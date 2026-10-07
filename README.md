# Sales Data Warehouse: Dimensional Model + Window Functions + CTE MoM Growth

> A retail sales data warehouse built in SQL: a star schema, window-function reports and CTE-based month-over-month (MoM) growth analysis.

**Tech:** SQL (SQLite 3.25+) · Python 3 (standard library only)

---

## Overview

This mini project takes a flat sales extract and turns it into an analytics-ready warehouse:

1. **Dimensional model:** a star schema with one fact table and four dimensions.
2. **Window-function report:** ranking, percentile buckets, running totals, moving averages and `LAG`/`LEAD`.
3. **CTE month-over-month growth:** chained CTEs that compute revenue, profit and order growth, overall and by category.

The data is **synthetic** (seeded, so it is reproducible): 4,783 order lines from Jan 2025 to Jun 2026. This lets the project run without any external files.

---

## Project structure

```
sales_dw_project/
├── 01_schema.sql           # Star schema: staging, dimensions, fact table, indexes
├── 02_load_dw.sql          # Staging -> dimensions -> fact (recursive CTE builds dim_date)
├── 03_window_report.sql    # Window-function reports (A-D)
├── 04_mom_growth_cte.sql   # CTE month-over-month growth reports (E-G)
├── run_project.py          # Builds the DB, runs data-quality checks and all reports
├── sales_dw.db             # Generated SQLite database
├── output/                 # One CSV per report + summary.md
└── README.md
```

---

## 1. Dimensional model (star schema)

```
            dim_date ─┐
        dim_customer ─┤
                      ├──< fact_sales >──┬─ dim_product
            dim_store ┘                  │
                                   (order_id = degenerate dimension)
```

| Table | Type | Grain / key |
|---|---|---|
| `fact_sales` | Fact | One row per order line, with foreign keys to all four dimensions |
| `dim_date` | Dimension | One row per calendar day (`date_key` = YYYYMMDD) |
| `dim_customer` | Dimension | One row per customer (surrogate `customer_key`) |
| `dim_product` | Dimension | One row per product, with category and sub-category |
| `dim_store` | Dimension | One row per city and region |
| `stg_orders` | Staging | Raw flat extract (4,783 rows) |

**Measures:** `quantity`, `gross_amount`, `discount_amt`, `net_revenue`, `cost_amount`, `profit`

---

## 2. Window-function report (`03_window_report.sql`)

| Report | What it shows | Functions used |
|---|---|---|
| A | Top 3 products per category | `RANK`, `DENSE_RANK`, `ROW_NUMBER`, `SUM() OVER` (share %, running total) |
| B | Top 5 customers per region | `RANK`, `NTILE`, `FIRST_VALUE` |
| C | Monthly revenue trend | YTD running `SUM`, 3-month moving `AVG`, `LAG`, `LEAD` |
| D | Customer order frequency | `LAG`, `ROW_NUMBER`, date difference |

---

## 3. CTE month-over-month growth (`04_mom_growth_cte.sql`)

| Report | Approach |
|---|---|
| E. Overall MoM growth | Three chained CTEs: aggregate by month, attach the previous month with `LAG`, then compute growth % (with a `NULLIF` divide-by-zero guard) and a trend flag |
| F. MoM growth by category | CTEs plus a conditional-aggregation pivot |
| G. Best and worst months | CTE plus `RANK` plus `UNION ALL` |

`02_load_dw.sql` also uses a **recursive CTE** to generate the date dimension.

### Sample output: MoM revenue growth

| year_month | revenue | revenue_mom_pct | trend_flag |
|------------|---------|-----------------|------------|
| 2025-02 | 2,203,624.5 | -5.86 | Decline |
| 2025-03 | 2,907,675.0 | 31.95 | Strong growth |
| 2025-04 | 1,776,163.5 | -38.91 | Decline |
| 2025-05 | 3,000,583.0 | 68.94 | Strong growth |
| 2025-06 | 1,908,193.0 | -36.41 | Decline |

---

## How to run

**Requirements:** Python 3.8 or newer. SQLite is built into Python, so there is nothing to install.

```bash
git clone https://github.com/Prathvik04/sales-dw-mini-project.git
cd sales-dw-mini-project
python run_project.py        # use python3 on Mac/Linux
```

This will:
- build `sales_dw.db`
- run 8 data-quality checks (row counts, no orphan keys, revenue reconciliation)
- run all 7 reports and save them to `output/*.csv` and `output/summary.md`

To explore the database yourself:

```bash
sqlite3 sales_dw.db
```
```sql
.headers on
.mode column
SELECT * FROM fact_sales LIMIT 5;
```

You can also open `sales_dw.db` in DB Browser for SQLite, DBeaver, or the SQLite extension in VS Code.

---

## Data-quality checks

All of these pass on every run:

- Staging row count equals fact row count
- No orphan date, customer, product or store keys
- `net_revenue = gross_amount - discount_amt`
- Fact revenue reconciles to the staging data
- Monthly revenue sums back to the total

---

## Key findings

- **Seasonality:** revenue peaks in Oct-Dec 2025 (about 3.6M-4.0M per month) compared with about 1.8M-3.0M in other months.
- **Volatile MoM growth:** growth ranged from -39% to +69% in 2025. A few high-ticket items (laptops, phones, furniture) swing monthly revenue, while order counts move far less.
- **Steadier 2026:** monthly revenue stayed within 2.5M-3.4M, with smaller MoM swings.
- **Category mix:** Technology is the largest category by revenue, led by the Laptop Pro 14.

---

## Using your own data

Load your data into `stg_orders` (columns are defined in `01_schema.sql`) and skip the data generator in `run_project.py`. The rest of the pipeline works unchanged.

To port to PostgreSQL, MySQL 8 or SQL Server, replace the SQLite date functions (`strftime`, `julianday`, `date(d, '+1 day')`) with that database's equivalents.

---

## Author

**Prathvik** · [GitHub](https://github.com/Prathvik04)
