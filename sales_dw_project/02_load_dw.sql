-- =====================================================================
-- 02_load_dw.sql  |  Transform staging -> dimensions -> fact
-- =====================================================================

-- dim_date: recursive CTE generates every calendar day in the data range
WITH RECURSIVE bounds AS (
    SELECT MIN(order_date) AS d0, MAX(order_date) AS d1 FROM stg_orders
),
cal(d) AS (
    SELECT d0 FROM bounds
    UNION ALL
    SELECT date(d, '+1 day') FROM cal, bounds WHERE d < d1
)
INSERT INTO dim_date
SELECT
    CAST(strftime('%Y%m%d', d) AS INTEGER),
    d,
    CAST(strftime('%Y', d) AS INTEGER),
    (CAST(strftime('%m', d) AS INTEGER) + 2) / 3,
    CAST(strftime('%m', d) AS INTEGER),
    CASE strftime('%m', d)
        WHEN '01' THEN 'January'  WHEN '02' THEN 'February' WHEN '03' THEN 'March'
        WHEN '04' THEN 'April'    WHEN '05' THEN 'May'      WHEN '06' THEN 'June'
        WHEN '07' THEN 'July'     WHEN '08' THEN 'August'   WHEN '09' THEN 'September'
        WHEN '10' THEN 'October'  WHEN '11' THEN 'November' ELSE 'December' END,
    strftime('%Y-%m', d),
    CAST(strftime('%d', d) AS INTEGER),
    CAST(strftime('%w', d) AS INTEGER),
    CASE strftime('%w', d)
        WHEN '0' THEN 'Sunday'   WHEN '1' THEN 'Monday' WHEN '2' THEN 'Tuesday'
        WHEN '3' THEN 'Wednesday' WHEN '4' THEN 'Thursday' WHEN '5' THEN 'Friday'
        ELSE 'Saturday' END,
    CASE WHEN strftime('%w', d) IN ('0','6') THEN 1 ELSE 0 END
FROM cal;

INSERT INTO dim_customer (customer_id, customer_name, segment)
SELECT DISTINCT customer_id, customer_name, segment FROM stg_orders ORDER BY customer_id;

INSERT INTO dim_store (city, region)
SELECT DISTINCT city, region FROM stg_orders ORDER BY region, city;

INSERT INTO dim_product (product_id, product_name, category, sub_category)
SELECT DISTINCT product_id, product_name, category, sub_category FROM stg_orders ORDER BY product_id;

-- fact_sales: resolve surrogate keys and derive measures
INSERT INTO fact_sales (order_id, date_key, customer_key, product_key, store_key,
                        quantity, unit_price, discount_pct,
                        gross_amount, discount_amt, net_revenue, cost_amount, profit)
SELECT
    s.order_id,
    CAST(strftime('%Y%m%d', s.order_date) AS INTEGER),
    c.customer_key,
    p.product_key,
    st.store_key,
    s.quantity,
    s.unit_price,
    s.discount_pct,
    ROUND(s.quantity * s.unit_price, 2),
    ROUND(s.quantity * s.unit_price * s.discount_pct, 2),
    ROUND(s.quantity * s.unit_price * (1 - s.discount_pct), 2),
    ROUND(s.quantity * s.unit_cost, 2),
    ROUND(s.quantity * s.unit_price * (1 - s.discount_pct) - s.quantity * s.unit_cost, 2)
FROM stg_orders s
JOIN dim_customer c  ON c.customer_id = s.customer_id
JOIN dim_product  p  ON p.product_id  = s.product_id
JOIN dim_store    st ON st.city = s.city AND st.region = s.region;
