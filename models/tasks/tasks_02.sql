-- models/task_02_cumulative_growth.sql

{{
  config(
    materialized = 'view',
    schema = 'analytics'
  )
}}

-- Weekly aggregation
WITH weekly_data AS (
    SELECT 
        DATE_TRUNC('week', DATE) AS week_start,
        COUNT(TRANSACTION_ID) AS transaction_count,
        SUM(CASE WHEN STATUS = 'APPROVED' THEN AMOUNT ELSE 0 END) AS weekly_gpv
    FROM ZELLER.TRANSACTIONS.TRANSACTIONS
    WHERE DATE <= '2022-12-05'  -- Data up to the week commencing Dec 5, 2022
    GROUP BY DATE_TRUNC('week', DATE)
    ORDER BY week_start
),

-- Monthly aggregation
monthly_data AS (
    SELECT 
        DATE_TRUNC('month', DATE) AS month_start,
        COUNT(TRANSACTION_ID) AS transaction_count,
        SUM(CASE WHEN STATUS = 'APPROVED' THEN AMOUNT ELSE 0 END) AS monthly_gpv
    FROM ZELLER.TRANSACTIONS.TRANSACTIONS
    WHERE DATE <= '2022-12-05'  -- Data up to the week commencing Dec 5, 2022
    GROUP BY DATE_TRUNC('month', DATE)
    ORDER BY month_start
),

-- Cumulative metrics by week
weekly_cumulative AS (
    SELECT 
        week_start,
        weekly_gpv,
        transaction_count,
        SUM(weekly_gpv) OVER (ORDER BY week_start) AS cumulative_gpv,
        SUM(transaction_count) OVER (ORDER BY week_start) AS cumulative_transactions,
        -- Growth metrics (week-over-week)
        LAG(weekly_gpv, 1, 0) OVER (ORDER BY week_start) AS prev_week_gpv,
        CASE 
            WHEN LAG(weekly_gpv, 1, 0) OVER (ORDER BY week_start) = 0 THEN NULL
            ELSE ROUND(((weekly_gpv - LAG(weekly_gpv, 1, 0) OVER (ORDER BY week_start)) / 
                  NULLIF(LAG(weekly_gpv, 1, 0) OVER (ORDER BY week_start), 0)) * 100, 2)
        END AS weekly_gpv_growth_pct
    FROM weekly_data
),

-- Cumulative metrics by month
monthly_cumulative AS (
    SELECT 
        month_start,
        monthly_gpv,
        transaction_count,
        SUM(monthly_gpv) OVER (ORDER BY month_start) AS cumulative_gpv,
        SUM(transaction_count) OVER (ORDER BY month_start) AS cumulative_transactions,
        -- Growth metrics (month-over-month)
        LAG(monthly_gpv, 1, 0) OVER (ORDER BY month_start) AS prev_month_gpv,
        CASE 
            WHEN LAG(monthly_gpv, 1, 0) OVER (ORDER BY month_start) = 0 THEN NULL
            ELSE ROUND(((monthly_gpv - LAG(monthly_gpv, 1, 0) OVER (ORDER BY month_start)) / 
                  NULLIF(LAG(monthly_gpv, 1, 0) OVER (ORDER BY month_start), 0)) * 100, 2)
        END AS monthly_gpv_growth_pct
    FROM monthly_data
)

-- Combine weekly and monthly data with a type indicator
SELECT 
    'WEEKLY' AS time_period,
    week_start::date AS period_start,
    weekly_gpv AS period_gpv,
    transaction_count AS period_transactions,
    cumulative_gpv,
    cumulative_transactions,
    weekly_gpv_growth_pct AS period_growth_pct
FROM weekly_cumulative

UNION ALL

SELECT 
    'MONTHLY' AS time_period,
    month_start::date AS period_start,
    monthly_gpv AS period_gpv,
    transaction_count AS period_transactions,
    cumulative_gpv,
    cumulative_transactions,
    monthly_gpv_growth_pct AS period_growth_pct
FROM monthly_cumulative
ORDER BY time_period, period_start