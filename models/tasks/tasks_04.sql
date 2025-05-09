-- models/task_04_merchant_outreach.sql

{{
  config(
    materialized = 'view',
    schema = 'analytics'
  )
}}

-- Part A: Top 5 performing merchants in December 2022
WITH december_2022_performance AS (
    SELECT 
        t.MERCHANT_ID,
        m.NAME AS merchant_name,
        m.CATEGORY AS industry,
        CASE WHEN m.SALES_MERCHANT THEN 'Yes' ELSE 'No' END AS acquired_via_sales_team,
        COUNT(t.TRANSACTION_ID) AS transaction_count,
        SUM(CASE WHEN t.STATUS = 'APPROVED' THEN t.AMOUNT ELSE 0 END) AS december_gpv,
        AVG(CASE WHEN t.STATUS = 'APPROVED' THEN t.AMOUNT ELSE NULL END) AS avg_transaction_value,
        MIN(CASE WHEN t.STATUS = 'APPROVED' THEN t.AMOUNT ELSE NULL END) AS min_transaction_value,
        MAX(CASE WHEN t.STATUS = 'APPROVED' THEN t.AMOUNT ELSE NULL END) AS max_transaction_value
    FROM ZELLER.TRANSACTIONS.TRANSACTIONS t
    JOIN ZELLER.MERCHANT.MERCHANT m ON t.MERCHANT_ID = m.MERCHANT_ID
    WHERE t.DATE >= '2022-12-01' AND t.DATE <= '2022-12-31'
    GROUP BY t.MERCHANT_ID, m.NAME, m.CATEGORY, m.SALES_MERCHANT
),

top_performers AS (
    SELECT 
        MERCHANT_ID,
        merchant_name,
        industry,
        acquired_via_sales_team,
        transaction_count,
        december_gpv,
        avg_transaction_value,
        min_transaction_value,
        max_transaction_value,
        ROW_NUMBER() OVER (ORDER BY december_gpv DESC) AS gpv_rank,
        'Top Performer' AS merchant_type
    FROM december_2022_performance
    QUALIFY gpv_rank <= 5  -- Top 5 by GPV (using Snowflake's QUALIFY)
),

-- Part B: Potentially churned merchants (no transactions for 6+ months)
merchant_last_activity AS (
    SELECT 
        m.MERCHANT_ID,
        m.NAME AS merchant_name,
        m.CATEGORY AS industry,
        CASE WHEN m.SALES_MERCHANT THEN 'Yes' ELSE 'No' END AS acquired_via_sales_team,
        MAX(t.DATE) AS last_transaction_date,
        DATEDIFF(DAY, MAX(t.DATE), '2022-12-15') AS days_inactive,
        COUNT(t.TRANSACTION_ID) AS total_transactions,
        SUM(CASE WHEN t.STATUS = 'APPROVED' THEN t.AMOUNT ELSE 0 END) AS total_gpv,
        -- Count months when merchant was active
        COUNT(DISTINCT DATE_TRUNC('MONTH', t.DATE)) AS active_months
    FROM ZELLER.MERCHANT.MERCHANT m
    LEFT JOIN ZELLER.TRANSACTIONS.TRANSACTIONS t ON m.MERCHANT_ID = t.MERCHANT_ID
    GROUP BY m.MERCHANT_ID, m.NAME, m.CATEGORY, m.SALES_MERCHANT
),

churned_merchants AS (
    SELECT 
        MERCHANT_ID,
        merchant_name,
        industry,
        acquired_via_sales_team,
        last_transaction_date,
        days_inactive,
        ROUND(days_inactive / 30.0, 1) AS months_inactive,
        total_transactions,
        total_gpv,
        active_months,
        CASE 
            WHEN active_months > 0 THEN ROUND(total_gpv / active_months, 2)
            ELSE 0
        END AS avg_monthly_gpv,
        'Churned' AS merchant_type
    FROM merchant_last_activity
    WHERE days_inactive >= 180 OR last_transaction_date IS NULL
)

-- Combine both result sets (top performers and churned merchants)
SELECT * FROM top_performers

UNION ALL

SELECT 
    MERCHANT_ID,
    merchant_name,
    industry,
    acquired_via_sales_team,
    total_transactions AS transaction_count,
    total_gpv AS december_gpv,
    CASE 
        WHEN total_transactions > 0 THEN total_gpv / total_transactions
        ELSE NULL
    END AS avg_transaction_value,
    NULL AS min_transaction_value,
    NULL AS max_transaction_value,
    ROW_NUMBER() OVER (ORDER BY total_gpv DESC) AS gpv_rank,
    merchant_type
FROM churned_merchants
ORDER BY 
    merchant_type,
    gpv_rank