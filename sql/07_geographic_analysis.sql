
/*
===============================================================================
Project: Online Retail Sales Analytics
File: 07_geographic_analysis.sql
Database: PostgreSQL / Supabase

Purpose:
1. Calculate revenue by country
2. Calculate orders and units by country
3. Calculate average order value by country
4. Calculate country revenue contribution
5. Identify potential international growth markets

Data scope:
- Completed product sales only
- United Kingdom is treated as the domestic market
===============================================================================
*/


-- ============================================================================
-- 1. COUNTRY SALES SUMMARY
-- ============================================================================

CREATE OR REPLACE VIEW country_sales_summary AS

WITH country_metrics AS (
    SELECT
        country,

        COUNT(
            DISTINCT invoice_no
        ) AS total_orders,

        COUNT(
            DISTINCT customer_id
        ) AS total_identified_customers,

        SUM(quantity) AS total_units_sold,

        SUM(line_amount) AS total_revenue

    FROM retail_completed_sales

    WHERE record_type = 'Product'
      AND country IS NOT NULL

    GROUP BY country
)

SELECT
    country,
    total_orders,
    total_identified_customers,
    total_units_sold,

    ROUND(
        total_revenue,
        2
    ) AS total_revenue,

    ROUND(
        total_revenue
        / NULLIF(total_orders, 0),
        2
    ) AS average_order_value,

    ROUND(
        total_revenue
        / NULLIF(
            SUM(total_revenue) OVER (),
            0
        )
        * 100,
        2
    ) AS revenue_share_percent,

    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS revenue_rank,

    CASE
        WHEN country = 'United Kingdom'
            THEN 'Domestic'

        ELSE 'International'
    END AS market_type

FROM country_metrics;


-- Revenue and orders by country
SELECT *
FROM country_sales_summary

ORDER BY total_revenue DESC;


-- ============================================================================
-- 2. COUNTRIES WITH HIGHEST AVERAGE ORDER VALUE
-- Minimum 10 orders reduces distortion from very small markets
-- ============================================================================

SELECT
    country,
    total_orders,
    total_units_sold,
    total_revenue,
    average_order_value,
    revenue_share_percent

FROM country_sales_summary

WHERE total_orders >= 10

ORDER BY average_order_value DESC

LIMIT 20;


-- ============================================================================
-- 3. MONTHLY COUNTRY PERFORMANCE
-- ============================================================================

CREATE OR REPLACE VIEW country_monthly_performance AS

SELECT
    DATE_TRUNC(
        'month',
        invoice_date
    )::date AS sales_month,

    country,

    COUNT(
        DISTINCT invoice_no
    ) AS monthly_orders,

    COUNT(
        DISTINCT customer_id
    ) AS monthly_identified_customers,

    SUM(quantity) AS monthly_units_sold,

    ROUND(
        SUM(line_amount),
        2
    ) AS monthly_revenue,

    ROUND(
        SUM(line_amount)
        / NULLIF(COUNT(DISTINCT invoice_no), 0),
        2
    ) AS monthly_average_order_value

FROM retail_completed_sales

WHERE record_type = 'Product'
  AND country IS NOT NULL

GROUP BY
    DATE_TRUNC('month', invoice_date),
    country;


-- Check monthly country performance
SELECT *
FROM country_monthly_performance

ORDER BY
    sales_month,
    monthly_revenue DESC

LIMIT 50;


-- ============================================================================
-- 4. INTERNATIONAL MARKET GROWTH OPPORTUNITY
--
-- December 2011 contains only partial-month data.
-- Therefore, the latest two complete months are used for comparison.
-- ============================================================================

CREATE OR REPLACE VIEW international_market_opportunity AS

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

country_comparison AS (
    SELECT
        sales.country,

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
        ) AS latest_month_revenue,

        COUNT(DISTINCT sales.invoice_no) FILTER (
            WHERE DATE_TRUNC(
                'month',
                sales.invoice_date
            )::date = boundaries.previous_complete_month
        ) AS previous_month_orders,

        COUNT(DISTINCT sales.invoice_no) FILTER (
            WHERE DATE_TRUNC(
                'month',
                sales.invoice_date
            )::date = boundaries.latest_complete_month
        ) AS latest_month_orders

    FROM retail_completed_sales AS sales

    CROSS JOIN month_boundaries AS boundaries

    WHERE sales.record_type = 'Product'
      AND sales.country IS NOT NULL
      AND sales.country <> 'United Kingdom'
      AND DATE_TRUNC(
            'month',
            sales.invoice_date
          )::date IN (
            boundaries.previous_complete_month,
            boundaries.latest_complete_month
          )

    GROUP BY
        sales.country,
        boundaries.previous_complete_month,
        boundaries.latest_complete_month
)

SELECT
    country,
    previous_complete_month,
    latest_complete_month,

    previous_month_orders,
    latest_month_orders,

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
    ) AS revenue_growth_percent,

    ROUND(
        latest_month_revenue
        / NULLIF(latest_month_orders, 0),
        2
    ) AS latest_month_average_order_value,

    CASE
        WHEN previous_month_revenue = 0
             AND latest_month_revenue > 0
            THEN 'New/Emerging'

        WHEN latest_month_revenue > previous_month_revenue
            THEN 'Growing'

        WHEN latest_month_revenue < previous_month_revenue
            THEN 'Declining'

        ELSE 'Stable'
    END AS market_trend

FROM country_comparison;


-- Potential international growth markets
-- Minimum five latest-month orders reduces small-sample distortion
SELECT
    country,
    previous_complete_month,
    latest_complete_month,
    previous_month_orders,
    latest_month_orders,
    previous_month_revenue,
    latest_month_revenue,
    revenue_change,
    revenue_growth_percent,
    latest_month_average_order_value,
    market_trend

FROM international_market_opportunity

WHERE market_trend IN (
        'Growing',
        'New/Emerging'
      )
  AND latest_month_orders >= 5

ORDER BY revenue_change DESC;


-- ============================================================================
-- 5. INTERNATIONAL MARKET SUMMARY
-- ============================================================================

SELECT
    COUNT(*) FILTER (
        WHERE market_type = 'International'
    ) AS international_markets,

    ROUND(
        SUM(total_revenue) FILTER (
            WHERE market_type = 'International'
        ),
        2
    ) AS international_revenue,

    ROUND(
        SUM(total_revenue) FILTER (
            WHERE market_type = 'International'
        )
        / NULLIF(SUM(total_revenue), 0)
        * 100,
        2
    ) AS international_revenue_share_percent

FROM country_sales_summary;


-- ============================================================================
-- 6. FINAL QUALITY CHECK
-- ============================================================================

SELECT
    COUNT(*) AS countries_analyzed,

    COUNT(*) FILTER (
        WHERE market_type = 'Domestic'
    ) AS domestic_markets,

    COUNT(*) FILTER (
        WHERE market_type = 'International'
    ) AS international_markets,

    ROUND(
        SUM(revenue_share_percent),
        2
    ) AS total_revenue_share_percent

FROM country_sales_summary;
