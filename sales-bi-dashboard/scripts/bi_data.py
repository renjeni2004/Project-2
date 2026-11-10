"""BI data layer: every dashboard number comes from parameterised SQL on PostgreSQL.

User input (filters, search text) is ALWAYS passed as bound parameters, never pasted
into the SQL string, which prevents SQL injection.
"""
from dataclasses import dataclass, replace
from datetime import date, timedelta

import pandas as pd

from db import read_sql


@dataclass(frozen=True)
class Filters:
    start: date
    end: date
    regions: tuple
    categories: tuple
    payments: tuple
    search: str = ""


WHERE = """
WHERE order_date BETWEEN :start AND :end
  AND region         IN :regions
  AND category       IN :categories
  AND payment_method IN :payments
  AND (:search = '' OR customer_name ILIKE '%' || :search || '%'
                    OR customer_id   ILIKE '%' || :search || '%'
                    OR product       ILIKE '%' || :search || '%')
"""


def _params(f: Filters) -> dict:
    return {"start": f.start, "end": f.end, "regions": list(f.regions),
            "categories": list(f.categories), "payments": list(f.payments),
            "search": f.search.strip()}


def filter_options() -> dict:
    """Values for the sidebar widgets, straight from the database."""
    meta = read_sql("SELECT MIN(order_date) AS lo, MAX(order_date) AS hi FROM orders")
    return {
        "min_date": meta["lo"][0].date(), "max_date": meta["hi"][0].date(),
        "regions": read_sql("SELECT region_name FROM regions ORDER BY 1")["region_name"].tolist(),
        "categories": read_sql("SELECT category_name FROM categories ORDER BY 1")["category_name"].tolist(),
        "payments": read_sql("SELECT DISTINCT payment_method FROM orders ORDER BY 1")["payment_method"].tolist(),
    }


def fetch_sales(f: Filters) -> pd.DataFrame:
    """Filtered order lines (filtering happens inside PostgreSQL)."""
    return read_sql(f"SELECT * FROM vw_sales_detail {WHERE} ORDER BY order_date, item_id", _params(f))


KPI_SQL = f"""
SELECT COALESCE(SUM(revenue), 0)                                  AS revenue,
       COUNT(DISTINCT order_id)                                   AS orders,
       COUNT(DISTINCT customer_id)                                AS customers,
       COALESCE(SUM(quantity), 0)                                 AS units,
       COALESCE(SUM(revenue) / NULLIF(COUNT(DISTINCT order_id), 0), 0)  AS avg_order_value,
       COALESCE(AVG(discount), 0) * 100                           AS avg_discount_pct
FROM vw_sales_detail {WHERE}
"""


def fetch_kpis(f: Filters) -> dict:
    row = read_sql(KPI_SQL, _params(f)).iloc[0]
    return {k: float(v) for k, v in row.items()}


def previous_period(f: Filters) -> Filters:
    """Same-length window immediately before the selected one (for KPI deltas)."""
    length = (f.end - f.start) + timedelta(days=1)
    return replace(f, start=f.start - length, end=f.start - timedelta(days=1))


def pct_change(now: float, before: float) -> float | None:
    return None if before == 0 else (now / before - 1) * 100
