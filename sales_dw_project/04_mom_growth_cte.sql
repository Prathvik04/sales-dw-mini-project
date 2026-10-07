-- =====================================================================
-- 04_mom_growth_cte.sql  |  Month-over-Month growth using chained CTEs
-- =====================================================================

-- ---- Report E: Overall MoM revenue, profit and order growth
-- name: E_mom_growth_overall
WITH monthly_base AS (                         -- step 1: aggregate to month grain
    SELECT d.year_month,
           SUM(f.net_revenue)           AS revenue,
           SUM(f.profit)                AS profit,
           COUNT(DISTINCT f.order_id)   AS orders
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY d.year_month
),
with_prev AS (                                 -- step 2: attach previous month
    SELECT year_month, revenue, profit, orders,
           LAG(revenue) OVER (ORDER BY year_month) AS prev_revenue,
           LAG(profit)  OVER (ORDER BY year_month) AS prev_profit,
           LAG(orders)  OVER (ORDER BY year_month) AS prev_orders
    FROM monthly_base
),
growth AS (                                    -- step 3: compute growth rates
    SELECT year_month,
           ROUND(revenue, 2) AS revenue,
           ROUND(prev_revenue, 2) AS prev_revenue,
           ROUND(revenue - prev_revenue, 2) AS revenue_change,
           ROUND(100.0 * (revenue - prev_revenue) / NULLIF(prev_revenue, 0), 2) AS revenue_mom_pct,
           ROUND(100.0 * (profit  - prev_profit)  / NULLIF(prev_profit, 0), 2)  AS profit_mom_pct,
           ROUND(100.0 * (orders  - prev_orders)  / NULLIF(prev_orders, 0), 2)  AS orders_mom_pct
    FROM with_prev
)
SELECT year_month, revenue, prev_revenue, revenue_change,
       revenue_mom_pct, profit_mom_pct, orders_mom_pct,
       CASE WHEN revenue_mom_pct IS NULL THEN 'n/a (first month)'
            WHEN revenue_mom_pct >  5 THEN 'Strong growth'
            WHEN revenue_mom_pct >= 0 THEN 'Flat / mild growth'
            ELSE 'Decline' END AS trend_flag
FROM growth
ORDER BY year_month;

-- ---- Report F: MoM revenue growth by product category (pivot-style)
-- name: F_mom_growth_by_category
WITH cat_month AS (
    SELECT d.year_month, p.category, SUM(f.net_revenue) AS revenue
    FROM fact_sales f
    JOIN dim_date    d ON d.date_key    = f.date_key
    JOIN dim_product p ON p.product_key = f.product_key
    GROUP BY d.year_month, p.category
),
cat_growth AS (
    SELECT year_month, category, revenue,
           100.0 * (revenue - LAG(revenue) OVER (PARTITION BY category ORDER BY year_month))
                 / NULLIF(LAG(revenue) OVER (PARTITION BY category ORDER BY year_month), 0) AS mom_pct
    FROM cat_month
)
SELECT year_month,
       ROUND(MAX(CASE WHEN category = 'Technology'      THEN mom_pct END), 2) AS technology_mom_pct,
       ROUND(MAX(CASE WHEN category = 'Furniture'       THEN mom_pct END), 2) AS furniture_mom_pct,
       ROUND(MAX(CASE WHEN category = 'Office Supplies' THEN mom_pct END), 2) AS office_supplies_mom_pct
FROM cat_growth
GROUP BY year_month
ORDER BY year_month;

-- ---- Report G: Best and worst growth months (CTE + RANK)
-- name: G_best_worst_months
WITH m AS (
    SELECT d.year_month, SUM(f.net_revenue) AS revenue
    FROM fact_sales f JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY d.year_month
),
g AS (
    SELECT year_month, revenue,
           100.0 * (revenue - LAG(revenue) OVER (ORDER BY year_month))
                 / NULLIF(LAG(revenue) OVER (ORDER BY year_month), 0) AS mom_pct
    FROM m
),
r AS (
    SELECT *, RANK() OVER (ORDER BY mom_pct DESC) AS best_rank,
              RANK() OVER (ORDER BY mom_pct ASC)  AS worst_rank
    FROM g WHERE mom_pct IS NOT NULL
)
SELECT 'Best'  AS bucket, year_month, ROUND(revenue,2) AS revenue, ROUND(mom_pct,2) AS mom_pct FROM r WHERE best_rank  <= 3
UNION ALL
SELECT 'Worst' AS bucket, year_month, ROUND(revenue,2), ROUND(mom_pct,2)                      FROM r WHERE worst_rank <= 3
ORDER BY bucket, mom_pct DESC;
