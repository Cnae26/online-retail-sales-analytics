/*
===============================================================================
Project: Online Retail Sales Analytics
File: 02_data_cleaning.sql
Database: PostgreSQL / Supabase

Purpose:
1. Standardize column names and data types
2. Remove exact duplicate rows
3. Convert invoice date from text to timestamp
4. Calculate line-level sales amount
5. Classify transaction status
6. Separate product and non-product records
7. Create an analysis-ready completed sales view

Important:
- The raw table online_retail is not modified.
- Exact duplicate rows are removed using SELECT DISTINCT.
- Customer ID is allowed to be NULL.
===============================================================================
*/


-- ============================================================================
-- 1. REMOVE OLD VIEWS
-- Drop the dependent view first
-- ============================================================================



-- ============================================================================
-- 2. CREATE CLEAN TRANSACTION VIEW
-- This view keeps completed sales, cancellations and adjustments
-- ============================================================================

CREATE OR REPLACE VIEW retail_transactions_clean AS

WITH standardized_data AS (
    SELECT
        -- Remove unnecessary spaces from invoice number
        NULLIF(
            TRIM("Invoice"),
            ''
        ) AS invoice_no,

        -- Standardize StockCode as uppercase text
        NULLIF(
            UPPER(TRIM("StockCode")),
            ''
        ) AS stock_code,

        -- Convert blank descriptions to NULL
        NULLIF(
            TRIM("Description"),
            ''
        ) AS description,

        -- Convert Quantity to integer
        "Quantity"::integer AS quantity,

        -- Convert text date into PostgreSQL timestamp
        TO_TIMESTAMP(
            NULLIF(TRIM("InvoiceDate"), ''),
            'DD/MM/YYYY HH24:MI'
        ) AS invoice_date,

        -- Keep four decimal places to preserve prices such as 0.001
        "Price"::numeric(12, 4) AS unit_price,

        -- Keep missing Customer ID as NULL
        NULLIF(
            TRIM("Customer ID"),
            ''
        ) AS customer_id,

        -- Convert blank countries to NULL
        NULLIF(
            TRIM("Country"),
            ''
        ) AS country

    FROM online_retail
),

remove_duplicates AS (
    -- Remove rows that are identical across all original fields
    SELECT DISTINCT
        invoice_no,
        stock_code,
        description,
        quantity,
        invoice_date,
        unit_price,
        customer_id,
        country

    FROM standardized_data
)

SELECT
    invoice_no,
    stock_code,
    description,
    quantity,
    invoice_date,
    unit_price,
    customer_id,
    country,

    -- Revenue at transaction-line level
    quantity::numeric * unit_price AS line_amount,

    -- Cancellation flag
    COALESCE(
        invoice_no LIKE 'C%',
        FALSE
    ) AS is_cancelled,

    -- Negative quantity flag
    COALESCE(
        quantity < 0,
        FALSE
    ) AS is_negative_quantity,

    -- Classify each transaction
    CASE
        WHEN invoice_no IS NULL
            OR stock_code IS NULL
            OR quantity IS NULL
            OR invoice_date IS NULL
            OR unit_price IS NULL
            THEN 'Invalid/Missing Key'

        WHEN invoice_no LIKE 'C%'
            THEN 'Cancelled'

        WHEN quantity < 0
            THEN 'Return/Adjustment'

        WHEN unit_price <= 0
            THEN 'Zero/Invalid Price'

        ELSE 'Completed Sale'
    END AS transaction_status,

    -- Separate merchandise from administrative/service records
    CASE
        WHEN stock_code IS NULL
            THEN 'Unknown'

        WHEN stock_code IN (
            'POST',
            'DOT',
            'M',
            'D',
            'PADS',
            'BANK CHARGES',
            'AMAZONFEE',
            'ADJUST'
        )
            THEN 'Non-product'

        ELSE 'Product'
    END AS record_type

FROM remove_duplicates;


-- ============================================================================
-- 3. CREATE COMPLETED SALES VIEW
-- Use this view for revenue and sales performance analysis
-- ============================================================================

CREATE OR REPLACE VIEW retail_completed_sales AS

SELECT
    invoice_no,
    stock_code,
    description,
    quantity,
    invoice_date,
    unit_price,
    customer_id,
    country,
    line_amount,
    record_type

FROM retail_transactions_clean

WHERE transaction_status = 'Completed Sale';


-- ============================================================================
-- 4. PREVIEW CLEANED DATA
-- ============================================================================

SELECT *
FROM retail_transactions_clean
LIMIT 20;


-- ============================================================================
-- 5. CHECK TRANSACTION DATE RANGE
-- ============================================================================

SELECT
    MIN(invoice_date) AS first_transaction_date,
    MAX(invoice_date) AS last_transaction_date

FROM retail_transactions_clean;


-- ============================================================================
-- 6. COMPARE RAW AND CLEANED ROW COUNTS
-- ============================================================================

SELECT
    (SELECT COUNT(*)
     FROM online_retail) AS raw_rows,

    (SELECT COUNT(*)
     FROM retail_transactions_clean) AS cleaned_rows,

    (SELECT COUNT(*)
     FROM online_retail)
    -
    (SELECT COUNT(*)
     FROM retail_transactions_clean) AS removed_duplicate_rows;


-- ============================================================================
-- 7. CHECK TRANSACTION STATUS DISTRIBUTION
-- ============================================================================

SELECT
    transaction_status,
    COUNT(*) AS total_rows

FROM retail_transactions_clean

GROUP BY transaction_status

ORDER BY total_rows DESC;


-- ============================================================================
-- 8. CHECK PRODUCT AND NON-PRODUCT DISTRIBUTION
-- ============================================================================

SELECT
    record_type,
    COUNT(*) AS total_rows

FROM retail_transactions_clean

GROUP BY record_type

ORDER BY total_rows DESC;


-- ============================================================================
-- 9. COMPLETED SALES SUMMARY
-- ============================================================================

SELECT
    COUNT(*) AS completed_rows,
    COUNT(DISTINCT invoice_no) AS completed_orders,
    SUM(quantity) AS units_sold,
    ROUND(SUM(line_amount), 2) AS total_revenue

FROM retail_completed_sales;


-- ============================================================================
-- 10. QUALITY CHECK
-- All three results should be zero
-- ============================================================================

SELECT
    COUNT(*) FILTER (
        WHERE invoice_no LIKE 'C%'
    ) AS cancelled_rows,

    COUNT(*) FILTER (
        WHERE quantity <= 0
    ) AS non_positive_quantity_rows,

    COUNT(*) FILTER (
        WHERE unit_price <= 0
    ) AS non_positive_price_rows

FROM retail_completed_sales;
