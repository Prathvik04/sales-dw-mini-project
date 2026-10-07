-- =====================================================================
-- 01_schema.sql  |  Star schema (dimensional model) for retail sales
-- Grain of fact_sales: ONE ROW PER ORDER LINE (one product on one order)
-- =====================================================================

DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_store;
DROP TABLE IF EXISTS stg_orders;

-- ---------- Staging (raw, flat, denormalised source extract) ----------
CREATE TABLE stg_orders (
    order_id      INTEGER,
    order_date    TEXT,      -- YYYY-MM-DD
    customer_id   TEXT,
    customer_name TEXT,
    segment       TEXT,      -- Consumer / Corporate / Home Office
    city          TEXT,
    region        TEXT,
    product_id    TEXT,
    product_name  TEXT,
    category      TEXT,
    sub_category  TEXT,
    unit_price    REAL,
    unit_cost     REAL,
    quantity      INTEGER,
    discount_pct  REAL       -- 0.00 - 0.30
);

-- ---------- Dimensions ----------
CREATE TABLE dim_date (
    date_key       INTEGER PRIMARY KEY,   -- YYYYMMDD
    full_date      TEXT NOT NULL,
    year           INTEGER NOT NULL,
    quarter        INTEGER NOT NULL,
    month          INTEGER NOT NULL,
    month_name     TEXT NOT NULL,
    year_month     TEXT NOT NULL,         -- YYYY-MM
    day_of_month   INTEGER NOT NULL,
    day_of_week    INTEGER NOT NULL,      -- 0=Sun .. 6=Sat
    day_name       TEXT NOT NULL,
    is_weekend     INTEGER NOT NULL
);

CREATE TABLE dim_customer (
    customer_key   INTEGER PRIMARY KEY AUTOINCREMENT,  -- surrogate key
    customer_id    TEXT NOT NULL UNIQUE,               -- natural/business key
    customer_name  TEXT NOT NULL,
    segment        TEXT NOT NULL
);

CREATE TABLE dim_store (          -- geography / sales region
    store_key      INTEGER PRIMARY KEY AUTOINCREMENT,
    city           TEXT NOT NULL,
    region         TEXT NOT NULL,
    UNIQUE (city, region)
);

CREATE TABLE dim_product (
    product_key    INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id     TEXT NOT NULL UNIQUE,
    product_name   TEXT NOT NULL,
    category       TEXT NOT NULL,
    sub_category   TEXT NOT NULL
);

-- ---------- Fact ----------
CREATE TABLE fact_sales (
    sales_key      INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id       INTEGER NOT NULL,          -- degenerate dimension
    date_key       INTEGER NOT NULL REFERENCES dim_date(date_key),
    customer_key   INTEGER NOT NULL REFERENCES dim_customer(customer_key),
    product_key    INTEGER NOT NULL REFERENCES dim_product(product_key),
    store_key      INTEGER NOT NULL REFERENCES dim_store(store_key),
    quantity       INTEGER NOT NULL,
    unit_price     REAL    NOT NULL,
    discount_pct   REAL    NOT NULL,
    gross_amount   REAL    NOT NULL,          -- qty * unit_price
    discount_amt   REAL    NOT NULL,
    net_revenue    REAL    NOT NULL,          -- gross - discount
    cost_amount    REAL    NOT NULL,
    profit         REAL    NOT NULL           -- net_revenue - cost
);

CREATE INDEX ix_fact_date     ON fact_sales(date_key);
CREATE INDEX ix_fact_customer ON fact_sales(customer_key);
CREATE INDEX ix_fact_product  ON fact_sales(product_key);
CREATE INDEX ix_fact_store    ON fact_sales(store_key);
