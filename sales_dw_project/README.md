# Mini Project: Dimensional Model + Window Function Report + CTE MoM Growth

A retail sales data warehouse built in SQL (SQLite 3.25+; the SQL is ANSI-style and ports to PostgreSQL/MySQL 8/SQL Server with small date-function changes).

## 1. Dimensional model (star schema)

```
            dim_date ─┐
        dim_customer ─┤
                      ├──< fact_sales >──┬─ dim_product
            dim_store ┘                  │
                                   (order_id = degenerate dim)
```

| Table | Type | Grain / key |
|---|---|---|
| `fact_sales` | Fact | One row per order line; FKs to all 4 dimensions |
| `dim_date` | Dimension | One row per calendar day (`date_key` = YYYYMMDD) |
| `dim_customer` | Dimension | One row per customer (surrogate `customer_key`) |
| `dim_product` | Dimension | One row per product, category hierarchy |
| `dim_store` | Dimension | One row per city/region |
| `stg_orders` | Staging | Raw flat extract (4,783 rows, Jan 2025 – Jun 2026) |

Measures: `quantity`, `gross_amount`, `discount_amt`, `net_revenue`, `cost_amount`, `profit`.

## 2. Window-function report (`03_window_report.sql`)
| Report | Functions used |
|---|---|
| A. Top 3 products per category | `RANK`, `DENSE_RANK`, `ROW_NUMBER`, `SUM() OVER` (share %, running total) |
| B. Customer ranking per region | `RANK`, `NTILE`, `FIRST_VALUE` |
| C. Monthly trend | running YTD `SUM`, 3-month moving `AVG`, `LAG`, `LEAD` |
| D. Customer order gaps | `LAG`, `ROW_NUMBER`, `julianday` diff |

## 3. CTE month-over-month growth (`04_mom_growth_cte.sql`)
| Report | Approach |
|---|---|
| E. Overall MoM | 3 chained CTEs: aggregate → `LAG` prior month → growth % with `NULLIF` divide-by-zero guard + trend flag |
| F. MoM by category | CTEs + conditional-aggregation pivot |
| G. Best / worst months | CTE + `RANK` + `UNION ALL` |

`02_load_dw.sql` also uses a **recursive CTE** to generate `dim_date`.

## 4. Run it
```bash
python3 run_project.py
```
Builds `sales_dw.db`, runs 8 data-quality checks (all pass), writes each report to `output/*.csv` and `output/summary.md`.

## 5. Key findings
- Revenue is seasonal: Oct–Dec 2025 was the peak (about ₹3.6–4.0M a month) against about ₹1.8–3.0M in the other months.
- MoM growth is volatile (−39% to +69% in 2025) because a few high-ticket items (laptops, phones, furniture) swing monthly revenue; order counts move far less.
- 2026 is steadier (monthly revenue ₹2.5–3.4M) with smaller MoM swings.
- Technology is the biggest category; Laptop Pro 14 leads it by revenue.

Data is synthetic (seeded, reproducible) so the project runs without external files. To use real data, load it into `stg_orders` and skip the generator.
