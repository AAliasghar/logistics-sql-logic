-- Silver layer: bronze data cleaned and typed.
-- Run in LogisticsDW after bronze.sql, then: EXEC silver.load_silver;

DROP TABLE IF EXISTS silver.crm_customers;
CREATE TABLE silver.crm_customers (
    customer_id   NVARCHAR(10)  NOT NULL,
    customer_name NVARCHAR(100) NOT NULL,
    segment       NVARCHAR(10)  NOT NULL,
    region        NVARCHAR(20)  NOT NULL,
    loaded_at     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

DROP TABLE IF EXISTS silver.tms_carriers;
CREATE TABLE silver.tms_carriers (
    carrier_code NVARCHAR(10) NOT NULL,
    carrier_name NVARCHAR(50) NOT NULL,
    loaded_at    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

DROP TABLE IF EXISTS silver.tms_zones;
CREATE TABLE silver.tms_zones (
    zone_code             NVARCHAR(10) NOT NULL,
    zone_name             NVARCHAR(20) NOT NULL,
    standard_transit_days INT          NOT NULL,
    loaded_at             DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

DROP TABLE IF EXISTS silver.tms_shipments;
CREATE TABLE silver.tms_shipments (
    shipment_id   NVARCHAR(10)  NOT NULL,
    customer_id   NVARCHAR(10)  NOT NULL,
    carrier_code  NVARCHAR(10)  NOT NULL,
    service_level NVARCHAR(10)  NOT NULL,
    zone_code     NVARCHAR(10)  NOT NULL,
    weight_kg     DECIMAL(6, 2) NULL,  -- unknown weight stays NULL
    ship_date     DATE          NOT NULL,
    promised_date DATE          NOT NULL,
    loaded_at     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

DROP TABLE IF EXISTS silver.tms_tracking_events;
CREATE TABLE silver.tms_tracking_events (
    shipment_id NVARCHAR(10) NOT NULL,
    event_time  DATETIME2(0) NULL,  -- NULL if the text could not be read as a time
    event_type  NVARCHAR(30) NOT NULL,
    loaded_at   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

-- Events stored per shipment in time order: gold reads them exactly this way
CREATE CLUSTERED INDEX cx_tms_tracking_events ON silver.tms_tracking_events (shipment_id, event_time);
CREATE UNIQUE CLUSTERED INDEX cx_tms_shipments ON silver.tms_shipments (shipment_id);
GO

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    TRUNCATE TABLE silver.crm_customers;
    INSERT INTO silver.crm_customers (customer_id, customer_name, segment, region)
    SELECT TRIM(customer_id), TRIM(customer_name), UPPER(TRIM(segment)), TRIM(region)
    FROM bronze.crm_customers;
    PRINT CONCAT(N'silver.crm_customers: ', @@ROWCOUNT, N' rows');

    TRUNCATE TABLE silver.tms_carriers;
    INSERT INTO silver.tms_carriers (carrier_code, carrier_name)
    SELECT UPPER(TRIM(carrier_code)), TRIM(carrier_name)
    FROM bronze.tms_carriers;
    PRINT CONCAT(N'silver.tms_carriers: ', @@ROWCOUNT, N' rows');

    TRUNCATE TABLE silver.tms_zones;
    INSERT INTO silver.tms_zones (zone_code, zone_name, standard_transit_days)
    SELECT UPPER(TRIM(zone_code)), TRIM(zone_name), standard_transit_days
    FROM bronze.tms_zones;
    PRINT CONCAT(N'silver.tms_zones: ', @@ROWCOUNT, N' rows');

    TRUNCATE TABLE silver.tms_shipments;
    INSERT INTO silver.tms_shipments (
        shipment_id, customer_id, carrier_code, service_level, zone_code, weight_kg, ship_date, promised_date
    )
    SELECT
        TRIM(shipment_id),
        TRIM(customer_id),
        UPPER(TRIM(carrier_code)),   -- some rows arrive as 'nlp'
        UPPER(TRIM(service_level)),
        UPPER(TRIM(zone_code)),
        weight_kg,
        ship_date,
        promised_date
    FROM bronze.tms_shipments;
    PRINT CONCAT(N'silver.tms_shipments: ', @@ROWCOUNT, N' rows');

    -- Normalise first, then remove duplicates: a duplicate row may also carry case or space dirt.
    TRUNCATE TABLE silver.tms_tracking_events;
    INSERT INTO silver.tms_tracking_events (shipment_id, event_time, event_type)
    SELECT DISTINCT
        TRIM(shipment_id),
        TRY_CONVERT(DATETIME2(0), TRIM(event_time), 120),
        UPPER(TRIM(event_type))
    FROM bronze.tms_tracking_events;
    PRINT CONCAT(N'silver.tms_tracking_events: ', @@ROWCOUNT, N' rows');
END;
GO
