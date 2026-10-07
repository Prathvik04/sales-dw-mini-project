-- =====================================================================
-- 03_window_report.sql  |  Window-function reports on the star schema
-- =====================================================================

-- ---- Report A: Top 3 products per category by revenue
--      (RANK, DENSE_RANK, ROW_NUMBER, % of category share, running total)
-- name: A_top_products_per_category
WITH product_rev AS (
    SELECT p.category, p.product_name,
           ROUND(SUM(f.net_revenue), 2) AS revenue,
           ROUND(SUM(f.profit), 2)      AS profit
    FROM fact_sales f
    JOIN dim_product p ON p.product_key = f.product_key
    GROUP BY p.category, p.product_name
),
ranked AS (
    SELECT *,
           RANK()       OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk,
           DENSE_RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS dense_rnk,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS row_num,
           ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY category), 2) AS pct_of_category,
           ROUND(SUM(revenue) OVER (PARTITION BY category ORDER BY revenue DESC
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS running_category_rev
    FROM product_rev
)
SELECT category, product_name, revenue, profit, rnk, dense_rnk, row_num,
       pct_of_category, running_category_rev
FROM ranked
WHERE rnk <= 3
ORDER BY category, rnk;

-- ---- Report B: Customer league table within each region
--      (NTILE quartiles, rank, gap to the leader via FIRST_VALUE)
-- name: B_customer_ranking_by_region
WITH cust AS (
    SELECT st.region, c.customer_name,
           ROUND(SUM(f.net_revenue), 2) AS revenue,
           COUNT(DISTINCT f.order_id)   AS orders
    FROM fact_sales f
    JOIN dim_customer c  ON c.customer_key = f.customer_key
    JOIN dim_store    st ON st.store_key   = f.store_key
    GROUP BY st.region, c.customer_name
),
scored AS (
    SELECT *,
           RANK()  OVER (PARTITION BY region ORDER BY revenue DESC) AS region_rank,
           NTILE(4) OVER (PARTITION BY region ORDER BY revenue DESC) AS quartile,
           FIRST_VALUE(revenue) OVER (PARTITION BY region ORDER BY revenue DESC) AS top_customer_rev
    FROM cust
)
SELECT region, customer_name, orders, revenue, region_rank, quartile,
       ROUND(top_customer_rev - revenue, 2) AS gap_to_leader
FROM scored
WHERE region_rank <= 5
ORDER BY region, region_rank;

-- ---- Report C: Monthly revenue with running total, 3-month moving average,
--      LAG / LEAD, and cumulative share of the year
-- name: C_monthly_trend_windows
WITH monthly AS (
    SELECT d.year, d.year_month,
           ROUND(SUM(f.net_revenue), 2) AS revenue
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY d.year, d.year_month
)
SELECT year_month, revenue,
       ROUND(SUM(revenue) OVER (PARTITION BY year ORDER BY year_month
             ROWS UNBOUNDED PRECEDING), 2)                                   AS ytd_revenue,
       ROUND(AVG(revenue) OVER (ORDER BY year_month
             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)                   AS moving_avg_3m,
       LAG(revenue)  OVER (ORDER BY year_month)                              AS prev_month_rev,
       LEAD(revenue) OVER (ORDER BY year_month)                              AS next_month_rev,
       ROUND(100.0 * SUM(revenue) OVER (PARTITION BY year ORDER BY year_month
             ROWS UNBOUNDED PRECEDING) / SUM(revenue) OVER (PARTITION BY year), 1) AS pct_of_year_cum
FROM monthly
ORDER BY year_month;

-- ---- Report D: Each customer's first and latest order + days between orders
-- name: D_customer_order_gaps
WITH orders AS (
    SELECT DISTINCT f.customer_key, f.order_id, d.full_date
    FROM fact_sales f JOIN dim_date d ON d.date_key = f.date_key
),
gaps AS (
    SELECT customer_key, order_id, full_date,
           LAG(full_date) OVER (PARTITION BY customer_key ORDER BY full_date, order_id) AS prev_order_date,
           ROW_NUMBER()   OVER (PARTITION BY customer_key ORDER BY full_date, order_id) AS order_seq
    FROM orders
)
SELECT c.customer_name,
       COUNT(*)                                                   AS total_orders,
       MIN(g.full_date)                                           AS first_order,
       MAX(g.full_date)                                           AS last_order,
       ROUND(AVG(julianday(g.full_date) - julianday(g.prev_order_date)), 1) AS avg_days_between_orders
FROM gaps g
JOIN dim_customer c ON c.customer_key = g.customer_key
GROUP BY c.customer_key
HAVING COUNT(*) >= 3
ORDER BY total_orders DESC, c.customer_name
LIMIT 10;
