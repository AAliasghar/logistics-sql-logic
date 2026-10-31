/*
===============================================================================
CI Assertions
===============================================================================
Script Purpose:
    Unlike the quality_checks_*.sql scripts (which return rows for a person to
    read), this script stops with an error when the pipeline output is wrong,
    so CI fails. Run it after the gold views are created.
===============================================================================
*/

DECLARE @bronze_rows INT = (SELECT COUNT(*) FROM bronze.crm_shipments_lmc_details);
DECLARE @fact_rows   INT = (SELECT COUNT(*) FROM gold.fact_shipments);

IF @bronze_rows = 0
    THROW 50001, 'bronze.crm_shipments_lmc_details is empty: the CSV did not load', 1;

IF @fact_rows <> @bronze_rows
    THROW 50002, 'gold.fact_shipments does not have one row per bronze shipment row', 1;

IF NOT EXISTS (SELECT 1 FROM gold.dim_customers)
    THROW 50003, 'gold.dim_customers is empty', 1;

IF NOT EXISTS (SELECT 1 FROM gold.dim_products)
    THROW 50004, 'gold.dim_products is empty', 1;

-- Fuel is a decimal cost (e.g. 178.90); an INT column would round or reject it
IF NOT EXISTS (SELECT 1 FROM silver.crm_shipments_lmc_details WHERE sls_fuel <> ROUND(sls_fuel, 0))
    THROW 50005, 'sls_fuel lost its decimals', 1;

IF EXISTS (
    SELECT 1 FROM gold.fact_shipments
    WHERE net_amount <> sales_amount - ISNULL(fuel_cost, 0) - ISNULL(surcharge, 0)
)
    THROW 50006, 'net_amount does not equal sales - fuel - surcharge', 1;

PRINT 'All CI assertions passed: '
    + CAST(@fact_rows AS NVARCHAR) + ' shipment rows in gold.fact_shipments';
