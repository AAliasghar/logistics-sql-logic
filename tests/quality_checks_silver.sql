-- Checks to read by hand after silver.load_silver. Every query should return no rows.

-- Text that still has spaces around it
SELECT customer_id, customer_name
FROM silver.crm_customers
WHERE DATALENGTH(customer_name) <> DATALENGTH(TRIM(customer_name));

-- Codes that are not upper case (case-sensitive comparison)
SELECT shipment_id, carrier_code, service_level, zone_code
FROM silver.tms_shipments
WHERE carrier_code COLLATE Latin1_General_CS_AS <> UPPER(carrier_code)
   OR service_level COLLATE Latin1_General_CS_AS <> UPPER(service_level)
   OR zone_code COLLATE Latin1_General_CS_AS <> UPPER(zone_code);

-- Event times that could not be read
SELECT shipment_id, event_type
FROM silver.tms_tracking_events
WHERE event_time IS NULL;

-- Event types outside the known list
SELECT DISTINCT event_type
FROM silver.tms_tracking_events
WHERE event_type NOT IN (N'PICKED_UP', N'IN_TRANSIT', N'OUT_FOR_DELIVERY', N'DELIVERY_FAILED', N'DELIVERED', N'RETURNED');

-- Shipments pointing at an unknown customer, carrier or zone
SELECT s.shipment_id, s.customer_id, s.carrier_code, s.zone_code
FROM silver.tms_shipments AS s
LEFT JOIN silver.crm_customers AS c ON c.customer_id = s.customer_id
LEFT JOIN silver.tms_carriers AS k ON k.carrier_code = s.carrier_code
LEFT JOIN silver.tms_zones AS z ON z.zone_code = s.zone_code
WHERE c.customer_id IS NULL OR k.carrier_code IS NULL OR z.zone_code IS NULL;

-- Shipments without any tracking event
SELECT s.shipment_id
FROM silver.tms_shipments AS s
WHERE NOT EXISTS (SELECT 1 FROM silver.tms_tracking_events AS e WHERE e.shipment_id = s.shipment_id);
