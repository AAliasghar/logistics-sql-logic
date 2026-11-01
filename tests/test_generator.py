"""Tests for the synthetic shipments generator. No network, no database."""

import random
from collections import defaultdict
from datetime import date, timedelta

import pytest

from generator.generate_data import CARRIERS, ZONES, build_customers, expected_metrics, simulate

START, END = date(2024, 1, 1), date(2025, 12, 31)


@pytest.fixture(scope="module")
def data():
    rng = random.Random(42)
    customers = build_customers(rng, 300)
    shipments, events = simulate(rng, customers, 20_000, START, END)
    return customers, shipments, events


def events_by_shipment(events):
    grouped = defaultdict(list)
    for event in events:
        grouped[event["shipment_id"]].append(event)
    return grouped


def test_every_shipment_references_existing_customer_carrier_zone(data):
    customers, shipments, _ = data
    customer_ids = {c["customer_id"] for c in customers}
    for s in shipments:
        assert s["customer_id"] in customer_ids
        assert s["carrier_code"] in CARRIERS
        assert s["zone_code"] in ZONES


def test_each_shipment_has_exactly_one_final_event_and_it_is_last(data):
    _, shipments, events = data
    grouped = events_by_shipment(events)
    assert len(grouped) == len(shipments)
    for shipment_events in grouped.values():
        finals = [e for e in shipment_events if e["event_type"] in ("DELIVERED", "RETURNED")]
        assert len(finals) == 1
        assert max(shipment_events, key=lambda e: e["event_time"]) is finals[0]


def test_event_times_strictly_increase_per_shipment(data):
    _, _, events = data
    for shipment_events in events_by_shipment(events).values():
        times = [e["event_time"] for e in shipment_events]
        assert all(a < b for a, b in zip(times, times[1:]))


def test_first_attempt_is_never_before_the_day_after_shipping(data):
    _, shipments, events = data
    grouped = events_by_shipment(events)
    for s in shipments:
        first = min(
            e["event_time"].date() for e in grouped[s["shipment_id"]] if e["event_type"] == "OUT_FOR_DELIVERY"
        )
        assert first >= s["ship_date"] + timedelta(days=1)


def test_on_time_rate_per_carrier_is_plausible(data):
    _, shipments, events = data
    rates = {m["carrier_code"]: m["on_time"] / m["shipments"] for m in expected_metrics(shipments, events)}
    assert set(rates) == set(CARRIERS)
    for code, rate in rates.items():
        assert 0.70 <= rate <= 0.97, (code, rate)
    assert rates["NLP"] > rates["VLF"]


def test_expected_metrics_add_up(data):
    _, shipments, events = data
    metrics = expected_metrics(shipments, events)
    assert sum(m["shipments"] for m in metrics) == 20_000
    for m in metrics:
        assert m["delivered"] + m["returned"] == m["shipments"]
        assert m["on_time"] <= m["delivered"]


# --- Task 2: dirty data and files -------------------------------------------------

import csv
import copy

from generator.generate_data import add_dirt, generate

FILES = [
    "source_crm/customers.csv",
    "source_tms/carriers.csv",
    "source_tms/zones.csv",
    "source_tms/shipments.csv",
    "source_tms/tracking_events.csv",
    "expected/carrier_metrics.csv",
]


@pytest.fixture(scope="module")
def generated(tmp_path_factory):
    out = tmp_path_factory.mktemp("seed42")
    generate(42, out)
    return out


def read_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def test_same_seed_gives_identical_files(generated, tmp_path):
    generate(42, tmp_path)
    for name in FILES:
        assert (tmp_path / name).read_bytes() == (generated / name).read_bytes(), name


def test_different_seed_gives_different_shipments(generated, tmp_path):
    generate(7, tmp_path)
    name = "source_tms/shipments.csv"
    assert (tmp_path / name).read_bytes() != (generated / name).read_bytes()


def test_files_are_crlf_ascii_without_bom(generated):
    for name in FILES:
        raw = (generated / name).read_bytes()
        assert raw.count(b"\n") == raw.count(b"\r\n"), name
        assert raw.isascii(), name
        assert not raw.startswith(b"\xef\xbb\xbf"), name


def near(actual, total, share):
    return 0.5 * share * total <= actual <= 1.5 * share * total


def test_dirt_shares_are_near_targets(generated):
    events = read_rows(generated / "source_tms/tracking_events.csv")
    shipments = read_rows(generated / "source_tms/shipments.csv")
    customers = read_rows(generated / "source_crm/customers.csv")

    normalised = [(e["shipment_id"], e["event_time"], e["event_type"].strip().upper()) for e in events]
    duplicates = len(normalised) - len(set(normalised))
    clean_events = len(set(normalised))
    assert near(duplicates, clean_events, 0.01)
    assert near(sum(e["event_type"] != e["event_type"].strip().upper() for e in events), len(events), 0.03)
    assert near(sum(s["carrier_code"] != s["carrier_code"].upper() for s in shipments), len(shipments), 0.02)
    assert near(sum(s["weight_kg"] == "" for s in shipments), len(shipments), 0.01)
    assert near(sum(c["customer_name"] != c["customer_name"].strip() for c in customers), len(customers), 0.02)


def test_add_dirt_does_not_change_its_inputs(data):
    customers, shipments, events = data
    before = copy.deepcopy((customers, shipments, events))
    add_dirt(random.Random(1), customers, shipments, events)
    assert (customers, shipments, events) == before
