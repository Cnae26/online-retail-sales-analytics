
/*
===============================================================================
Project: Online Retail Sales Analytics
File: 06_returns_cancellations.sql
Database: PostgreSQL / Supabase

Purpose:
1. Calculate estimated return rate
2. Calculate cancellation rate
3. Estimate reversed transaction value
4. Identify products with high return rates
5. Identify customers with unusually high return activity

Important assumptions:
- Invoice numbers beginning with C are treated as cancellations.
- Negative quantities represent returns, cancellations or adjustments.
- The dataset does not contain a separate return reason.
===============================================================================
*/


-- ============================================================================
-- 1. OVERALL RETURNS AND CANCELLATIONS SUMMARY
-- ============================================================================

CREATE OR REPLACE VIEW returns_cancellations_summary AS

WITH transaction_metrics AS (
    SELECT
        COUNT(DISTINCT invoice_no) FILTER (
            WHERE transaction_status = 'Completed Sale'
        ) AS completed_orders,

        COUNT(DISTINCT invoice_no) FILTER (
            WHERE transaction_status = 'Cancelled'
        ) AS cancelled_orders,

        COALESCE(
            SUM(quantity) FILTER (
                WHERE transaction_status = 'Completed Sale'
            ),
            0
        ) AS completed_units,

        COALESCE(
            SUM(ABS(quantity)) FILTER (
                WHERE quantity < 0
            ),
            0
        ) AS negative_quantity_units,

        COALESCE(
            SUM(
                CASE
                    WHEN transaction_status = 'Cancelled'
                         AND unit_price > 0
                        THEN ABS(line_amount)
                    ELSE 0
                END
            ),
            0
        ) AS estimated_cancelled_value,

        COALESCE(
            SUM(
                CASE
                    WHEN transaction_status = 'Return/Adjustment'
                         AND unit_price > 0
                        THEN ABS(line_amount)
                    ELSE 0
                END
            ),
            0
        ) AS estimated_return_adjustment_value

    FROM retail_transactions_clean

    WHERE record_type = 'Product'
)

SELECT
    completed_orders,
    cancelled_orders,

    ROUND(
        cancelled_orders::numeric
        / NULLIF(completed_orders + cancelled_orders, 0)
        * 100,
        2
    ) AS cancellation_rate_percent,

    completed_units,
    negative_quantity_units,

    ROUND(
        negative_quantity_units::numeric
        / NULLIF(completed_units, 0)
        * 100,
        2
    ) AS estimated_return_rate_percent,

    ROUND(
        estimated_cancelled_value,
        2
    ) AS estimated_cancelled_value,

    ROUND(
        estimated_return_adjustment_value,
        2
    ) AS estimated_return_adjustment_value,

    ROUND(
        estimated_cancelled_value
        + estimated_return_adjustment_value,
        2
    ) AS total_estimated_reversed_value

FROM transaction_metrics;


-- Check overall summary
SELECT *
FROM returns_cancellations_summary;


-- ============================================================================
-- 2. MONTHLY RETURNS AND CANCELLATIONS
-- ============================================================================

CREATE OR REPLACE VIEW monthly_returns_cancellations AS

WITH monthly_metrics AS (
    SELECT
        DATE_TRUNC(
            'month',
            invoice_date
        )::date AS transaction_month,

        COUNT(DISTINCT invoice_no) FILTER (
            WHERE transaction_status = 'Completed Sale'
        ) AS completed_orders,

        COUNT(DISTINCT invoice_no) FILTER (
            WHERE transaction_status = 'Cancelled'
        ) AS cancelled_orders,

        COALESCE(
            SUM(quantity) FILTER (
                WHERE transaction_status = 'Completed Sale'
            ),
            0
        ) AS completed_units,

        COALESCE(
            SUM(ABS(quantity)) FILTER (
                WHERE quantity < 0
            ),
            0
        ) AS negative_quantity_units,

        COALESCE(
            SUM(
                CASE
                    WHEN quantity < 0
                         AND unit_price > 0
                        THEN ABS(line_amount)
                    ELSE 0
                END
            ),
            0
        ) AS estimated_reversed_value

    FROM retail_transactions_clean

    WHERE record_type = 'Product'

    GROUP BY DATE_TRUNC('month', invoice_date)
)

SELECT
    transaction_month,
    completed_orders,
    cancelled_orders,

    ROUND(
        cancelled_orders::numeric
        / NULLIF(completed_orders + cancelled_orders, 0)
        * 100,
        2
    ) AS cancellation_rate_percent,

    completed_units,
    negative_quantity_units,

    ROUND(
        negative_quantity_units::numeric
        / NULLIF(completed_units, 0)
        * 100,
        2
    ) AS estimated_return_rate_percent,

    ROUND(
        estimated_reversed_value,
        2
    ) AS estimated_reversed_value

FROM monthly_metrics;


-- Check monthly performance
SELECT *
FROM monthly_returns_cancellations

ORDER BY transaction_month;


-- ============================================================================
-- 3. RETURN RATE BY PRODUCT
-- ============================================================================

CREATE OR REPLACE VIEW product_return_rates AS

WITH product_sales AS (
    SELECT
        stock_code,
        MAX(description) AS product_description,
        SUM(quantity) AS sold_units,
        COUNT(DISTINCT invoice_no) AS completed_orders

    FROM retail_completed_sales

    WHERE record_type = 'Product'

    GROUP BY stock_code
),

product_returns AS (
    SELECT
        stock_code,
        MAX(description) AS product_description,

        SUM(
            ABS(quantity)
        ) AS returned_or_cancelled_units,

        COUNT(DISTINCT invoice_no) FILTER (
            WHERE transaction_status = 'Cancelled'
        ) AS cancelled_transactions,

        COUNT(DISTINCT invoice_no) FILTER (
            WHERE transaction_status = 'Return/Adjustment'
        ) AS return_adjustment_transactions,

        SUM(
            CASE
                WHEN unit_price > 0
                    THEN ABS(line_amount)
                ELSE 0
            END
        ) AS estimated_return_value

    FROM retail_transactions_clean

    WHERE record_type = 'Product'
      AND quantity < 0

    GROUP BY stock_code
)

SELECT
    COALESCE(
        sales.stock_code,
        returns.stock_code
    ) AS stock_code,

    COALESCE(
        sales.product_description,
        returns.product_description
    ) AS product_description,

    COALESCE(
        sales.sold_units,
        0
    ) AS sold_units,

    COALESCE(
        returns.returned_or_cancelled_units,
        0
    ) AS returned_or_cancelled_units,

    COALESCE(
        returns.cancelled_transactions,
        0
    ) AS cancelled_transactions,

    COALESCE(
        returns.return_adjustment_transactions,
        0
    ) AS return_adjustment_transactions,

    ROUND(
        COALESCE(
            returns.returned_or_cancelled_units,
            0
        )::numeric
        / NULLIF(sales.sold_units, 0)
        * 100,
        2
    ) AS estimated_return_rate_percent,

    ROUND(
        COALESCE(
            returns.estimated_return_value,
            0
        ),
        2
    ) AS estimated_return_value,

    CASE
        WHEN COALESCE(
            returns.returned_or_cancelled_units,
            0
        ) > COALESCE(
            sales.sold_units,
            0
        )
            THEN 'Review: returns exceed sales'

        ELSE 'OK'
    END AS data_quality_flag

FROM product_sales AS sales

FULL OUTER JOIN product_returns AS returns
    ON sales.stock_code = returns.stock_code;


-- Products with high return rates
-- Minimum 100 sold units reduces distortion from very small products
SELECT
    stock_code,
    product_description,
    sold_units,
    returned_or_cancelled_units,
    estimated_return_rate_percent,
    estimated_return_value,
    data_quality_flag

FROM product_return_rates

WHERE sold_units >= 100
  AND returned_or_cancelled_units > 0

ORDER BY estimated_return_rate_percent DESC

LIMIT 20;


-- ============================================================================
-- 4. CUSTOMER RETURN BEHAVIOR
-- Customer analysis uses only non-null Customer IDs
-- ============================================================================

CREATE OR REPLACE VIEW customer_return_behavior AS

WITH customer_sales AS (
    SELECT
        customer_id,

        COUNT(
            DISTINCT invoice_no
        ) AS completed_orders,

        SUM(quantity) AS purchased_units,

        SUM(line_amount) AS completed_revenue

    FROM retail_completed_sales

    WHERE record_type = 'Product'
      AND customer_id IS NOT NULL

    GROUP BY customer_id
),

customer_returns AS (
    SELECT
        customer_id,

        COUNT(
            DISTINCT invoice_no
        ) AS return_transactions,

        SUM(
            ABS(quantity)
        ) AS returned_or_cancelled_units,

        SUM(
            CASE
                WHEN unit_price > 0
                    THEN ABS(line_amount)
                ELSE 0
            END
        ) AS estimated_return_value

    FROM retail_transactions_clean

    WHERE record_type = 'Product'
      AND customer_id IS NOT NULL
      AND quantity < 0

    GROUP BY customer_id
),

combined_customer_data AS (
    SELECT
        COALESCE(
            sales.customer_id,
            returns.customer_id
        ) AS customer_id,

        COALESCE(
            sales.completed_orders,
            0
        ) AS completed_orders,

        COALESCE(
            returns.return_transactions,
            0
        ) AS return_transactions,

        COALESCE(
            sales.purchased_units,
            0
        ) AS purchased_units,

        COALESCE(
            returns.returned_or_cancelled_units,
            0
        ) AS returned_or_cancelled_units,

        COALESCE(
            sales.completed_revenue,
            0
        ) AS completed_revenue,

        COALESCE(
            returns.estimated_return_value,
            0
        ) AS estimated_return_value

    FROM customer_sales AS sales

    FULL OUTER JOIN customer_returns AS returns
        ON sales.customer_id = returns.customer_id
),

scored_customers AS (
    SELECT
        *,

        PERCENT_RANK() OVER (
            ORDER BY returned_or_cancelled_units
        ) AS return_activity_rank

    FROM combined_customer_data
)

SELECT
    customer_id,
    completed_orders,
    return_transactions,
    purchased_units,
    returned_or_cancelled_units,

    ROUND(
        return_transactions::numeric
        / NULLIF(
            completed_orders + return_transactions,
            0
        )
        * 100,
        2
    ) AS return_transaction_rate_percent,

    ROUND(
        completed_revenue,
        2
    ) AS completed_revenue,

    ROUND(
        estimated_return_value,
        2
    ) AS estimated_return_value,

    ROUND(
        (return_activity_rank * 100)::numeric,
        2
    ) AS return_activity_percentile

FROM scored_customers;


-- Customers in the highest 5% of return activity
SELECT *
FROM customer_return_behavior

WHERE return_activity_percentile >= 95
  AND return_transactions >= 3

ORDER BY returned_or_cancelled_units DESC;


-- ============================================================================
-- 5. FINAL QUALITY CHECK
-- ============================================================================

SELECT
    (SELECT COUNT(*)
     FROM product_return_rates) AS products_checked,

    (SELECT COUNT(*)
     FROM customer_return_behavior) AS customers_checked,

    (SELECT COUNT(*)
     FROM customer_return_behavior
     WHERE return_activity_percentile >= 95
       AND return_transactions >= 3) AS high_return_activity_customers;
