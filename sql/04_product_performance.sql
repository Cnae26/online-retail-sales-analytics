/*
===============================================================================
Project: Online Retail Sales Analytics
File: 04_product_performance.sql
Database: PostgreSQL / Supabase

Purpose:
1. Identify top products by revenue
2. Identify top products by units sold
3. Identify products with the highest returned/cancelled units
4. Identify products concentrated in specific months
5. Identify products with declining revenue

Data scope:
- Sales analysis uses completed product sales
- Return analysis uses negative-quantity product transactions
===============================================================================
*/


-- ============================================================================
-- 1. PRODUCT SALES SUMMARY
-- One row represents one product
-- ============================================================================

CREATE OR REPLACE VIEW product_sales_summary AS

SELECT
    stock_code,

    -- Description is used as a readable product label
    MAX(description) AS product_description,

    COUNT(
        DISTINCT invoice_no
    ) AS total_orders,

    SUM(quantity) AS total_units_sold,

    ROUND(
        SUM(line_amount),
        2
    ) AS total_revenue,

    ROUND(
        SUM(line_amount)
        / NULLIF(SUM(quantity), 0),
        2
    ) AS average_selling_price

FROM retail_completed_sales

WHERE record_type = 'Product'

GROUP BY stock_code;


-- ============================================================================
-- 2. TOP 10 PRODUCTS BY REVENUE
-- ============================================================================

SELECT
    stock_code,
    product_description,
    total_orders,
    total_units_sold,
    total_revenue

FROM product_sales_summary

ORDER BY total_revenue DESC

LIMIT 10;


-- ============================================================================
-- 3. TOP 10 PRODUCTS BY UNITS SOLD
-- ============================================================================

SELECT
    stock_code,
    product_description,
    total_orders,
    total_units_sold,
    total_revenue

FROM product_sales_summary

ORDER BY total_units_sold DESC

LIMIT 10;


-- ============================================================================
-- 4. PRODUCT RETURNS AND CANCELLATIONS SUMMARY
--
-- Dataset limitation:
-- Negative quantities can represent returns, cancellations or adjustments.
-- The dataset does not provide a separate return reason.
-- ============================================================================

CREATE OR REPLACE VIEW product_returns_summary AS

SELECT
    stock_code,

    MAX(description) AS product_description,

    COUNT(
        DISTINCT invoice_no
    ) AS return_or_cancellation_transactions,

    SUM(
        ABS(quantity)
    ) AS returned_or_cancelled_units,

    ROUND(
        SUM(
            CASE
                WHEN unit_price > 0
                    THEN ABS(quantity::numeric * unit_price)

                ELSE 0
            END
        ),
        2
    ) AS estimated_return_value

FROM retail_transactions_clean

WHERE record_type = 'Product'
  AND quantity < 0

GROUP BY stock_code;


-- Top 10 products by returned or cancelled units
SELECT
    stock_code,
    product_description,
    return_or_cancellation_transactions,
    returned_or_cancelled_units,
    estimated_return_value

FROM product_returns_summary

ORDER BY returned_or_cancelled_units DESC

LIMIT 10;


-- ============================================================================
-- 5. MONTHLY PRODUCT PERFORMANCE
-- One row represents one product in one month
-- ============================================================================

CREATE OR REPLACE VIEW product_monthly_performance AS

SELECT
    DATE_TRUNC(
        'month',
        invoice_date
    )::date AS sales_month,

    stock_code,

    MAX(description) AS product_description,

    COUNT(
        DISTINCT invoice_no
    ) AS monthly_orders,

    SUM(quantity) AS monthly_units_sold,

    ROUND(
        SUM(line_amount),
        2
    ) AS monthly_revenue

FROM retail_completed_sales

WHERE record_type = 'Product'

GROUP BY
    DATE_TRUNC('month', invoice_date),
    stock_code;


-- Preview monthly product performance
SELECT *
FROM product_monthly_performance

ORDER BY
    sales_month,
    monthly_revenue DESC

LIMIT 30;


-- ============================================================================
-- 6. PRODUCTS WITH SALES CONCENTRATED IN A SPECIFIC MONTH
--
-- Peak month share:
-- Product revenue in its best month / Total product revenue
--
-- A high percentage suggests that the product sells strongly during
-- a particular month.
-- ============================================================================

CREATE OR REPLACE VIEW product_peak_month AS

WITH monthly_with_totals AS (
    SELECT
        sales_month,
        stock_code,
        product_description,
        monthly_orders,
        monthly_units_sold,
        monthly_revenue,

        SUM(monthly_revenue) OVER (
            PARTITION BY stock_code
        ) AS product_total_revenue,

        SUM(monthly_units_sold) OVER (
            PARTITION BY stock_code
        ) AS product_total_units

    FROM product_monthly_performance
),

ranked_months AS (
    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY stock_code
            ORDER BY
                monthly_revenue DESC,
                sales_month
        ) AS month_rank

    FROM monthly_with_totals
)

SELECT
    stock_code,
    product_description,

    sales_month AS peak_sales_month,

    monthly_orders AS peak_month_orders,

    monthly_units_sold AS peak_month_units,

    monthly_revenue AS peak_month_revenue,

    product_total_units,

    ROUND(
        product_total_revenue,
        2
    ) AS product_total_revenue,

    ROUND(
        monthly_revenue
        / NULLIF(product_total_revenue, 0)
        * 100,
        2
    ) AS peak_month_revenue_share_percent

FROM ranked_months

WHERE month_rank = 1;


-- Products most concentrated in one month
-- Minimum 100 units prevents very small products from dominating the result
SELECT
    stock_code,
    product_description,
    peak_sales_month,
    peak_month_units,
    peak_month_revenue,
    product_total_units,
    product_total_revenue,
    peak_month_revenue_share_percent

FROM product_peak_month

WHERE product_total_units >= 100

ORDER BY peak_month_revenue_share_percent DESC

LIMIT 20;


-- ============================================================================
-- 7. PRODUCTS WITH DECLINING REVENUE
--
-- The final month in this dataset is December 2011, but it contains
-- only partial-month data. Therefore, compare the latest two complete months:
-- October 2011 and November 2011.
--
-- The calculation is dynamic based on the maximum transaction date.
-- ============================================================================

CREATE OR REPLACE VIEW product_revenue_decline AS

WITH month_boundaries AS (
    SELECT
        (
            DATE_TRUNC('month', MAX(invoice_date))
            - INTERVAL '1 month'
        )::date AS latest_complete_month,

        (
            DATE_TRUNC('month', MAX(invoice_date))
            - INTERVAL '2 months'
        )::date AS previous_complete_month

    FROM retail_completed_sales

    WHERE record_type = 'Product'
),

revenue_comparison AS (
    SELECT
        sales.stock_code,

        MAX(
            sales.description
        ) AS product_description,

        boundaries.previous_complete_month,

        boundaries.latest_complete_month,

        COALESCE(
            SUM(sales.line_amount) FILTER (
                WHERE DATE_TRUNC(
                    'month',
                    sales.invoice_date
                )::date = boundaries.previous_complete_month
            ),
            0
        ) AS previous_month_revenue,

        COALESCE(
            SUM(sales.line_amount) FILTER (
                WHERE DATE_TRUNC(
                    'month',
                    sales.invoice_date
                )::date = boundaries.latest_complete_month
            ),
            0
        ) AS latest_month_revenue

    FROM retail_completed_sales AS sales

    CROSS JOIN month_boundaries AS boundaries

    WHERE sales.record_type = 'Product'
      AND DATE_TRUNC(
            'month',
            sales.invoice_date
          )::date IN (
            boundaries.previous_complete_month,
            boundaries.latest_complete_month
          )

    GROUP BY
        sales.stock_code,
        boundaries.previous_complete_month,
        boundaries.latest_complete_month
)

SELECT
    stock_code,
    product_description,
    previous_complete_month,
    latest_complete_month,

    ROUND(
        previous_month_revenue,
        2
    ) AS previous_month_revenue,

    ROUND(
        latest_month_revenue,
        2
    ) AS latest_month_revenue,

    ROUND(
        latest_month_revenue
        - previous_month_revenue,
        2
    ) AS revenue_change,

    ROUND(
        (
            latest_month_revenue
            - previous_month_revenue
        )
        / NULLIF(previous_month_revenue, 0)
        * 100,
        2
    ) AS revenue_change_percent

FROM revenue_comparison

WHERE latest_month_revenue < previous_month_revenue
  AND previous_month_revenue > 0;


-- Products with the largest absolute revenue decline
SELECT *
FROM product_revenue_decline

ORDER BY revenue_change ASC

LIMIT 20;


-- ============================================================================
-- 8. FINAL QUALITY CHECK
-- ============================================================================

SELECT
    (SELECT COUNT(*)
     FROM product_sales_summary) AS products_with_completed_sales,

    (SELECT COUNT(*)
     FROM product_returns_summary) AS products_with_returns,

    (SELECT COUNT(*)
     FROM product_peak_month) AS products_with_peak_month,

    (SELECT COUNT(*)
     FROM product_revenue_decline) AS products_with_declining_revenue;
