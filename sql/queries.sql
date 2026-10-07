-- =====================================================================================
-- PROJECT 2: CUSTOMER CHURN & REVENUE LEAKAGE  |  SQL ANALYSIS
-- Dialect: SQLite (standard SQL - works in PostgreSQL / MySQL 8+ with tiny changes).
--
-- `customers_v` is a VIEW over the raw `customers` table that adds:
--     is_churn       = Exited (1 = customer left)
--     age_band, balance_band, activity   (CASE WHEN bucketing)
--     annual_revenue = 2% net interest margin on balance + $50 fee income per product
--                      (ASSUMPTION - change it in run_sql.py and pipeline.py together)
-- =====================================================================================


-- name: 01_kpis
-- question: How big is the churn problem, in customers AND in dollars?
SELECT
    COUNT(*)                                              AS customers,
    SUM(is_churn)                                         AS churned,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct,
    ROUND(SUM(annual_revenue) / 1e6, 2)                   AS total_annual_revenue_mn,
    ROUND(SUM(CASE WHEN is_churn = 1 THEN annual_revenue END) / 1e6, 2) AS revenue_lost_mn,
    ROUND(100.0 * SUM(CASE WHEN is_churn = 1 THEN annual_revenue END) / SUM(annual_revenue), 2) AS revenue_lost_pct,
    ROUND(AVG(Tenure), 2)                                 AS avg_tenure_yrs
FROM customers_v;


-- name: 02_churn_by_geography
-- question: Which country loses the most customers and revenue?
SELECT
    Geography,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct,
    ROUND(SUM(CASE WHEN is_churn = 1 THEN annual_revenue END) / 1e3, 1) AS revenue_lost_k
FROM customers_v
GROUP BY Geography
ORDER BY churn_rate_pct DESC;


-- name: 03_churn_by_products
-- question: Is the number of products a bank customer holds linked to churn?
SELECT
    NumOfProducts,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct,
    ROUND(SUM(CASE WHEN is_churn = 1 THEN annual_revenue END) / 1e3, 1) AS revenue_lost_k
FROM customers_v
GROUP BY NumOfProducts
ORDER BY NumOfProducts;


-- name: 04_activity_by_products_matrix
-- question: Do inactive customers with a single product churn the most? (two-way matrix)
SELECT
    activity,
    ROUND(100.0 * AVG(CASE WHEN NumOfProducts = 1 THEN is_churn END), 2) AS churn_pct_1_product,
    ROUND(100.0 * AVG(CASE WHEN NumOfProducts = 2 THEN is_churn END), 2) AS churn_pct_2_products,
    ROUND(100.0 * AVG(CASE WHEN NumOfProducts >= 3 THEN is_churn END), 2) AS churn_pct_3plus_products,
    COUNT(*)                                                             AS customers
FROM customers_v
GROUP BY activity;


-- name: 05_churn_by_age_band
-- question: Which age groups churn? (CASE WHEN banding, with gap vs the overall rate)
SELECT
    age_band,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct,
    ROUND(100.0 * (AVG(is_churn) - (SELECT AVG(is_churn) FROM customers_v)), 2) AS gap_vs_overall_pp
FROM customers_v
GROUP BY age_band
ORDER BY age_band;


-- name: 06_segment_revenue_leakage_ranked
-- question: Which balance x activity segments leak the most revenue? (RANK window function)
WITH seg AS (
    SELECT
        balance_band || ' | ' || activity                       AS segment,
        COUNT(*)                                                AS customers,
        AVG(is_churn)                                           AS churn_rate,
        SUM(CASE WHEN is_churn = 1 THEN annual_revenue END)     AS revenue_lost
    FROM customers_v
    GROUP BY balance_band, activity
)
SELECT
    segment,
    customers,
    ROUND(100 * churn_rate, 2)                                  AS churn_rate_pct,
    ROUND(revenue_lost / 1e3, 1)                                AS revenue_lost_k,
    RANK() OVER (ORDER BY revenue_lost DESC)                    AS leakage_rank
FROM seg
ORDER BY leakage_rank;


-- name: 07_pareto_revenue_loss
-- question: Do a few segments cause most of the loss? (cumulative share with SUM() OVER)
WITH seg AS (
    SELECT
        Geography || ' | ' || activity                          AS segment,
        SUM(CASE WHEN is_churn = 1 THEN annual_revenue ELSE 0 END) AS revenue_lost
    FROM customers_v
    GROUP BY Geography, activity
)
SELECT
    segment,
    ROUND(revenue_lost / 1e3, 1)                                AS revenue_lost_k,
    ROUND(100.0 * revenue_lost / SUM(revenue_lost) OVER (), 1)  AS share_pct,
    ROUND(100.0 * SUM(revenue_lost) OVER (ORDER BY revenue_lost DESC)
          / SUM(revenue_lost) OVER (), 1)                       AS cumulative_share_pct
FROM seg
ORDER BY revenue_lost DESC;


-- name: 08_tenure_churn
-- question: Do new customers leave faster than loyal ones?
SELECT
    Tenure                                                AS tenure_years,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct,
    ROUND(100.0 * (AVG(is_churn) - AVG(AVG(is_churn)) OVER ()), 2) AS gap_vs_avg_of_years_pp
FROM customers_v
GROUP BY Tenure
ORDER BY Tenure;


-- name: 09_balance_quartiles
-- question: Among customers WITH a balance, do bigger balances churn more? (NTILE quartiles)
WITH q AS (
    SELECT is_churn, Balance, annual_revenue,
           NTILE(4) OVER (ORDER BY Balance) AS balance_quartile
    FROM customers_v
    WHERE Balance > 0
)
SELECT
    balance_quartile,
    ROUND(MIN(Balance), 0)                                AS min_balance,
    ROUND(MAX(Balance), 0)                                AS max_balance,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct
FROM q
GROUP BY balance_quartile
ORDER BY balance_quartile;


-- name: 10_high_risk_profile
-- question: How concentrated is churn in a simple 'high-risk profile'? (CTE + flag)
-- profile = age 45+ AND inactive AND (Germany OR 3+ products OR single product)
WITH flagged AS (
    SELECT *,
        CASE WHEN Age >= 45 AND IsActiveMember = 0
                  AND (Geography = 'Germany' OR NumOfProducts >= 3 OR NumOfProducts = 1)
             THEN 'High-risk profile' ELSE 'Everyone else' END AS profile
    FROM customers_v
)
SELECT
    profile,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_customers,
    ROUND(100.0 * AVG(is_churn), 2)                       AS churn_rate_pct,
    ROUND(100.0 * SUM(is_churn) / SUM(SUM(is_churn)) OVER (), 1) AS pct_of_all_churners
FROM flagged
GROUP BY profile;


-- name: 11_top_valuable_churners_per_country
-- question: Who are the 3 most valuable lost customers in each country? (ROW_NUMBER + PARTITION BY)
WITH ranked AS (
    SELECT
        CustomerId, Geography, Age, NumOfProducts,
        ROUND(Balance, 0)        AS balance,
        ROUND(annual_revenue, 0) AS annual_revenue,
        ROW_NUMBER() OVER (PARTITION BY Geography ORDER BY annual_revenue DESC) AS rn
    FROM customers_v
    WHERE is_churn = 1
)
SELECT Geography, CustomerId, Age, NumOfProducts, balance, annual_revenue
FROM ranked
WHERE rn <= 3
ORDER BY Geography, annual_revenue DESC;
