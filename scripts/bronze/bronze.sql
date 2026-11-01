-- Bronze layer: the CSV files loaded as they are, dirt included.
-- Run in LogisticsDW, then: EXEC bronze.load_bronze @data_path = N'<folder that holds source_crm and source_tms>';

DROP TABLE IF EXISTS bronze.crm_customers;
CREATE TABLE bronze.crm_customers (
    customer_id   NVARCHAR(10),
    customer_name NVARCHAR(100),
    segment       NVARCHAR(10),
    region        NVARCHAR(20)
);

DROP TABLE IF EXISTS bronze.tms_carriers;
CREATE TABLE bronze.tms_carriers (
    carrier_code NVARCHAR(10),
    carrier_name NVARCHAR(50)
);

DROP TABLE IF EXISTS bronze.tms_zones;
CREATE TABLE bronze.tms_zones (
    zone_code             NVARCHAR(10),
    zone_name             NVARCHAR(20),
    standard_transit_days INT
);

DROP TABLE IF EXISTS bronze.tms_shipments;
CREATE TABLE bronze.tms_shipments (
    shipment_id   NVARCHAR(10),
    customer_id   NVARCHAR(10),
    carrier_code  NVARCHAR(10),
    service_level NVARCHAR(10),
    zone_code     NVARCHAR(10),
    weight_kg     DECIMAL(6, 2) NULL,  -- blank in the file -> NULL
    ship_date     DATE,
    promised_date DATE
);

DROP TABLE IF EXISTS bronze.tms_tracking_events;
CREATE TABLE bronze.tms_tracking_events (
    shipment_id NVARCHAR(10),
    event_time  NVARCHAR(30),  -- converted in silver
    event_type  NVARCHAR(40)   -- may have mixed case and extra spaces
);
GO

-- Empties one bronze table and fills it from one CSV file.
CREATE OR ALTER PROCEDURE bronze.load_file
    @table SYSNAME,
    @file  NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @target NVARCHAR(300) = N'bronze.' + QUOTENAME(@table);
    DECLARE @sql NVARCHAR(MAX) =
        N'TRUNCATE TABLE ' + @target + N'; '
        + N'BULK INSERT ' + @target
        + N' FROM ''' + REPLACE(@file, N'''', N'''''') + N''''
        + N' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', TABLOCK);';
    EXEC sys.sp_executesql @sql;

    DECLARE @rows INT;
    SET @sql = N'SELECT @n = COUNT(*) FROM ' + @target + N';';
    EXEC sys.sp_executesql @sql, N'@n INT OUTPUT', @n = @rows OUTPUT;
    PRINT CONCAT(@target, N': ', @rows, N' rows from ', @file);
END;
GO

-- Loads all five source files. @data_path is the datasets folder as the SQL Server
-- machine sees it; a trailing / or \ is fine.
CREATE OR ALTER PROCEDURE bronze.load_bronze
    @data_path NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    WHILE RIGHT(@data_path, 1) IN (N'/', N'\')
        SET @data_path = LEFT(@data_path, LEN(@data_path) - 1);

    DECLARE @file NVARCHAR(400);

    SET @file = @data_path + N'/source_crm/customers.csv';
    EXEC bronze.load_file @table = N'crm_customers', @file = @file;

    SET @file = @data_path + N'/source_tms/carriers.csv';
    EXEC bronze.load_file @table = N'tms_carriers', @file = @file;

    SET @file = @data_path + N'/source_tms/zones.csv';
    EXEC bronze.load_file @table = N'tms_zones', @file = @file;

    SET @file = @data_path + N'/source_tms/shipments.csv';
    EXEC bronze.load_file @table = N'tms_shipments', @file = @file;

    SET @file = @data_path + N'/source_tms/tracking_events.csv';
    EXEC bronze.load_file @table = N'tms_tracking_events', @file = @file;
END;
GO
