-- Checks to read by hand after gold.sql. Every query should return no rows.

-- Delivered before it was shipped
SELECT shipment_id, ship_date, delivered_date
FROM gold.fact_shipments
WHERE delivered_date < ship_date;

-- Counted as on time but not delivered
SELECT shipment_id, final_status, is_on_time
FROM gold.fact_shipments
WHERE is_on_time = 1 AND final_status <> N'DELIVERED';

-- More failed attempts than attempts
SELECT shipment_id, attempts, failed_attempts
FROM gold.fact_shipments
WHERE failed_attempts > attempts;

-- Fact rows whose customer, carrier or zone is missing from the dimensions
SELECT f.shipment_id
FROM gold.fact_shipments AS f
LEFT JOIN gold.dim_customers AS c ON c.customer_id = f.customer_id
LEFT JOIN gold.dim_carriers AS k ON k.carrier_code = f.carrier_code
LEFT JOIN gold.dim_zones AS z ON z.zone_code = f.zone_code
WHERE c.customer_id IS NULL OR k.carrier_code IS NULL OR z.zone_code IS NULL;

-- Report percentages outside 0-100
SELECT carrier_code, zone_code, ship_month, on_time_pct, failed_attempt_pct, return_pct
FROM gold.rpt_carrier_performance
WHERE on_time_pct NOT BETWEEN 0 AND 100
   OR failed_attempt_pct NOT BETWEEN 0 AND 100
   OR return_pct NOT BETWEEN 0 AND 100;
