# Logistics SQL Warehouse: Carrier Delivery Performance

[![CI](https://github.com/AAliasghar/logistics-sql-logic/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AAliasghar/logistics-sql-logic/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A SQL Server data warehouse in T-SQL (**bronze → silver → gold**) that measures how well parcel carriers deliver: on-time rate, transit days, failed delivery attempts and returns, per carrier, zone and month.

The data is **synthetic**: a Python generator in this repo creates customers, carriers, zones, 20,000 shipments and their tracking events, with some deliberately messy records for the warehouse to clean. Every name and number is invented.

---

## Results (committed data, seed 42)

| Carrier | Shipments | On time | Returned | Failed delivery attempts |
|---|--:|--:|--:|--:|
| NLP NorthLine Parcel | 6,046 | 87.4% | 63 | 356 |
| SWC Swift Courier | 5,958 | 81.8% | 63 | 367 |
| MTP MetroPost | 4,989 | 79.5% | 50 | 324 |
| VLF Valley Freight | 3,007 | 75.0% | 35 | 180 |

CI builds the warehouse from the CSV files and checks that these counts come out of `gold.fact_shipments` exactly, after all the cleaning.

---

## The data

`generator/generate_data.py` (Python standard library only) writes:

| File | Rows | Content |
|---|--:|---|
| `datasets/source_crm/customers.csv` | 300 | customer id, name, segment (webshop / B2B), region |
| `datasets/source_tms/carriers.csv` | 4 | carrier code and name |
| `datasets/source_tms/zones.csv` | 4 | urban, suburban, rural, remote, with standard transit days |
| `datasets/source_tms/shipments.csv` | 20,000 | customer, carrier, service level, zone, weight, ship date, promised date (2024–2025) |
| `datasets/source_tms/tracking_events.csv` | 83,065 | picked up → in transit → out for delivery → delivered / delivery failed → returned |
| `datasets/expected/carrier_metrics.csv` | 4 | the generator's own per-carrier counts, used by CI |

**How deliveries behave:** each carrier has its own on-time rate; deliveries are slower in November–December and to remote zones; about 5% of first attempts fail and get a second attempt the next day; if that fails too, the parcel is returned.

**Deliberately messy records:** duplicate tracking events (1%), event types in mixed case or with extra spaces (3%), lower-case carrier codes (2%), blank weights (1%), customer names with extra spaces (2%).

Regenerate (the committed files use seed 42; CI fails if they don't match):

```bash
python generator/generate_data.py            # writes datasets/
python generator/generate_data.py --seed 7   # different data, same shape (don't commit it)
```

---

## The warehouse

| Layer | File | What happens |
|---|---|---|
| Bronze | `scripts/bronze/bronze.sql` | Five tables, loaded from the CSVs as they are with `BULK INSERT` |
| Silver | `scripts/silver/silver.sql` | Trims text, upper-cases codes, converts event times, removes duplicate events (after normalising them) |
| Gold | `scripts/gold/gold.sql` | Views for reporting (below) |

| Gold view | One row per | Content |
|---|---|---|
| `dim_customers`, `dim_carriers`, `dim_zones` | customer / carrier / zone | descriptive columns |
| `fact_shipments` | shipment | promised date, first attempt, delivered date, attempts, failed attempts, final status, transit days, on time yes/no |
| `rpt_carrier_performance` | carrier × zone × month | shipments, on-time %, average transit days, failed-attempt %, return % |

A shipment's final status comes from its latest tracking event (`ROW_NUMBER()` per shipment). It counts as **on time** when it was delivered (not returned) on or before the promised date.

---

## Run it

**Requirements:** SQL Server 2017 or later (Developer or Express edition is fine), plus SSMS, Azure Data Studio or `sqlcmd`.

> `scripts/database.sql` **drops and recreates** the database `LogisticsDW`.

Run in this order:

```sql
:r scripts/database.sql
USE LogisticsDW;
:r scripts/bronze/bronze.sql
:r scripts/silver/silver.sql
:r scripts/gold/gold.sql

EXEC bronze.load_bronze @data_path = N'C:\path\to\logistics-sql-logic\datasets';
EXEC silver.load_silver;
```

`:r` needs SQLCMD mode; in SSMS you can also open and run each file. `@data_path` is the `datasets` folder **as the SQL Server machine sees it** (for SQL Server in Docker, mount the folder and use the container path, as CI does).

On-time rate per carrier in 2025:

```sql
SELECT
    c.carrier_name,
    COUNT(*) AS shipments,
    CAST(100.0 * SUM(f.is_on_time) / COUNT(*) AS DECIMAL(5, 1)) AS on_time_pct
FROM gold.fact_shipments AS f
JOIN gold.dim_carriers AS c ON c.carrier_code = f.carrier_code
WHERE f.ship_date >= '2025-01-01'
GROUP BY c.carrier_name
ORDER BY on_time_pct DESC;
```

---

## Tests and CI

- `tests/test_generator.py` (pytest): the same seed gives identical files; every shipment points to a real customer, carrier and zone; every shipment ends delivered or returned; event times always move forward; on-time rates are plausible; files are CRLF and ASCII; the messy-record shares are close to their targets.
- `tests/ci_assertions.sql`: stops with an error if a shipment is missing from gold, a duplicate event reaches silver, a shipment has no final status, or the per-carrier counts differ from `datasets/expected/carrier_metrics.csv`.
- `tests/quality_checks_silver.sql`, `tests/quality_checks_gold.sql`: checks to read by hand; each query should return no rows.

**CI** (`.github/workflows/ci.yml`) runs on pushes to `main` and on pull requests into `main`: generator tests, a check that the committed data matches the generator, then SQL Server 2022 in Docker builds all three layers (loading twice, to prove a rerun adds no duplicates) and runs `ci_assertions.sql`. The two quality-check scripts also run there, but only to prove they work; their results are meant to be read by hand.

---

## Project structure

```
logistics-sql-logic/
├── generator/generate_data.py   # synthetic data generator
├── datasets/                    # generated CSVs (committed)
├── scripts/
│   ├── database.sql             # LogisticsDW + bronze/silver/gold schemas
│   ├── bronze/bronze.sql
│   ├── silver/silver.sql
│   └── gold/gold.sql
├── tests/                       # pytest + SQL checks
├── .github/workflows/ci.yml
└── LICENSE
```

---

## Roadmap

- [ ] Shipping costs: carrier rate cards by weight and zone, cost per shipment and per carrier
- [ ] `sqlfluff` style checks in CI

---

## License

MIT. See [LICENSE](LICENSE).

## Author

[AAliasghar](https://github.com/AAliasghar) · [Open an issue](https://github.com/AAliasghar/logistics-sql-logic/issues)
