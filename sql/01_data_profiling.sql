-- ============================================================
-- PROJECT: Online Retail Sales Analytics
-- FILE: 01_data_profiling.sql
-- PURPOSE: Explore the raw dataset before data cleaning
-- SOURCE TABLE: online_retail
-- ============================================================


-- 1. Preview the dataset
-- Check the columns and understand what one row represents.

SELECT *
FROM online_retail
LIMIT 10;


-- 2. Count rows and unique business entities
-- COUNT(*) counts transaction lines.
-- COUNT(DISTINCT) counts unique business entities.

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT "Invoice") AS unique_invoices,
    COUNT(DISTINCT "StockCode") AS unique_stock_codes,
    COUNT(DISTINCT "Customer ID") AS unique_customers,
    COUNT(DISTINCT "Country") AS unique_countries
FROM online_retail;


-- 3. Check missing values
-- Customer ID is required for customer-level analysis,
-- but it is not required for general sales analysis.

SELECT
    COUNT(*) FILTER (
        WHERE "Description" IS NULL
           OR TRIM("Description") = ''
    ) AS missing_descriptions,

    COUNT(*) FILTER (
        WHERE "Customer ID" IS NULL
           OR TRIM("Customer ID") = ''
    ) AS missing_customer_ids,

    COUNT(*) FILTER (
        WHERE "Country" IS NULL
           OR TRIM("Country") = ''
    ) AS missing_countries

FROM online_retail;


-- 4. Check cancellations and unusual transactions
-- Invoices beginning with C represent cancellations.
-- Negative quantities may represent returns or adjustments.

SELECT
    COUNT(*) FILTER (
        WHERE "Invoice" LIKE 'C%'
    ) AS cancelled_rows,

    COUNT(*) FILTER (
        WHERE "Quantity" < 0
    ) AS negative_quantity_rows,

    COUNT(*) FILTER (
        WHERE "Price" = 0
    ) AS zero_price_rows,

    COUNT(*) FILTER (
        WHERE "Price" < 0
    ) AS negative_price_rows,

    COUNT(*) FILTER (
        WHERE "Invoice" NOT LIKE 'C%'
          AND "Quantity" > 0
          AND "Price" > 0
    ) AS normal_sales_rows

FROM online_retail;


-- 5. Compare cancellation status with negative quantities
-- This checks whether every negative quantity belongs
-- to an invoice beginning with C.

SELECT
    COUNT(*) FILTER (
        WHERE "Invoice" LIKE 'C%'
          AND "Quantity" < 0
    ) AS cancelled_and_negative,

    COUNT(*) FILTER (
        WHERE "Invoice" NOT LIKE 'C%'
          AND "Quantity" < 0
    ) AS negative_but_not_cancelled,

    COUNT(*) FILTER (
        WHERE "Invoice" LIKE 'C%'
          AND "Quantity" >= 0
    ) AS cancelled_but_not_negative

FROM online_retail;


-- 6. Check exact duplicate records
-- Total rows minus unique rows equals duplicate rows.

WITH unique_rows AS (
    SELECT DISTINCT
        "Invoice",
        "StockCode",
        "Description",
        "Quantity",
        "InvoiceDate",
        "Price",
        "Customer ID",
        "Country"
    FROM online_retail
)

SELECT
    (SELECT COUNT(*) FROM online_retail) AS total_rows,
    COUNT(*) AS unique_rows,

    (SELECT COUNT(*) FROM online_retail)
    - COUNT(*) AS duplicate_rows

FROM unique_rows;


-- 7. Check numeric ranges
-- Extreme values are reviewed before deciding whether
-- they are valid transactions or data-quality problems.

SELECT
    MIN("Quantity") AS minimum_quantity,
    MAX("Quantity") AS maximum_quantity,
    ROUND(AVG("Quantity")::numeric, 2) AS average_quantity,

    MIN("Price") AS minimum_price,
    MAX("Price") AS maximum_price,
    ROUND(AVG("Price")::numeric, 2) AS average_price

FROM online_retail;


-- 8. Investigate the highest quantities

SELECT
    "Invoice",
    "StockCode",
    "Description",
    "Quantity",
    "Price",
    "InvoiceDate"
FROM online_retail
ORDER BY "Quantity" DESC
LIMIT 20;


-- 9. Investigate the lowest quantities

SELECT
    "Invoice",
    "StockCode",
    "Description",
    "Quantity",
    "Price",
    "InvoiceDate"
FROM online_retail
ORDER BY "Quantity" ASC
LIMIT 20;


-- 10. Investigate the highest prices

SELECT
    "Invoice",
    "StockCode",
    "Description",
    "Quantity",
    "Price",
    "InvoiceDate"
FROM online_retail
ORDER BY "Price" DESC
LIMIT 20;


-- 11. Check the transaction date range
-- InvoiceDate was imported as text in DD/MM/YYYY HH24:MI format.

SELECT
    MIN(
        TO_TIMESTAMP(
            TRIM("InvoiceDate"),
            'DD/MM/YYYY HH24:MI'
        )
    ) AS first_transaction_date,

    MAX(
        TO_TIMESTAMP(
            TRIM("InvoiceDate"),
            'DD/MM/YYYY HH24:MI'
        )
    ) AS last_transaction_date

FROM online_retail;


-- 12. Review possible non-product stock codes
-- These records should be reviewed, not deleted automatically.

SELECT
    "StockCode",
    MAX("Description") AS description,
    COUNT(*) AS total_rows,
    ROUND(SUM("Quantity" * "Price")::numeric, 2) AS total_value

FROM online_retail

WHERE "StockCode" !~ '^[0-9]+[A-Za-z]*$'

GROUP BY "StockCode"

ORDER BY total_rows DESC;
