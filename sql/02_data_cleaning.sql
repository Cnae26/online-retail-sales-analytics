/*
===============================================================================
Project: Online Retail Sales Analytics
File: 02_data_cleaning.sql
Database: PostgreSQL / Supabase

Purpose:
1. Standardize column names and data types
2. Remove exact duplicate records
3. Convert invoice date from text to timestamp
4. Calculate transaction-level revenue
5. Classify completed sales, cancellations, and adjustments
6. Separate product and non-product records
7. Create an analysis-ready completed-sales view

Important assumption:
Exact duplicate rows are removed using SELECT DISTINCT because the source
dataset does not contain a unique transaction-line identifier.

The raw table online_retail is preserved without modification.
===============================================================================
*/


-- ============================================================================
-- 1. CREATE CLEAN TRANSACTION VIEW
-- ============================================================================

CREATE OR REPLACE VIEW retail_transactions_clean AS

WITH standardized_data AS (
    SELECT
        NULLIF(TRIM("Invoice"), '') AS invoice_no,

        NULLIF(
            UPPER(TRIM("StockCode")),
            ''
        ) AS stock_code,

        NULLIF(
            TRIM("Description"),
            ''
        ) AS description,

        "Quantity"::integer AS quantity,

        TO_TIMESTAMP(
            NULLIF(TRIM("InvoiceDate"), ''),
            'DD/MM/YYYY HH24:MI'
        ) AS invoice_date,

        "Price"::numeric(12, 2) AS unit_price,

        NULLIF(
            TRIM("Customer ID"),
            ''
        ) AS customer_id,

        NULLIF(
            TRIM("Country"),
            ''
        ) AS country

    FROM online_retail
),

remove_duplicates AS (
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

    quantity::numeric * unit_price AS line_amount,

    COALESCE(
        invoice_no LIKE 'C%',
        FALSE
    ) AS is_cancelled,

    COALESCE(
        quantity < 0,
        FALSE
    ) AS is_negative_quantity,

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

    CASE
        WHEN stock_code IS NULL
            THEN 'Unknown'

        WHEN stock_code IN (
            'POST',
            'DOT',
            'M',
            'D',
            'BANK CHARGES',
            'AMAZONFEE',
            'ADJUST'
        )
            THEN 'Non-product'

        ELSE 'Product'
    END AS record_type

FROM remove_duplicates;


-- ============================================================================
-- 2. CREATE COMPLETED SALES VIEW
-- ============================================================================

/*
This view contains only valid completed sales.

Use this view for:
- Total Revenue
- Total Orders
- Total Units Sold
- Average Order Value
- Monthly Sales Trend
- Revenue Growth

Do not use this view for returns or cancellation analysis because those
transactions have already been excluded.
*/

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
-- 3. VALIDATION: PREVIEW CLEAN DATA
-- ============================================================================

SELECT *
FROM retail_transactions_clean
LIMIT 20;


-- ============================================================================
-- 4. VALIDATION: CHECK DATE RANGE
-- ============================================================================

SELECT
    MIN(invoice_date) AS first_transaction_date,
    MAX(invoice_date) AS last_transaction_date

FROM retail_transactions_clean;


-- ============================================================================
-- 5. VALIDATION: COMPARE RAW AND CLEANED ROW COUNTS
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
-- 6. VALIDATION: TRANSACTION STATUS DISTRIBUTION
-- ============================================================================

SELECT
    transaction_status,
    COUNT(*) AS total_rows

FROM retail_transactions_clean

GROUP BY transaction_status

ORDER BY total_rows DESC;


-- ============================================================================
-- 7. VALIDATION: RECORD TYPE DISTRIBUTION
-- ============================================================================

SELECT
    record_type,
    COUNT(*) AS total_rows

FROM retail_transactions_clean

GROUP BY record_type

ORDER BY total_rows DESC;


-- ============================================================================
-- 8. VALIDATION: COMPLETED SALES SUMMARY
-- ============================================================================

SELECT
    COUNT(*) AS completed_rows,
    COUNT(DISTINCT invoice_no) AS completed_orders,
    SUM(quantity) AS units_sold,
    ROUND(SUM(line_amount), 2) AS total_revenue

FROM retail_completed_sales;


-- ============================================================================
-- 9. QUALITY CHECK: ALL RESULTS SHOULD BE ZERO
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
