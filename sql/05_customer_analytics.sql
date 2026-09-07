
/*
===============================================================================
Project: Online Retail Sales Analytics
File: 05_customer_analytics.sql
Database: PostgreSQL / Supabase

Purpose:
1. Create customer-level sales metrics
2. Calculate new and returning customers
3. Calculate repeat purchase rate
4. Calculate average revenue per customer
5. Perform RFM segmentation
6. Identify high-value and at-risk customers

Data scope:
- Completed product sales only
- Transactions with non-null Customer ID only
===============================================================================
*/


-- ============================================================================
-- 1. CUSTOMER SALES SUMMARY
-- One row represents one identified customer
-- ============================================================================

CREATE OR REPLACE VIEW customer_sales_summary AS

SELECT
    customer_id,

    -- Used as the customer's primary country label
    MAX(country) AS customer_country,

    MIN(
        invoice_date::date
    ) AS first_purchase_date,

    MAX(
        invoice_date::date
    ) AS last_purchase_date,

    COUNT(
        DISTINCT invoice_no
    ) AS total_orders,

    SUM(quantity) AS total_units_purchased,

    ROUND(
        SUM(line_amount),
        2
    ) AS total_customer_revenue,

    ROUND(
        SUM(line_amount)
        / NULLIF(COUNT(DISTINCT invoice_no), 0),
        2
    ) AS customer_average_order_value

FROM retail_completed_sales

WHERE customer_id IS NOT NULL
  AND record_type = 'Product'

GROUP BY customer_id;


-- Check customer summary
SELECT *
FROM customer_sales_summary

ORDER BY total_customer_revenue DESC

LIMIT 20;


-- ============================================================================
-- 2. CUSTOMER KPI SUMMARY
-- ============================================================================

CREATE OR REPLACE VIEW customer_kpi_summary AS

WITH customer_metrics AS (
    SELECT
        COUNT(*) AS total_identified_customers,

        COUNT(*) FILTER (
            WHERE total_orders >= 2
        ) AS repeat_customers,

        COUNT(*) FILTER (
            WHERE total_orders = 1
        ) AS one_time_customers,

        SUM(
            total_customer_revenue
        ) AS identified_customer_revenue

    FROM customer_sales_summary
)

SELECT
    total_identified_customers,
    repeat_customers,
    one_time_customers,

    ROUND(
        repeat_customers::numeric
        / NULLIF(total_identified_customers, 0)
        * 100,
        2
    ) AS repeat_purchase_rate_percent,

    ROUND(
        identified_customer_revenue,
        2
    ) AS identified_customer_revenue,

    ROUND(
        identified_customer_revenue
        / NULLIF(total_identified_customers, 0),
        2
    ) AS average_revenue_per_customer

FROM customer_metrics;


-- Check customer KPIs
SELECT *
FROM customer_kpi_summary;


-- ============================================================================
-- 3. MONTHLY NEW AND RETURNING CUSTOMERS
--
-- New customer:
-- The customer's first purchase occurs in that month.
--
-- Returning customer:
-- The customer first purchased before that month.
-- ============================================================================

CREATE OR REPLACE VIEW monthly_customer_status AS

WITH customer_monthly_sales AS (
    SELECT
        DATE_TRUNC(
            'month',
            invoice_date
        )::date AS sales_month,

        customer_id,

        COUNT(
            DISTINCT invoice_no
        ) AS monthly_orders,

        SUM(line_amount) AS monthly_revenue

    FROM retail_completed_sales

    WHERE customer_id IS NOT NULL
      AND record_type = 'Product'

    GROUP BY
        DATE_TRUNC('month', invoice_date),
        customer_id
),

customer_first_month AS (
    SELECT
        customer_id,

        MIN(sales_month) AS first_purchase_month

    FROM customer_monthly_sales

    GROUP BY customer_id
),

classified_customers AS (
    SELECT
        monthly.sales_month,
        monthly.customer_id,
        monthly.monthly_orders,
        monthly.monthly_revenue,
        first_month.first_purchase_month,

        CASE
            WHEN monthly.sales_month
                 = first_month.first_purchase_month
                THEN 'New Customer'

            ELSE 'Returning Customer'
        END AS customer_status

    FROM customer_monthly_sales AS monthly

    INNER JOIN customer_first_month AS first_month
        ON monthly.customer_id = first_month.customer_id
)

SELECT
    sales_month,

    COUNT(
        DISTINCT customer_id
    ) AS active_customers,

    COUNT(DISTINCT customer_id) FILTER (
        WHERE customer_status = 'New Customer'
    ) AS new_customers,

    COUNT(DISTINCT customer_id) FILTER (
        WHERE customer_status = 'Returning Customer'
    ) AS returning_customers,

    ROUND(
        COUNT(DISTINCT customer_id) FILTER (
            WHERE customer_status = 'Returning Customer'
        )::numeric
        / NULLIF(COUNT(DISTINCT customer_id), 0)
        * 100,
        2
    ) AS returning_customer_rate_percent,

    ROUND(
        COALESCE(
            SUM(monthly_revenue) FILTER (
                WHERE customer_status = 'New Customer'
            ),
            0
        ),
        2
    ) AS new_customer_revenue,

    ROUND(
        COALESCE(
            SUM(monthly_revenue) FILTER (
                WHERE customer_status = 'Returning Customer'
            ),
            0
        ),
        2
    ) AS returning_customer_revenue

FROM classified_customers

GROUP BY sales_month;


-- Check monthly new and returning customers
SELECT *
FROM monthly_customer_status

ORDER BY sales_month;


-- ============================================================================
-- 4. RFM CUSTOMER SEGMENTATION
--
-- Recency:   Days since the customer's latest purchase
-- Frequency: Number of completed orders
-- Monetary:  Total customer revenue
--
-- Score 5 = Best
-- Score 1 = Lowest
-- ============================================================================

CREATE OR REPLACE VIEW customer_rfm_segments AS

WITH analysis_date AS (
    SELECT
        MAX(invoice_date::date) + 1 AS reference_date

    FROM retail_completed_sales

    WHERE record_type = 'Product'
),

rfm_base AS (
    SELECT
        customer.customer_id,
        customer.customer_country,
        customer.first_purchase_date,
        customer.last_purchase_date,

        dates.reference_date
            - customer.last_purchase_date AS recency_days,

        customer.total_orders AS frequency,

        customer.total_customer_revenue AS monetary_value,

        customer.customer_average_order_value

    FROM customer_sales_summary AS customer

    CROSS JOIN analysis_date AS dates
),

rfm_scores AS (
    SELECT
        *,

        -- Lower recency is better, so recent customers receive higher scores
        NTILE(5) OVER (
            ORDER BY
                recency_days DESC,
                customer_id
        ) AS recency_score,

        -- More orders receive higher scores
        NTILE(5) OVER (
            ORDER BY
                frequency,
                customer_id
        ) AS frequency_score,

        -- Higher revenue receives higher scores
        NTILE(5) OVER (
            ORDER BY
                monetary_value,
                customer_id
        ) AS monetary_score

    FROM rfm_base
)

SELECT
    customer_id,
    customer_country,
    first_purchase_date,
    last_purchase_date,
    recency_days,
    frequency,
    monetary_value,
    customer_average_order_value,
    recency_score,
    frequency_score,
    monetary_score,

    CONCAT(
        recency_score,
        frequency_score,
        monetary_score
    ) AS rfm_score,

    CASE
        WHEN recency_score >= 4
             AND frequency_score >= 4
             AND monetary_score >= 4
            THEN 'Champions'

        WHEN recency_score <= 2
             AND (
                 frequency_score >= 4
                 OR monetary_score >= 4
             )
            THEN 'At Risk'

        WHEN frequency = 1
             AND recency_score >= 4
            THEN 'New Customers'

        WHEN recency_score >= 3
             AND frequency_score >= 4
            THEN 'Loyal Customers'

        WHEN recency_score >= 3
             AND frequency_score BETWEEN 2 AND 3
            THEN 'Potential Loyalists'

        WHEN recency_score <= 2
             AND frequency_score <= 2
            THEN 'Hibernating'

        ELSE 'Other'
    END AS customer_segment

FROM rfm_scores;


-- Check RFM segment distribution
SELECT
    customer_segment,
    COUNT(*) AS total_customers,

    ROUND(
        SUM(monetary_value),
        2
    ) AS segment_revenue,

    ROUND(
        AVG(monetary_value),
        2
    ) AS average_customer_revenue

FROM customer_rfm_segments

GROUP BY customer_segment

ORDER BY segment_revenue DESC;


-- ============================================================================
-- 5. HIGH-VALUE AND AT-RISK CUSTOMER STATUS
-- ============================================================================

CREATE OR REPLACE VIEW customer_priority_status AS

SELECT
    customer_id,
    customer_country,
    recency_days,
    frequency,
    monetary_value,
    customer_average_order_value,
    recency_score,
    frequency_score,
    monetary_score,
    rfm_score,
    customer_segment,

    CASE
        WHEN recency_score <= 2
             AND (
                 frequency_score >= 4
                 OR monetary_score >= 4
             )
            THEN 'High-value At Risk'

        WHEN recency_score >= 3
             AND frequency_score >= 4
             AND monetary_score >= 4
            THEN 'Active High-value'

        WHEN recency_score <= 2
            THEN 'At Risk'

        ELSE 'Standard'
    END AS customer_priority

FROM customer_rfm_segments;


-- Active high-value customers
SELECT *
FROM customer_priority_status

WHERE customer_priority = 'Active High-value'

ORDER BY monetary_value DESC

LIMIT 20;


-- High-value customers at risk
SELECT *
FROM customer_priority_status

WHERE customer_priority = 'High-value At Risk'

ORDER BY monetary_value DESC

LIMIT 20;


-- ============================================================================
-- 6. FINAL QUALITY CHECKS
-- ============================================================================

-- Customer IDs should not contain NULL
SELECT
    COUNT(*) AS total_customers,

    COUNT(*) FILTER (
        WHERE customer_id IS NULL
    ) AS missing_customer_ids,

    MIN(recency_score) AS minimum_recency_score,
    MAX(recency_score) AS maximum_recency_score,

    MIN(frequency_score) AS minimum_frequency_score,
    MAX(frequency_score) AS maximum_frequency_score,

    MIN(monetary_score) AS minimum_monetary_score,
    MAX(monetary_score) AS maximum_monetary_score

FROM customer_rfm_segments;


-- Every customer should be counted as new only once
SELECT
    (
        SELECT total_identified_customers
        FROM customer_kpi_summary
    ) AS total_identified_customers,

    (
        SELECT SUM(new_customers)
        FROM monthly_customer_status
    ) AS total_customers_classified_as_new;
