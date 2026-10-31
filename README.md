# Logistics SQL Warehouse (T-SQL, Bronze / Silver / Gold)

[![CI](https://github.com/AAliasghar/logistics-sql-logic/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AAliasghar/logistics-sql-logic/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A SQL Server data warehouse built in three layers (**bronze → silver → gold**) from CSV exports of two source systems (a CRM and an ERP). The gold layer is a small star schema: customers, products and a shipment fact table with fuel and surcharge costs.

> **Status:** learning project. The warehouse structure and the customer/product/order data come from the well-known *SQL Data Warehouse Project* tutorial by Data with Baraa (based on Microsoft's AdventureWorks sample data). My extension is the shipment cost logic: fuel and surcharge columns carried from the source file through silver into the gold fact table, with a net amount per order line. All data is public sample data.

---

## What's inside

| Layer | Objects | What happens |
|---|---|---|
| **Bronze** | 6 tables, `bronze.load_bronze` | CSVs loaded as they are with `BULK INSERT` |
| **Silver** | 6 tables, `silver.load_silver` | Cleaning: trimmed names, standardised codes (gender, marital status, country, product line), invalid dates set to NULL, sales recalculated where `sales ≠ quantity × price`, latest record per customer |
| **Gold** | 3 views | `dim_customers` (CRM + ERP merged), `dim_products` (current products with category), `fact_shipments` |

`gold.fact_shipments` has one row per order line:

| Column | Meaning |
|---|---|
| `order_number`, `product_key`, `customer_key` | Order line and its dimensions |
| `order_date`, `shipping_date`, `due_date` | Dates |
| `sales_amount`, `quantity`, `price` | Revenue |
| `fuel_cost` | Fuel cost of the shipment (about 5% of sales in this data) |
| `surcharge` | Extra charge, set on a few shipments only (empty = none) |
| `net_amount` | `sales_amount − fuel_cost − surcharge` (empty values count as 0) |

## Data

`datasets/` holds the source files (about 116,000 rows):

| Source | File | Rows |
|---|---|--:|
| CRM | `source_crm/cust_info.csv` | 18,494 |
| CRM | `source_crm/prd_info.csv` | 397 |
| CRM | `source_crm/shipments_lmc_details.csv` (sales order lines + `sls_surcharge`, `sls_Fuel`) | 60,398 |
| ERP | `source_erp/CUST_AZ12.csv` | 18,484 |
| ERP | `source_erp/LOC_A101.csv` | 18,484 |
| ERP | `source_erp/PX_CAT_G1V2.csv` | 37 |

The fuel and surcharge columns are synthetic additions to the tutorial's sales file.

---

## Run it

**Requirements:** SQL Server 2017 or later (Developer or Express edition is fine) and SSMS, Azure Data Studio or `sqlcmd`.

> `scripts/init_database.sql` **drops and recreates** a database called `DataWarehouse`.

Run the scripts in this order:

```sql
-- 1. Database and schemas
:r scripts/init_database.sql

-- 2. Bronze: tables, load procedure, load
:r scripts/bronze/ddl_bronze.sql
:r scripts/bronze/proc_load_bronze.sql
EXEC bronze.load_bronze @data_path = N'C:\path\to\logistics-sql-logic\datasets';

-- 3. Silver
:r scripts/silver/ddl_silver.sql
:r scripts/silver/proc_load_silver.sql
EXEC silver.load_silver;

-- 4. Gold
:r scripts/gold/ddl_gold.sql
```

(`:r` works in SQLCMD mode; in SSMS you can also open each file and run it.)

`@data_path` is the `datasets` folder **as the SQL Server machine sees it**. With SQL Server in Docker, mount the folder into the container and use the container path, as the CI workflow does.

Example query: net amount by year and product category.

```sql
SELECT
    YEAR(f.order_date)  AS order_year,
    p.category,
    SUM(f.sales_amount) AS sales,
    SUM(f.fuel_cost)    AS fuel,
    SUM(f.net_amount)   AS net
FROM gold.fact_shipments f
JOIN gold.dim_products p ON p.product_key = f.product_key
GROUP BY YEAR(f.order_date), p.category
ORDER BY order_year, net DESC;
```

---

## Tests

- `tests/quality_checks_silver.sql`, `tests/quality_checks_gold.sql`: checks to read by hand (each query should return no rows): duplicates, unwanted spaces, invalid dates, `sales = quantity × price`, fact-to-dimension links.
- `tests/ci_assertions.sql`: stops with an error if the output is wrong (empty tables, missing shipment rows, fuel decimals lost, wrong `net_amount`).

**CI** (`.github/workflows/ci.yml`) starts SQL Server 2022 in Docker on every push and pull request, builds all three layers from the CSVs and runs the checks above.

---

## Project structure

```
logistics-sql-logic/
├── datasets/
│   ├── source_crm/          # customers, products, shipment order lines
│   └── source_erp/          # customer birthdates/gender, locations, product categories
├── scripts/
│   ├── init_database.sql    # DataWarehouse database + bronze/silver/gold schemas
│   ├── bronze/              # ddl_bronze.sql, proc_load_bronze.sql
│   ├── silver/              # ddl_silver.sql, proc_load_silver.sql
│   └── gold/                # ddl_gold.sql (views)
├── tests/                   # quality checks + CI assertions
├── .github/workflows/ci.yml
└── LICENSE
```

---

## Roadmap

- [ ] Replace the tutorial data with a generated shipments dataset (carriers, rate cards, weights, zones) so the cost logic is realistic, not a fixed share of sales
- [ ] Carrier rate-card table and a cost-per-shipment calculation
- [ ] `sqlfluff` style checks in CI

---

## License

MIT. See [LICENSE](LICENSE).

## Author

[AAliasghar](https://github.com/AAliasghar) · [Open an issue](https://github.com/AAliasghar/logistics-sql-logic/issues)
