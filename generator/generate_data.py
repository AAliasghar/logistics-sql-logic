"""
Synthetic logistics data: customers, carriers, zones, shipments and tracking events.

Every name and number here is invented. One random.Random drives everything in a
fixed order, so the same seed always gives the same data.
"""

import argparse
import csv
import random
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

# code -> (name, base on-time probability, share of shipments)
CARRIERS = {
    "NLP": ("NorthLine Parcel", 0.93, 0.30),
    "SWC": ("Swift Courier", 0.88, 0.30),
    "MTP": ("MetroPost", 0.85, 0.25),
    "VLF": ("Valley Freight", 0.80, 0.15),
}

# code -> (name, standard transit days)
ZONES = {
    "URB": ("Urban", 1),
    "SUB": ("Suburban", 2),
    "RUR": ("Rural", 3),
    "REM": ("Remote", 4),
}
ZONE_SHARES = {"URB": 0.40, "SUB": 0.30, "RUR": 0.20, "REM": 0.10}

REGIONS = ["North", "South", "East", "West", "Central"]

EXPRESS_SHARE = 0.25
PEAK_MONTHS = {11, 12}
PEAK_PENALTY = 0.08
REMOTE_PENALTY = 0.05
EARLY_SHARE = 0.20
FIRST_ATTEMPT_FAILS = 0.05
SECOND_ATTEMPT_FAILS = 0.20
RETURN_AFTER_DAYS = 3

START_DATE, END_DATE = date(2024, 1, 1), date(2025, 12, 31)
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "datasets"

# Share of rows that get each kind of deliberate dirt (exact counts, see add_dirt)
DUPLICATE_EVENTS = 0.01
MESSY_EVENT_TYPES = 0.03
LOWER_CASE_CARRIERS = 0.02
BLANK_WEIGHTS = 0.01
PADDED_CUSTOMER_NAMES = 0.02


def build_customers(rng: random.Random, n: int) -> list[dict]:
    return [
        {
            "customer_id": f"C{i:04d}",
            "customer_name": f"Customer {i:04d}",
            "segment": "WEB" if rng.random() < 0.70 else "B2B",
            "region": rng.choice(REGIONS),
        }
        for i in range(1, n + 1)
    ]


def _at(day: date, earliest_s: int, latest_s: int, rng: random.Random) -> datetime:
    """A random time on `day` between two offsets in seconds after midnight."""
    return datetime.combine(day, datetime.min.time()) + timedelta(seconds=rng.randint(earliest_s, latest_s))


def _first_attempt_date(rng, ship_date, promised_date, on_time_probability):
    if rng.random() < on_time_probability:
        day = promised_date - timedelta(days=1) if rng.random() < EARLY_SHARE else promised_date
        return max(day, ship_date + timedelta(days=1))
    return promised_date + timedelta(days=rng.randint(1, 3))


def simulate(
    rng: random.Random, customers: list[dict], n: int, start: date, end: date
) -> tuple[list[dict], list[dict]]:
    """Clean shipments and their tracking events, in time order per shipment."""
    carrier_codes = list(CARRIERS)
    carrier_weights = [CARRIERS[c][2] for c in carrier_codes]
    zone_codes = list(ZONE_SHARES)
    zone_weights = [ZONE_SHARES[z] for z in zone_codes]
    period_days = (end - start).days

    shipments, events = [], []
    for i in range(1, n + 1):
        shipment_id = f"S{i:06d}"
        ship_date = start + timedelta(days=rng.randint(0, period_days))
        carrier = rng.choices(carrier_codes, carrier_weights)[0]
        service = "EXP" if rng.random() < EXPRESS_SHARE else "STD"
        zone = rng.choices(zone_codes, zone_weights)[0]
        weight = round(min(30.0, max(0.2, rng.lognormvariate(0.7, 0.9))), 2)

        transit_days = ZONES[zone][1]
        if service == "EXP":
            transit_days = max(1, transit_days - 1)
        promised_date = ship_date + timedelta(days=transit_days)

        on_time_probability = CARRIERS[carrier][1]
        if ship_date.month in PEAK_MONTHS:
            on_time_probability -= PEAK_PENALTY
        if zone == "REM":
            on_time_probability -= REMOTE_PENALTY

        shipments.append(
            {
                "shipment_id": shipment_id,
                "customer_id": rng.choice(customers)["customer_id"],
                "carrier_code": carrier,
                "service_level": service,
                "zone_code": zone,
                "weight_kg": weight,
                "ship_date": ship_date,
                "promised_date": promised_date,
            }
        )

        picked_up = _at(ship_date, 8 * 3600, 18 * 3600, rng)
        in_transit = picked_up + timedelta(seconds=rng.randint(2 * 3600, 6 * 3600))
        shipment_events = [(picked_up, "PICKED_UP"), (in_transit, "IN_TRANSIT")]

        attempt_date = _first_attempt_date(rng, ship_date, promised_date, on_time_probability)
        for attempt, fail_probability in enumerate((FIRST_ATTEMPT_FAILS, SECOND_ATTEMPT_FAILS), start=1):
            shipment_events.append((_at(attempt_date, 7 * 3600, 9 * 3600, rng), "OUT_FOR_DELIVERY"))
            outcome_time = _at(attempt_date, 9 * 3600 + 1, 20 * 3600, rng)
            if rng.random() >= fail_probability:
                shipment_events.append((outcome_time, "DELIVERED"))
                break
            shipment_events.append((outcome_time, "DELIVERY_FAILED"))
            if attempt == 1:
                attempt_date += timedelta(days=1)
            else:
                returned_on = attempt_date + timedelta(days=RETURN_AFTER_DAYS)
                shipment_events.append((_at(returned_on, 10 * 3600, 16 * 3600, rng), "RETURNED"))

        events.extend(
            {"shipment_id": shipment_id, "event_time": time, "event_type": kind} for time, kind in shipment_events
        )
    return shipments, events


def expected_metrics(shipments: list[dict], events: list[dict]) -> list[dict]:
    """Per-carrier counts from clean data; the warehouse must arrive at the same numbers."""
    delivered_on, returned, failed = {}, set(), defaultdict(int)
    for e in events:
        if e["event_type"] == "DELIVERED":
            delivered_on[e["shipment_id"]] = e["event_time"].date()
        elif e["event_type"] == "RETURNED":
            returned.add(e["shipment_id"])
        elif e["event_type"] == "DELIVERY_FAILED":
            failed[e["shipment_id"]] += 1

    rows = {
        code: {"carrier_code": code, "shipments": 0, "delivered": 0, "on_time": 0, "returned": 0, "failed_attempts": 0}
        for code in sorted(CARRIERS)
    }
    for s in shipments:
        row = rows[s["carrier_code"]]
        sid = s["shipment_id"]
        row["shipments"] += 1
        row["failed_attempts"] += failed[sid]
        if sid in delivered_on:
            row["delivered"] += 1
            row["on_time"] += delivered_on[sid] <= s["promised_date"]
        if sid in returned:
            row["returned"] += 1
    return list(rows.values())


def _pick(rng: random.Random, rows: list, share: float) -> set[int]:
    """Indexes of exactly round(share x len(rows)) rows."""
    return set(rng.sample(range(len(rows)), round(share * len(rows))))


def _messy(rng: random.Random, value: str) -> str:
    """The same code in different case and/or with extra spaces; never equal to the original."""
    case = rng.choice([str.lower, str.title, str.upper])
    messy = " " * rng.randint(0, 2) + case(value) + " " * rng.randint(0, 2)
    return messy if messy != value else value.lower()


def add_dirt(
    rng: random.Random, customers: list[dict], shipments: list[dict], events: list[dict]
) -> tuple[list[dict], list[dict], list[dict]]:
    """Dirty copies of the clean data, for the silver layer to clean. The inputs are not changed."""
    customers = [dict(c) for c in customers]
    shipments = [dict(s) for s in shipments]

    duplicated = _pick(rng, events, DUPLICATE_EVENTS)
    dirty_events = []
    for i, event in enumerate(events):
        dirty_events.append(dict(event))
        if i in duplicated:
            dirty_events.append(dict(event))

    for i in _pick(rng, dirty_events, MESSY_EVENT_TYPES):
        dirty_events[i]["event_type"] = _messy(rng, dirty_events[i]["event_type"])
    for i in _pick(rng, shipments, LOWER_CASE_CARRIERS):
        shipments[i]["carrier_code"] = shipments[i]["carrier_code"].lower()
    for i in _pick(rng, shipments, BLANK_WEIGHTS):
        shipments[i]["weight_kg"] = None
    for i in _pick(rng, customers, PADDED_CUSTOMER_NAMES):
        customers[i]["customer_name"] = " " * rng.randint(1, 2) + customers[i]["customer_name"] + " " * rng.randint(1, 2)

    return customers, shipments, dirty_events


def _write(path: Path, columns: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\r\n")  # CRLF: what BULK INSERT expects by default
        writer.writerow(columns)
        for row in rows:
            writer.writerow([_text(row[c]) for c in columns])


def _text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


def generate(seed: int, out_dir: Path, n_shipments: int = 20000, n_customers: int = 300) -> None:
    """Write the source CSVs and the expected per-carrier metrics to out_dir."""
    rng = random.Random(seed)
    customers = build_customers(rng, n_customers)
    shipments, events = simulate(rng, customers, n_shipments, START_DATE, END_DATE)
    metrics = expected_metrics(shipments, events)  # from clean data, before the dirt
    customers, shipments, events = add_dirt(rng, customers, shipments, events)

    out_dir = Path(out_dir)
    _write(out_dir / "source_crm/customers.csv", ["customer_id", "customer_name", "segment", "region"], customers)
    _write(
        out_dir / "source_tms/carriers.csv",
        ["carrier_code", "carrier_name"],
        [{"carrier_code": code, "carrier_name": name} for code, (name, _, _) in CARRIERS.items()],
    )
    _write(
        out_dir / "source_tms/zones.csv",
        ["zone_code", "zone_name", "standard_transit_days"],
        [{"zone_code": code, "zone_name": name, "standard_transit_days": days} for code, (name, days) in ZONES.items()],
    )
    _write(
        out_dir / "source_tms/shipments.csv",
        ["shipment_id", "customer_id", "carrier_code", "service_level", "zone_code", "weight_kg", "ship_date", "promised_date"],
        shipments,
    )
    _write(out_dir / "source_tms/tracking_events.csv", ["shipment_id", "event_time", "event_type"], events)
    _write(
        out_dir / "expected/carrier_metrics.csv",
        ["carrier_code", "shipments", "delivered", "on_time", "returned", "failed_attempts"],
        metrics,
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Generate the synthetic logistics dataset.")
    parser.add_argument("--seed", type=int, default=42, help="random seed (the committed data uses 42)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output folder (default: the repo's datasets/)")
    args = parser.parse_args(argv)
    generate(args.seed, args.out)
    print(f"Wrote dataset with seed {args.seed} to {args.out}")


if __name__ == "__main__":
    main()
