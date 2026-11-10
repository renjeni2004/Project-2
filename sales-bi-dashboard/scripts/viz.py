"""Plotly figure builders shared by the Streamlit app and the static exports."""
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from features import SEGMENT_ORDER

LAYOUT = dict(template="plotly_white", margin=dict(l=40, r=20, t=55, b=40), height=380)
SEGMENT_COLORS = {"Champions": "#2a9d8f", "Loyal": "#8ab17d", "Needs Attention": "#e9c46a",
                  "At Risk (high value)": "#f4a261", "Hibernating": "#e76f51"}


def _fin(fig, title, **kw):
    fig.update_layout(title=title, **{**LAYOUT, **kw})
    return fig


def monthly_trend(df):
    m = df.groupby("year_month", as_index=False)["revenue"].sum()
    m["rolling_3m"] = m["revenue"].rolling(3).mean()
    fig = go.Figure()
    fig.add_bar(x=m["year_month"], y=m["revenue"], name="Revenue", marker_color="#8ecae6")
    fig.add_scatter(x=m["year_month"], y=m["rolling_3m"], name="3-month average",
                    mode="lines+markers", line=dict(color="#023047", width=3))
    return _fin(fig, "Monthly Revenue with 3-Month Rolling Average", legend=dict(orientation="h", y=1.12))


def mom_growth(df):
    m = df.groupby("year_month", as_index=False)["revenue"].sum()
    m["mom_pct"] = m["revenue"].pct_change() * 100
    m = m.dropna()
    fig = px.bar(m, x="year_month", y="mom_pct", color=(m["mom_pct"] >= 0).map({True: "Growth", False: "Decline"}),
                 color_discrete_map={"Growth": "#2a9d8f", "Decline": "#e76f51"})
    return _fin(fig, "Month-over-Month Growth (%)", legend_title_text="")


def yoy_lines(df):
    p = df.pivot_table(index="month", columns="year", values="revenue", aggfunc="sum").reset_index()
    p = p.melt(id_vars="month", var_name="year", value_name="revenue")
    fig = px.line(p, x="month", y="revenue", color=p["year"].astype(str), markers=True)
    fig.update_xaxes(dtick=1)
    return _fin(fig, "Year-over-Year Revenue by Month", legend_title_text="Year")


def category_treemap(df):
    fig = px.treemap(df, path=[px.Constant("All sales"), "category", "product"], values="revenue",
                     color="category")
    return _fin(fig, "Revenue Mix: Category > Product", margin=dict(l=10, r=10, t=55, b=10))


def category_year_bar(df):
    c = df.groupby(["category", "year"], as_index=False)["revenue"].sum()
    fig = px.bar(c, x="category", y="revenue", color=c["year"].astype(str), barmode="group")
    return _fin(fig, "Category Revenue by Year", legend_title_text="Year")


def region_bar(df):
    r = df.groupby("region", as_index=False)["revenue"].sum().sort_values("revenue", ascending=False)
    fig = px.bar(r, x="region", y="revenue", color="region", text_auto=".3s")
    return _fin(fig, "Revenue by Region", showlegend=False)


def region_category_heatmap(df):
    p = df.pivot_table(index="region", columns="category", values="revenue", aggfunc="sum").fillna(0)
    fig = px.imshow(p, text_auto=".3s", aspect="auto", color_continuous_scale="Blues")
    return _fin(fig, "Revenue Heatmap: Region x Category")


def target_attainment(att):
    fig = px.line(att, x="year_month", y="attainment_pct", color="region", markers=True)
    fig.add_hline(y=100, line_dash="dash", line_color="grey", annotation_text="Target")
    return _fin(fig, "Monthly Target Attainment by Region (%) - targets are assumptions", legend_title_text="")


def top_products(df, n=10):
    p = df.groupby("product", as_index=False)["revenue"].sum().nlargest(n, "revenue").iloc[::-1]
    fig = px.bar(p, x="revenue", y="product", orientation="h", text_auto=".3s")
    return _fin(fig, f"Top {n} Products by Revenue", height=max(360, 32 * n + 120))


def top_customers(df, n=10):
    c = (df.groupby(["customer_id", "customer_name"], as_index=False)["revenue"].sum()
           .nlargest(n, "revenue").iloc[::-1])
    fig = px.bar(c, x="revenue", y=c["customer_name"] + " (" + c["customer_id"] + ")",
                 orientation="h", text_auto=".3s")
    fig.update_yaxes(title="")
    return _fin(fig, f"Top {n} Customers by Revenue", height=max(360, 32 * n + 120))


def pareto(df):
    c = df.groupby("customer_id")["revenue"].sum().sort_values(ascending=False).reset_index()
    c["customer_pct"] = (c.index + 1) / len(c) * 100
    c["revenue_pct"] = c["revenue"].cumsum() / c["revenue"].sum() * 100
    fig = px.area(c, x="customer_pct", y="revenue_pct")
    fig.add_hline(y=80, line_dash="dot", annotation_text="80% of revenue")
    fig.update_xaxes(title="% of customers (largest first)")
    fig.update_yaxes(title="Cumulative % of revenue")
    return _fin(fig, "Customer Pareto Curve")


def rfm_segments(rfm):
    s = (rfm.groupby("segment", as_index=False)
            .agg(customers=("customer_id", "count"), revenue=("monetary", "sum")))
    s["segment"] = pd.Categorical(s["segment"], SEGMENT_ORDER, ordered=True)
    s = s.sort_values("segment")
    fig = px.bar(s, x="segment", y="revenue", color="segment", color_discrete_map=SEGMENT_COLORS,
                 text=s["customers"].map(lambda n: f"{n} customers"))
    return _fin(fig, "Revenue by Customer Segment (RFM)", showlegend=False)


def rfm_scatter(rfm):
    fig = px.scatter(rfm, x="frequency", y="monetary", size="monetary", color="segment",
                     color_discrete_map=SEGMENT_COLORS, hover_name="customer_name",
                     hover_data={"recency_days": True, "monetary": ":,.0f"}, log_x=True, log_y=True)
    return _fin(fig, "Customers: Frequency vs Monetary (log scale)", legend_title_text="")


def payment_donut(df):
    p = df.groupby("payment_method", as_index=False)["revenue"].sum()
    fig = px.pie(p, names="payment_method", values="revenue", hole=0.5)
    return _fin(fig, "Revenue by Payment Method")


def discount_effect(df):
    d = df.assign(discount_band=(df["discount"] * 100).round().astype(int).astype(str) + "%")
    g = d.groupby("discount_band", as_index=False).agg(avg_line_value=("revenue", "mean"), lines=("revenue", "size"))
    g = g.sort_values("discount_band", key=lambda s: s.str.rstrip("%").astype(int))
    fig = px.bar(g, x="discount_band", y="avg_line_value", text_auto=".0f", hover_data=["lines"])
    return _fin(fig, "Average Order-Line Value by Discount Level")


def weekday_bar(df):
    names = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"}
    w = df.groupby("iso_weekday", as_index=False)["revenue"].sum()
    w["day"] = w["iso_weekday"].map(names)
    fig = px.bar(w, x="day", y="revenue", text_auto=".3s")
    return _fin(fig, "Revenue by Day of Week")
