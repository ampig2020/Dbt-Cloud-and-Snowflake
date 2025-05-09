-- models/task_03_bottom_performing_industries.sql

{{
  config(
    materialized = 'view',
    schema = 'analytics'
  )
}}

WITH industry_metrics AS (
    SELECT 
        m.CATEGORY AS industry,
        COUNT(DISTINCT m.MERCHANT_ID) AS merchant_count,
        COUNT(t.TRANSACTION_ID) AS transaction_count,
        SUM(CASE WHEN t.STATUS = 'APPROVED' THEN t.AMOUNT ELSE 0 END) AS industry_gpv
    FROM ZELLER.TRANSACTIONS.TRANSACTIONS t
    JOIN ZELLER.MERCHANT.MERCHANT m ON t.MERCHANT_ID = m.MERCHANT_ID
    GROUP BY m.CATEGORY
),

total_portfolio AS (
    SELECT 
        SUM(merchant_count) AS total_merchants,
        SUM(transaction_count) AS total_transactions,
        SUM(industry_gpv) AS total_gpv
    FROM industry_metrics
),

industry_ranks AS (
    SELECT 
        industry,
        merchant_count,
        transaction_count,
        industry_gpv,
        -- Calculate the percentage contributions
        ROUND((merchant_count / tp.total_merchants) * 100, 2) AS merchant_contribution_pct,
        ROUND((transaction_count / tp.total_transactions) * 100, 2) AS transaction_contribution_pct,
        ROUND((industry_gpv / tp.total_gpv) * 100, 2) AS gpv_contribution_pct,
        -- Rank industries by GPV (ascending for bottom performers)
        ROW_NUMBER() OVER (ORDER BY industry_gpv ASC) AS rank_by_gpv
    FROM industry_metrics, total_portfolio tp
),

bottom_industries AS (
    SELECT 
        industry,
        merchant_count,
        transaction_count,
        industry_gpv,
        merchant_contribution_pct,
        transaction_contribution_pct,
        gpv_contribution_pct,
        rank_by_gpv
    FROM industry_ranks
    WHERE rank_by_gpv <= 3  -- Bottom 3 by GPV
)

-- Main results with individual bottom industries
SELECT 
    industry,
    merchant_count,
    transaction_count,
    industry_gpv,
    merchant_contribution_pct,
    transaction_contribution_pct,
    gpv_contribution_pct,
    rank_by_gpv,
    'Individual' AS metric_type
FROM bottom_industries

UNION ALL

-- Combined statistics for bottom 3 industries
SELECT 
    'Bottom 3 Industries Combined' AS industry,
    SUM(merchant_count) AS merchant_count,
    SUM(transaction_count) AS transaction_count,
    SUM(industry_gpv) AS industry_gpv,
    ROUND(SUM(merchant_contribution_pct), 2) AS merchant_contribution_pct,
    ROUND(SUM(transaction_contribution_pct), 2) AS transaction_contribution_pct,
    ROUND(SUM(gpv_contribution_pct), 2) AS gpv_contribution_pct,
    NULL AS rank_by_gpv,
    'Combined' AS metric_type
FROM bottom_industries

ORDER BY 
    CASE WHEN metric_type = 'Individual' THEN 1 ELSE 2 END,
    rank_by_gpv