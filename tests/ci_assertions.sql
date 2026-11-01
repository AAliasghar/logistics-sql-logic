-- Stops with an error when the warehouse output is wrong, so CI fails.
-- Needs the sqlcmd variable DataPath (the datasets folder as SQL Server sees it):
--   sqlcmd -d LogisticsDW -v DataPath=/repo/datasets -i tests/ci_assertions.sql
SET NOCOUNT ON;

CREATE TABLE #expected (
    carrier_code    NVARCHAR(10),
    shipments       INT,
    delivered       INT,
    on_time         INT,
    returned        INT,
    failed_attempts INT
);
BULK INSERT #expected
FROM '$(DataPath)/expected/carrier_metrics.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',');

IF NOT EXISTS (SELECT 1 FROM #expected)
    THROW 50001, 'expected/carrier_metrics.csv is empty or did not load', 1;

IF (SELECT COUNT(*) FROM gold.fact_shipments) <> (SELECT COUNT(*) FROM bronze.tms_shipments)
    THROW 50002, 'gold.fact_shipments does not have exactly one row per shipment', 1;

IF EXISTS (
    SELECT 1
    FROM silver.tms_tracking_events
    GROUP BY shipment_id, event_time, event_type
    HAVING COUNT(*) > 1
)
    THROW 50003, 'duplicate tracking events reached silver', 1;

-- COUNT, not EXISTS: EXISTS makes SQL Server pick a row-by-row plan for this view that takes minutes
IF (SELECT COUNT(*) FROM gold.fact_shipments WHERE final_status = N'IN_TRANSIT') > 0
    THROW 50004, 'a shipment has no final status (every generated shipment is delivered or returned)', 1;

-- The database ignores case in comparisons, so the counts below would not notice codes silver forgot
-- to upper-case. Check that case-sensitively here.
IF (
    SELECT COUNT(*) FROM silver.tms_shipments
    WHERE carrier_code COLLATE Latin1_General_CS_AS <> UPPER(carrier_code)
       OR service_level COLLATE Latin1_General_CS_AS <> UPPER(service_level)
       OR zone_code COLLATE Latin1_General_CS_AS <> UPPER(zone_code)
) > 0
    THROW 50006, 'silver.tms_shipments has codes that are not upper case', 1;

IF (
    SELECT COUNT(*) FROM silver.tms_tracking_events
    WHERE event_type COLLATE Latin1_General_CS_AS <> UPPER(event_type)
       OR DATALENGTH(event_type) <> DATALENGTH(TRIM(event_type))
       OR event_type LIKE N'%' + NCHAR(13) + N'%'  -- a line-ending character left over from the file
) > 0
    THROW 50007, 'silver.tms_tracking_events has event types that are not clean upper case', 1;

SELECT
    carrier_code,
    COUNT(*) AS shipments,
    SUM(CASE WHEN final_status = N'DELIVERED' THEN 1 ELSE 0 END) AS delivered,
    SUM(is_on_time) AS on_time,
    SUM(CASE WHEN final_status = N'RETURNED' THEN 1 ELSE 0 END) AS returned,
    SUM(failed_attempts) AS failed_attempts
INTO #actual
FROM gold.fact_shipments
GROUP BY carrier_code;

-- Rows in one table but not the other, in both directions
SELECT * INTO #differences FROM #expected
EXCEPT
SELECT * FROM #actual;

INSERT INTO #differences
SELECT * FROM #actual
EXCEPT
SELECT * FROM #expected;

IF EXISTS (SELECT 1 FROM #differences)
BEGIN
    SELECT * FROM #differences;
    THROW 50005, 'per-carrier counts in gold differ from datasets/expected/carrier_metrics.csv (rows above)', 1;
END;

DECLARE @shipments INT = (SELECT COUNT(*) FROM gold.fact_shipments);  -- PRINT does not allow subqueries
PRINT CONCAT(N'All CI assertions passed: ', @shipments, N' shipments, per-carrier counts equal the generator''s');
