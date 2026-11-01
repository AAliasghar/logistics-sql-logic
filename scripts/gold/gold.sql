-- Gold layer: views for reporting carrier delivery performance.
-- Run in LogisticsDW after silver.sql. Views read silver directly, so they are always current.

CREATE OR ALTER VIEW gold.dim_customers AS
SELECT customer_id, customer_name, segment, region
FROM silver.crm_customers;
GO

CREATE OR ALTER VIEW gold.dim_carriers AS
SELECT carrier_code, carrier_name
FROM silver.tms_carriers;
GO

CREATE OR ALTER VIEW gold.dim_zones AS
SELECT zone_code, zone_name, standard_transit_days
FROM silver.tms_zones;
GO

-- One row per shipment: what was promised and what happened.
CREATE OR ALTER VIEW gold.fact_shipments AS
WITH event_summary AS (
    SELECT
        shipment_id,
        SUM(CASE WHEN event_type = N'OUT_FOR_DELIVERY' THEN 1 ELSE 0 END) AS attempts,
        SUM(CASE WHEN event_type = N'DELIVERY_FAILED' THEN 1 ELSE 0 END) AS failed_attempts,
        MIN(CASE WHEN event_type = N'OUT_FOR_DELIVERY' THEN CAST(event_time AS DATE) END) AS first_attempt_date,
        MAX(CASE WHEN event_type = N'DELIVERED' THEN CAST(event_time AS DATE) END) AS delivered_date
    FROM silver.tms_tracking_events
    GROUP BY shipment_id
),
latest_event AS (
    SELECT
        shipment_id,
        event_type,
        ROW_NUMBER() OVER (
            PARTITION BY shipment_id
            -- On a tie in time, a final event wins over an intermediate one
            ORDER BY event_time DESC,
                CASE event_type WHEN N'RETURNED' THEN 1 WHEN N'DELIVERED' THEN 2 ELSE 3 END
        ) AS position_from_last
    FROM silver.tms_tracking_events
)
SELECT
    s.shipment_id,
    s.customer_id,
    s.carrier_code,
    s.zone_code,
    s.service_level,
    s.weight_kg,
    s.ship_date,
    s.promised_date,
    e.first_attempt_date,
    e.delivered_date,
    ISNULL(e.attempts, 0) AS attempts,
    ISNULL(e.failed_attempts, 0) AS failed_attempts,
    CASE l.event_type
        WHEN N'DELIVERED' THEN N'DELIVERED'
        WHEN N'RETURNED' THEN N'RETURNED'
        ELSE N'IN_TRANSIT'
    END AS final_status,
    CASE WHEN l.event_type = N'DELIVERED' THEN DATEDIFF(DAY, s.ship_date, e.delivered_date) END AS transit_days,
    CASE WHEN l.event_type = N'DELIVERED' AND e.delivered_date <= s.promised_date THEN 1 ELSE 0 END AS is_on_time
FROM silver.tms_shipments AS s
LEFT JOIN event_summary AS e
    ON e.shipment_id = s.shipment_id
LEFT JOIN latest_event AS l
    ON l.shipment_id = s.shipment_id
    AND l.position_from_last = 1;
GO

-- Carrier x zone x ship month: the numbers a carrier review starts from.
CREATE OR ALTER VIEW gold.rpt_carrier_performance AS
SELECT
    carrier_code,
    zone_code,
    DATEFROMPARTS(YEAR(ship_date), MONTH(ship_date), 1) AS ship_month,
    COUNT(*) AS shipments,
    CAST(100.0 * SUM(is_on_time) / COUNT(*) AS DECIMAL(5, 1)) AS on_time_pct,
    CAST(AVG(CAST(transit_days AS DECIMAL(6, 2))) AS DECIMAL(4, 2)) AS avg_transit_days,
    CAST(100.0 * SUM(CASE WHEN failed_attempts > 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS failed_attempt_pct,
    CAST(100.0 * SUM(CASE WHEN final_status = N'RETURNED' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS return_pct
FROM gold.fact_shipments
GROUP BY carrier_code, zone_code, DATEFROMPARTS(YEAR(ship_date), MONTH(ship_date), 1);
GO
