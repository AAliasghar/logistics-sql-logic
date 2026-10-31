/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    This stored procedure loads data into the 'bronze' schema from external CSV files.
    It performs the following actions:
    - Truncates the bronze tables before loading data.
    - Uses the `BULK INSERT` command to load data from csv Files to bronze tables.

Parameters:
    @data_path  Folder that holds source_crm/ and source_erp/, as the SQL Server
                machine sees it (no trailing slash).

Usage Example:
    EXEC bronze.load_bronze @data_path = N'C:\path\to\logistics-sql-logic\datasets';
===============================================================================
*/

CREATE OR ALTER PROCEDURE bronze.load_bronze @data_path NVARCHAR(400) AS
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	DECLARE @sql NVARCHAR(MAX);
	-- BULK INSERT does not accept a variable as the file name, so each load is built as dynamic SQL.
	-- Forward slashes work on both Windows and Linux SQL Server.
	DECLARE @options NVARCHAR(200) = N''' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', TABLOCK);';
	BEGIN TRY
		SET @batch_start_time = GETDATE();
		PRINT '================================================';
		PRINT 'Loading Bronze Layer';
		PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '------------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.crm_cust_info';
		TRUNCATE TABLE bronze.crm_cust_info;
		PRINT '>> Inserting Data Into: bronze.crm_cust_info';
		SET @sql = N'BULK INSERT bronze.crm_cust_info FROM ''' + @data_path + N'/source_crm/cust_info.csv' + @options;
		EXEC sp_executesql @sql;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.crm_prd_info';
		TRUNCATE TABLE bronze.crm_prd_info;
		PRINT '>> Inserting Data Into: bronze.crm_prd_info';
		SET @sql = N'BULK INSERT bronze.crm_prd_info FROM ''' + @data_path + N'/source_crm/prd_info.csv' + @options;
		EXEC sp_executesql @sql;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.crm_shipments_lmc_details';
		TRUNCATE TABLE bronze.crm_shipments_lmc_details;
		PRINT '>> Inserting Data Into: bronze.crm_shipments_lmc_details';
		SET @sql = N'BULK INSERT bronze.crm_shipments_lmc_details FROM ''' + @data_path + N'/source_crm/shipments_lmc_details.csv' + @options;
		EXEC sp_executesql @sql;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

		PRINT '------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '------------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.erp_loc_a101';
		TRUNCATE TABLE bronze.erp_loc_a101;
		PRINT '>> Inserting Data Into: bronze.erp_loc_a101';
		SET @sql = N'BULK INSERT bronze.erp_loc_a101 FROM ''' + @data_path + N'/source_erp/LOC_A101.csv' + @options;
		EXEC sp_executesql @sql;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.erp_cust_az12';
		TRUNCATE TABLE bronze.erp_cust_az12;
		PRINT '>> Inserting Data Into: bronze.erp_cust_az12';
		SET @sql = N'BULK INSERT bronze.erp_cust_az12 FROM ''' + @data_path + N'/source_erp/CUST_AZ12.csv' + @options;
		EXEC sp_executesql @sql;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.erp_px_cat_g1v2';
		TRUNCATE TABLE bronze.erp_px_cat_g1v2;
		PRINT '>> Inserting Data Into: bronze.erp_px_cat_g1v2';
		SET @sql = N'BULK INSERT bronze.erp_px_cat_g1v2 FROM ''' + @data_path + N'/source_erp/PX_CAT_G1V2.csv' + @options;
		EXEC sp_executesql @sql;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Bronze Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='
	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '==========================================';
		THROW; -- re-raise, so the caller (and CI) sees the load failed
	END CATCH
END
