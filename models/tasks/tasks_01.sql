-- models/task_01_week_over_week_performance.sql

{{
  config(
    materialized = 'view',
    schema = 'analytics'
  )
}}

WITH sales_weeks AS (
    SELECT 
        t.DATE,
        t.TRANSACTION_ID,
        t.MERCHANT_ID,
        t.TYPE,
        t.AMOUNT,
        t.STATUS,
        m.CATEGORY AS industry,
        CASE
            WHEN t.DATE BETWEEN '2022-12-05' AND '2022-12-11' THEN 'Week Dec 5-11'
            WHEN t.DATE BETWEEN '2022-11-28' AND '2022-12-04' THEN 'Week Nov 28-Dec 4'
        END AS sales_week
    FROM ZELLER.TRANSACTIONS.TRANSACTIONS t
    JOIN ZELLER.MERCHANT.MERCHANT m 
      ON t.MERCHANT_ID = m.MERCHANT_ID
    WHERE 
        t.STATUS = 'APPROVED'  -- Based on your sample data showing "APPROVED"
        AND t.DATE BETWEEN '2022-11-28' AND '2022-12-11'
),

weekly_aggregates AS (
    SELECT 
        sales_week,
        industry,
        COUNT(TRANSACTION_ID) AS transaction_count,
        SUM(AMOUNT) AS gpv
    FROM sales_weeks
    GROUP BY sales_week, industry
),

industry_pivot AS (
    SELECT 
        industry,
        SUM(CASE WHEN sales_week = 'Week Dec 5-11' THEN gpv ELSE 0 END) AS current_week_gpv,
        SUM(CASE WHEN sales_week = 'Week Nov 28-Dec 4' THEN gpv ELSE 0 END) AS previous_week_gpv,
        SUM(CASE WHEN sales_week = 'Week Dec 5-11' THEN transaction_count ELSE 0 END) AS current_week_txn_count,
        SUM(CASE WHEN sales_week = 'Week Nov 28-Dec 4' THEN transaction_count ELSE 0 END) AS previous_week_txn_count
    FROM weekly_aggregates
    GROUP BY industry
),

industry_wow_change AS (
    SELECT 
        industry,
        current_week_gpv,
        previous_week_gpv,
        (current_week_gpv - previous_week_gpv) AS gpv_change,
        ROUND(
            (current_week_gpv - previous_week_gpv) / NULLIF(previous_week_gpv, 0) * 100, 2
        ) AS gpv_pct_change,
        current_week_txn_count,
        previous_week_txn_count,
        (current_week_txn_count - previous_week_txn_count) AS txn_count_change,
        ROUND(
            (current_week_txn_count - previous_week_txn_count) / NULLIF(previous_week_txn_count, 0) * 100, 2
        ) AS txn_count_pct_change
    FROM industry_pivot
),

overall_metrics AS (
    SELECT 
        SUM(current_week_gpv) AS current_week_gpv,
        SUM(previous_week_gpv) AS previous_week_gpv,
        SUM(current_week_txn_count) AS current_week_txn_count,
        SUM(previous_week_txn_count) AS previous_week_txn_count
    FROM industry_pivot
)

SELECT 
    industry AS metric,
    current_week_gpv,
    previous_week_gpv,
    gpv_change,
    gpv_pct_change,
    current_week_txn_count,
    previous_week_txn_count,
    txn_count_change,
    txn_count_pct_change,
    'Industry' AS category,
    'Week Dec 5-11 vs. Week Nov 28-Dec 4' AS comparison_period
FROM industry_wow_change

UNION ALL

SELECT 
    'Overall' AS metric,
    current_week_gpv,
    previous_week_gpv,
    (current_week_gpv - previous_week_gpv) AS gpv_change,
    ROUND(
        (current_week_gpv - previous_week_gpv) / NULLIF(previous_week_gpv, 0) * 100, 2
    ) AS gpv_pct_change,
    current_week_txn_count,
    previous_week_txn_count,
    (current_week_txn_count - previous_week_txn_count) AS txn_count_change,
    ROUND(
        (current_week_txn_count - previous_week_txn_count) / NULLIF(previous_week_txn_count, 0) * 100, 2
    ) AS txn_count_pct_change,
    'Overall' AS category,
    'Week Dec 5-11 vs. Week Nov 28-Dec 4' AS comparison_period
FROM overall_metrics

ORDER BY category, gpv_pct_change DESC