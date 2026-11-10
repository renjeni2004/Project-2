"""Business Intelligence Sales Analytics Dashboard.

Run from the project root:   streamlit run dashboard/app.py
Data source: PostgreSQL (see .env). All filtering happens in SQL.
"""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import pandas as pd
import streamlit as st

import bi_data as bd
import viz
import wrangling
from db import list_queries, load_query, run_query
from features import compute_rfm
from report import dashboard_workbook

st.set_page_config(page_title="Sales BI Dashboard", page_icon=":bar_chart:", layout="wide")


def show(container, fig, key: str) -> None:
    """Render a Plotly figure; unique keys let the same chart appear in several tabs."""
    container.plotly_chart(fig, width="stretch", key=key)


# ----------------------------------------------------------------- cached data access
@st.cache_data(ttl=600, show_spinner=False)
def get_options() -> dict:
    return bd.filter_options()


@st.cache_data(ttl=600, show_spinner="Querying PostgreSQL...")
def get_sales(f: bd.Filters) -> pd.DataFrame:
    return bd.fetch_sales(f)


@st.cache_data(ttl=600, show_spinner=False)
def get_kpis(f: bd.Filters) -> dict:
    return bd.fetch_kpis(f)


@st.cache_data(ttl=600, show_spinner="Running query...")
def get_query_result(name: str) -> pd.DataFrame:
    return run_query(name)


# ----------------------------------------------------------------- connection check
try:
    opts = get_options()
except Exception as exc:                                  # noqa: BLE001
    st.error("Could not connect to PostgreSQL. Check DATABASE_URL in your .env file and that the "
             "server is running, then run `python scripts/load_database.py`.")
    st.code(str(exc)[:400])
    st.stop()

# ----------------------------------------------------------------- sidebar filters
st.sidebar.title("Filters")
picked = st.sidebar.date_input("Order date range", value=(opts["min_date"], opts["max_date"]),
                               min_value=opts["min_date"], max_value=opts["max_date"])
start, end = (picked[0], picked[1]) if isinstance(picked, (tuple, list)) and len(picked) == 2 \
    else (opts["min_date"], opts["max_date"])
regions = st.sidebar.multiselect("Region", opts["regions"], default=opts["regions"])
categories = st.sidebar.multiselect("Category", opts["categories"], default=opts["categories"])
payments = st.sidebar.multiselect("Payment method", opts["payments"], default=opts["payments"])
search = st.sidebar.text_input("Search customer name / ID / product", "")

filters = bd.Filters(start, end, tuple(regions), tuple(categories), tuple(payments), search)
df = get_sales(filters)

st.title("Sales Analytics Dashboard")
st.caption(f"{start:%d %b %Y} to {end:%d %b %Y} | {len(df):,} order lines match your filters")
if df.empty:
    st.warning("No data matches these filters. Widen the date range or clear the search box.")
    st.stop()

# ----------------------------------------------------------------- KPI cards
k, prev = get_kpis(filters), get_kpis(bd.previous_period(filters))


def delta(key: str):
    d = bd.pct_change(k[key], prev[key])
    return None if d is None else f"{d:+.1f}% vs previous period"


c1, c2, c3, c4, c5 = st.columns(5)
c1.metric("Revenue", f"${k['revenue']:,.0f}", delta("revenue"))
c2.metric("Orders", f"{k['orders']:,.0f}", delta("orders"))
c3.metric("Customers", f"{k['customers']:,.0f}", delta("customers"))
c4.metric("Avg order value", f"${k['avg_order_value']:,.0f}", delta("avg_order_value"))
c5.metric("Units sold", f"{k['units']:,.0f}", delta("units"))

rfm = compute_rfm(df)

tab_over, tab_rev, tab_cust, tab_prod, tab_reg, tab_trend, tab_sql, tab_data = st.tabs(
    ["Overview", "Revenue", "Customers", "Products", "Regions", "Trends", "SQL Explorer", "Data & Export"])

with tab_over:
    show(st, viz.monthly_trend(df), "chart1")
    a, b = st.columns(2)
    show(a, viz.category_treemap(df), "chart2")
    show(b, viz.region_bar(df), "chart3")

with tab_rev:
    a, b = st.columns(2)
    show(a, viz.yoy_lines(df), "chart4")
    show(b, viz.category_year_bar(df), "chart5")
    a, b = st.columns(2)
    show(a, viz.payment_donut(df), "chart6")
    show(b, viz.discount_effect(df), "chart7")

with tab_cust:
    st.subheader("Customer segmentation (RFM)")
    st.caption("Recency = days since last order | Frequency = number of orders | Monetary = total spend. "
               "Scores 1-5 (5 = best) within the filtered data.")
    a, b = st.columns(2)
    show(a, viz.rfm_segments(rfm), "chart8")
    show(b, viz.rfm_scatter(rfm), "chart9")
    a, b = st.columns(2)
    n_top = a.slider("Top N customers", 5, 25, 10)
    show(a, viz.top_customers(df, n_top), "chart10")
    show(b, viz.pareto(df), "chart11")
    seg = st.selectbox("Show customers in segment", ["All"] + sorted(rfm["segment"].unique()))
    st.dataframe(rfm if seg == "All" else rfm[rfm["segment"] == seg], width="stretch", hide_index=True)

with tab_prod:
    n_prod = st.slider("Top N products", 5, 20, 10)
    a, b = st.columns(2)
    show(a, viz.top_products(df, n_prod), "chart12")
    show(b, viz.category_treemap(df), "chart13")
    perf = (df.groupby(["category", "product"], as_index=False)
              .agg(units=("quantity", "sum"), revenue=("revenue", "sum"), avg_discount=("discount", "mean")))
    perf["share_pct"] = (perf["revenue"] / perf["revenue"].sum() * 100).round(2)
    perf["rank"] = perf["revenue"].rank(ascending=False, method="min").astype(int)
    st.dataframe(perf.sort_values("rank"), width="stretch", hide_index=True)

with tab_reg:
    a, b = st.columns(2)
    show(a, viz.region_bar(df), "chart14")
    show(b, viz.region_category_heatmap(df), "chart15")
    show(st, viz.target_attainment(wrangling.integrate_targets(df)), "chart16")

with tab_trend:
    show(st, viz.monthly_trend(df), "chart17")
    a, b = st.columns(2)
    show(a, viz.mom_growth(df), "chart18")
    show(b, viz.weekday_bar(df), "chart19")

with tab_sql:
    st.subheader("SQL Explorer")
    st.caption("Saved analytical queries from `database/queries/` (joins, CTEs, window functions). "
               "They run on the full database and ignore the sidebar filters.")
    name = st.selectbox("Choose a query", list_queries())
    st.code(load_query(name), language="sql")
    st.dataframe(get_query_result(name), width="stretch", hide_index=True)

with tab_data:
    st.subheader("Filtered data")
    st.dataframe(df.head(1000), width="stretch", hide_index=True)
    st.caption(f"Showing the first 1,000 of {len(df):,} rows. Exports contain all filtered rows.")
    a, b = st.columns(2)
    a.download_button("Download CSV", df.to_csv(index=False).encode("utf-8"),
                      file_name=f"sales_{date.today():%Y%m%d}.csv", mime="text/csv")
    b.download_button("Download Excel report", dashboard_workbook(df, rfm),
                      file_name=f"sales_report_{date.today():%Y%m%d}.xlsx",
                      mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
