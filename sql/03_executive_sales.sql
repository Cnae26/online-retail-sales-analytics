/*
===============================================================================
Project: Online Retail Sales Analytics
File: 03_executive_sales.sql
Database: PostgreSQL / Supabase

Purpose:
1. Calculate executive sales KPIs
2. Analyze monthly sales trends
3. Calculate month-over-month revenue growth
4. Analyze weekly sales patterns

Data scope:
- Completed transactions only
- Product records only
- Non-product charges are excluded
===============================================================================
*/


-- ============================================================================
-- 1. EXECUTIVE SALES SUMMARY
-- ============================================================================

CREATE OR REPLACE VIEW executive_sales_summary AS

WITH sales_scope AS (
    SELECT *
    FROM retail_completed_sales
    WHERE record_type = 'Product'
)

SELECT
    ROUND(
        SUM(line_amount),
        2
    ) AS total_revenue,

    COUNT(
        DISTINCT invoice_no
    ) AS total_orders,

    SUM(quantity) AS total_units_sold,

    ROUND(
        SUM(line_amount)
        / NULLIF(COUNT(DISTINCT invoice_no), 0),
        2
    ) AS average_order_value,

    MIN(invoice_date::date) AS first_sales_date,

    MAX(invoice_date::date) AS last_sales_date

FROM sales_scope;


-- Check executive sales summary
SELECT *
FROM executive_sales_summary;


-- ============================================================================
-- 2. MONTHLY SALES PERFORMANCE
-- ============================================================================

CREATE OR REPLACE VIEW monthly_sales_performance AS

WITH monthly_sales AS (
    SELECT
        DATE_TRUNC(
            'month',
            invoice_date
        )::date AS sales_month,

        SUM(line_amount) AS monthly_revenue,

        COUNT(
            DISTINCT invoice_no
        ) AS monthly_orders,

        SUM(quantity) AS monthly_units_sold,

        COUNT(
            DISTINCT invoice_date::date
        ) AS active_sales_days,

        MIN(invoice_date::date) AS first_sales_date,

        MAX(invoice_date::date) AS last_sales_date

    FROM retail_completed_sales

    WHERE record_type = 'Product'

    GROUP BY
        DATE_TRUNC('month', invoice_date)
),

sales_with_previous_month AS (
    SELECT
        sales_month,
        monthly_revenue,
        monthly_orders,
        monthly_units_sold,
        active_sales_days,
        first_sales_date,
        last_sales_date,

        LAG(monthly_revenue) OVER (
            ORDER BY sales_month
        ) AS previous_month_revenue

    FROM monthly_sales
)

SELECT
    sales_month,

    ROUND(
        monthly_revenue,
        2
    ) AS monthly_revenue,

    monthly_orders,

    monthly_units_sold,

    ROUND(
        monthly_revenue
        / NULLIF(monthly_orders, 0),
        2
    ) AS monthly_average_order_value,

    ROUND(
        previous_month_revenue,
        2
    ) AS previous_month_revenue,

    ROUND(
        (
            monthly_revenue - previous_month_revenue
        )
        / NULLIF(previous_month_revenue, 0)
        * 100,
        2
    ) AS revenue_growth_percent,

    active_sales_days,
    first_sales_date,
    last_sales_date

FROM sales_with_previous_month;


-- Check monthly sales performance
SELECT *
FROM monthly_sales_performance
ORDER BY sales_month;


-- ============================================================================
-- 3. DAILY SALES TREND
-- ============================================================================

CREATE OR REPLACE VIEW daily_sales_trend AS

SELECT
    invoice_date::date AS sales_date,

    ROUND(
        SUM(line_amount),
        2
    ) AS daily_revenue,

    COUNT(
        DISTINCT invoice_no
    ) AS daily_orders,

    SUM(quantity) AS daily_units_sold,

    ROUND(
        SUM(line_amount)
        / NULLIF(COUNT(DISTINCT invoice_no), 0),
        2
    ) AS daily_average_order_value

FROM retail_completed_sales

WHERE record_type = 'Product'

GROUP BY invoice_date::date;


-- Check daily sales trend
SELECT *
FROM daily_sales_trend
ORDER BY sales_date
LIMIT 30;


-- ============================================================================
-- 4. WEEKDAY SALES PATTERN
-- This helps identify which days normally generate higher sales
-- ============================================================================

CREATE OR REPLACE VIEW weekday_sales_pattern AS

WITH daily_sales AS (
    SELECT
        invoice_date::date AS sales_date,

        SUM(line_amount) AS daily_revenue,

        COUNT(
            DISTINCT invoice_no
        ) AS daily_orders,

        SUM(quantity) AS daily_units_sold

    FROM retail_completed_sales

    WHERE record_type = 'Product'

    GROUP BY invoice_date::date
)

SELECT
    EXTRACT(
        ISODOW FROM sales_date
    )::integer AS day_number,

    TO_CHAR(
        sales_date,
        'FMDay'
    ) AS day_name,

    COUNT(*) AS observed_sales_days,

    ROUND(
        AVG(daily_revenue),
        2
    ) AS average_daily_revenue,

    ROUND(
        AVG(daily_orders),
        2
    ) AS average_daily_orders,

    ROUND(
        AVG(daily_units_sold),
        2
    ) AS average_daily_units_sold

FROM daily_sales

GROUP BY
    EXTRACT(ISODOW FROM sales_date),
    TO_CHAR(sales_date, 'FMDay');


-- Check weekday sales pattern
SELECT *
FROM weekday_sales_pattern
ORDER BY day_number;


-- ============================================================================
-- 5. FINAL QUALITY CHECK
-- ============================================================================

SELECT
    COUNT(*) AS number_of_months,

    MIN(sales_month) AS first_month,

    MAX(sales_month) AS last_month,

    COUNT(*) FILTER (
        WHERE revenue_growth_percent IS NULL
    ) AS months_without_growth_comparison

FROM monthly_sales_performance;
