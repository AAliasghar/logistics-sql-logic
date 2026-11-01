-- Creates the LogisticsDW database with one schema per layer.
-- Warning: if LogisticsDW already exists, it is dropped first and all its data is lost.

USE master;
GO

IF DB_ID(N'LogisticsDW') IS NOT NULL
BEGIN
    ALTER DATABASE LogisticsDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE LogisticsDW;
END;
GO

CREATE DATABASE LogisticsDW;
GO

USE LogisticsDW;
GO

CREATE SCHEMA bronze;  -- raw copies of the CSV files
GO
CREATE SCHEMA silver;  -- cleaned and typed
GO
CREATE SCHEMA gold;    -- views for reporting
GO
