#!/usr/bin/env python3
"""Build the sales data warehouse end to end, run all reports, validate results.

Usage:  python3 run_project.py
Outputs: sales_dw.db, output/*.csv, output/summary.md
"""
import csv
import random
import re
import sqlite3
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).parent
DB = HERE / "sales_dw.db"
OUT = HERE / "output"
OUT.mkdir(exist_ok=True)
random.seed(42)

# ------------------------------------------------------------------ data
REGIONS = {
    "North": ["Delhi", "Chandigarh", "Jaipur"],
    "South": ["Bengaluru", "Chennai", "Hyderabad"],
    "West": ["Mumbai", "Pune", "Ahmedabad"],
    "East": ["Kolkata", "Bhubaneswar", "Guwahati"],
}
SEGMENTS = ["Consumer", "Corporate", "Home Office"]
PRODUCTS = [  # id, name, category, sub_category, price, cost
    ("P01", "Laptop Pro 14", "Technology", "Computers", 65000, 48000),
    ("P02", "Wireless Mouse", "Technology", "Accessories", 900, 450),
    ("P03", "27in Monitor", "Technology", "Displays", 18000, 12500),
    ("P04", "Mechanical Keyboard", "Technology", "Accessories", 3500, 1900),
    ("P05", "Smartphone X", "Technology", "Phones", 42000, 31000),
    ("P06", "Ergonomic Chair", "Furniture", "Chairs", 14000, 8500),
    ("P07", "Standing Desk", "Furniture", "Tables", 26000, 17000),
    ("P08", "Bookcase", "Furniture", "Bookcases", 9000, 5200),
    ("P09", "Filing Cabinet", "Furniture", "Storage", 7500, 4300),
    ("P10", "A4 Paper Ream", "Office Supplies", "Paper", 350, 220),
    ("P11", "Ball Pens (Box)", "Office Supplies", "Art", 180, 90),
    ("P12", "Binder Set", "Office Supplies", "Binders", 450, 240),
    ("P13", "Stapler", "Office Supplies", "Fasteners", 300, 150),
    ("P14", "Whiteboard", "Office Supplies", "Appliances", 2500, 1500),
]
FIRST = ["Aarav", "Vivaan", "Diya", "Ananya", "Rohan", "Isha", "Kabir", "Meera", "Arjun", "Saanvi",
         "Neha", "Rahul", "Priya", "Karan", "Tara", "Dev", "Sneha", "Vikram", "Pooja", "Aditya"]
LAST = ["Sharma", "Iyer", "Reddy", "Das", "Patel", "Nair", "Singh", "Gupta", "Mehta", "Bose"]

START, END = date(2025, 1, 1), date(2026, 6, 30)


def seasonal(month):  # mild seasonality: festive Q4 lift, summer dip
    return {1: .9, 2: .85, 3: 1.0, 4: .95, 5: .9, 6: .85,
            7: .9, 8: 1.0, 9: 1.05, 10: 1.35, 11: 1.4, 12: 1.2}[month]


def generate_orders():
    customers = []
    for i in range(1, 121):
        city_region = random.choice([(c, r) for r, cs in REGIONS.items() for c in cs])
        customers.append((f"C{i:04d}", f"{random.choice(FIRST)} {random.choice(LAST)}",
                          random.choice(SEGMENTS), *city_region))
    rows, oid, d = [], 10000, START
    while d <= END:
        growth = 1 + 0.015 * ((d.year - 2025) * 12 + d.month - 1)  # gentle upward trend
        n_orders = max(0, round(random.gauss(5 * seasonal(d.month) * growth * (1.2 if d.weekday() >= 5 else 1), 1.5)))
        for _ in range(n_orders):
            oid += 1
            cust = random.choice(customers)
            for _ in range(random.choices([1, 2, 3], [.6, .3, .1])[0]):
                p = random.choices(PRODUCTS, [1, 5, 2, 3, 1.5, 1.5, 1, 1, 1, 8, 8, 6, 5, 2])[0]
                big = p[4] > 10000
                qty = random.randint(1, 2) if big else random.randint(1, 10)
                disc = random.choice([0, 0, 0, 0.05, 0.10, 0.15, 0.20, 0.30])
                rows.append((oid, d.isoformat(), cust[0], cust[1], cust[2], cust[3], cust[4],
                             p[0], p[1], p[2], p[3], p[4], p[5], qty, disc))
        d += timedelta(days=1)
    return rows


# ------------------------------------------------------------------ run
def split_named_queries(sql_text):
    """Split a report file into (name, query) using '-- name:' markers."""
    parts = re.split(r"^-- name:\s*(\S+)\s*$", sql_text, flags=re.M)
    return [(parts[i], parts[i + 1].strip()) for i in range(1, len(parts), 2)]


def fmt_table(cols, rows, limit=40):
    shown = rows[:limit]
    w = [max(len(str(c)), *(len(str(r[i])) for r in shown)) if shown else len(str(c))
         for i, c in enumerate(cols)]
    line = lambda vals: "| " + " | ".join(str(v).ljust(w[i]) for i, v in enumerate(vals)) + " |"
    out = [line(cols), "|" + "|".join("-" * (x + 2) for x in w) + "|"] + [line(r) for r in shown]
    if len(rows) > limit:
        out.append(f"... ({len(rows) - limit} more rows)")
    return "\n".join(out)


def main():
    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    cur = con.cursor()

    cur.executescript((HERE / "01_schema.sql").read_text())
    cur.executemany("INSERT INTO stg_orders VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", generate_orders())
    con.commit()
    cur.executescript((HERE / "02_load_dw.sql").read_text())
    con.commit()

    # ---------------- validation (data-quality checks)
    checks = {
        "staging lines == fact rows":
            "SELECT (SELECT COUNT(*) FROM stg_orders) = (SELECT COUNT(*) FROM fact_sales)",
        "no orphan date keys":
            "SELECT COUNT(*) = 0 FROM fact_sales f LEFT JOIN dim_date d USING(date_key) WHERE d.date_key IS NULL",
        "no orphan customer keys":
            "SELECT COUNT(*) = 0 FROM fact_sales f LEFT JOIN dim_customer c USING(customer_key) WHERE c.customer_key IS NULL",
        "no orphan product keys":
            "SELECT COUNT(*) = 0 FROM fact_sales f LEFT JOIN dim_product p USING(product_key) WHERE p.product_key IS NULL",
        "no orphan store keys":
            "SELECT COUNT(*) = 0 FROM fact_sales f LEFT JOIN dim_store s USING(store_key) WHERE s.store_key IS NULL",
        "net = gross - discount":
            "SELECT COUNT(*) = 0 FROM fact_sales WHERE ABS(net_revenue - (gross_amount - discount_amt)) > 0.02",
        "revenue ties to staging":
            "SELECT ABS((SELECT SUM(net_revenue) FROM fact_sales) - "
            "(SELECT SUM(quantity*unit_price*(1-discount_pct)) FROM stg_orders)) < 5",
        "MoM sums back to total":
            "SELECT ABS((SELECT SUM(net_revenue) FROM fact_sales) - "
            "(SELECT SUM(m) FROM (SELECT SUM(f.net_revenue) m FROM fact_sales f JOIN dim_date d USING(date_key) GROUP BY year_month))) < 0.01",
    }
    results, failed = [], 0
    for name, q in checks.items():
        ok = bool(cur.execute(q).fetchone()[0])
        failed += not ok
        results.append(f"{'PASS' if ok else 'FAIL'}  {name}")
    print("\n".join(results))

    # ---------------- reports
    summary = ["# Report outputs\n"]
    cnt = {t: cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
           for t in ["stg_orders", "dim_date", "dim_customer", "dim_product", "dim_store", "fact_sales"]}
    summary.append("## Warehouse row counts\n```\n" + "\n".join(f"{k:14s}{v:>8,}" for k, v in cnt.items()) + "\n```\n")
    summary.append("## Data-quality checks\n```\n" + "\n".join(results) + "\n```\n")

    for sqlfile in ["03_window_report.sql", "04_mom_growth_cte.sql"]:
        for name, q in split_named_queries((HERE / sqlfile).read_text()):
            cur.execute(q)
            cols = [c[0] for c in cur.description]
            rows = cur.fetchall()
            with open(OUT / f"{name}.csv", "w", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(cols)
                w.writerows(rows)
            summary.append(f"## {name}\n```\n{fmt_table(cols, rows)}\n```\n")
            print(f"ran {name}: {len(rows)} rows")

    (OUT / "summary.md").write_text("\n".join(summary))
    con.close()
    print("\nALL CHECKS PASSED" if not failed else f"\n{failed} CHECK(S) FAILED")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
