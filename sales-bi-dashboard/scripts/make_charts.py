"""Static PNG charts (Matplotlib/Seaborn) + a standalone Plotly HTML preview of the dashboard."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick
import seaborn as sns

import viz, wrangling
from config import DASH_DIR, VIZ_DIR
from features import SEGMENT_ORDER, compute_rfm, load_sales
from viz import SEGMENT_COLORS

sns.set_theme(style="whitegrid")
MONEY = mtick.FuncFormatter(lambda x, _: f"${x:,.0f}")


def save(fig, name):
    fig.tight_layout(); fig.savefig(VIZ_DIR / name, dpi=130); plt.close(fig)


def main() -> None:
    df = load_sales()
    rfm = compute_rfm(df)

    m = df.groupby("year_month")["revenue"].sum()
    fig, ax = plt.subplots(figsize=(11, 4.5))
    ax.bar(m.index, m.values, color="#8ecae6", label="Revenue")
    ax.plot(m.index, m.rolling(3).mean().values, color="#023047", marker="o", lw=2.5, label="3-month average")
    ax.yaxis.set_major_formatter(MONEY); ax.tick_params(axis="x", rotation=60); ax.legend()
    ax.set_title("Monthly Revenue with Rolling Average", fontweight="bold")
    save(fig, "01_monthly_revenue_rolling.png")

    s = rfm.groupby("segment")["monetary"].sum().reindex(SEGMENT_ORDER)
    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.bar(s.index, s.values, color=[SEGMENT_COLORS[k] for k in s.index])
    ax.yaxis.set_major_formatter(MONEY); ax.tick_params(axis="x", rotation=20)
    ax.set_title("Revenue by RFM Customer Segment", fontweight="bold")
    save(fig, "02_rfm_segments.png")

    p = df.pivot_table(index="region", columns="category", values="revenue", aggfunc="sum") / 1000
    fig, ax = plt.subplots(figsize=(9, 4.5))
    sns.heatmap(p, annot=True, fmt=".0f", cmap="Blues", ax=ax)
    ax.set_title("Revenue by Region x Category ($ thousands)", fontweight="bold")
    save(fig, "03_region_category_heatmap.png")

    c = df.groupby(["category", "year"])["revenue"].sum().reset_index()
    fig, ax = plt.subplots(figsize=(9, 4.5))
    sns.barplot(data=c, x="category", y="revenue", hue="year", ax=ax)
    ax.yaxis.set_major_formatter(MONEY); ax.set_title("Category Revenue by Year", fontweight="bold")
    save(fig, "04_category_by_year.png")

    t = df.groupby("product")["revenue"].sum().nlargest(10).iloc[::-1]
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.barh(t.index, t.values, color=sns.color_palette("deep")[0]); ax.xaxis.set_major_formatter(MONEY)
    ax.set_title("Top 10 Products by Revenue", fontweight="bold")
    save(fig, "05_top_products.png")

    cu = df.groupby("customer_id")["revenue"].sum().sort_values(ascending=False)
    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.plot((range(1, len(cu) + 1)), cu.cumsum() / cu.sum() * 100)
    ax.set_xlabel("Customers (largest first)"); ax.set_ylabel("Cumulative % of revenue")
    ax.axhline(80, ls=":", color="grey"); ax.set_title("Customer Pareto Curve", fontweight="bold")
    save(fig, "06_customer_pareto.png")

    att = wrangling.integrate_targets(df).pivot(index="year_month", columns="region", values="attainment_pct")
    fig, ax = plt.subplots(figsize=(10, 4.5))
    att.plot(ax=ax); ax.axhline(100, ls="--", color="grey")
    ax.set_title("Monthly Target Attainment % by Region (illustrative targets)", fontweight="bold")
    save(fig, "07_target_attainment.png")

    corr = df[["quantity", "unit_price", "discount", "revenue"]].corr()
    fig, ax = plt.subplots(figsize=(6, 5))
    sns.heatmap(corr, annot=True, fmt=".2f", cmap="coolwarm", center=0, ax=ax)
    ax.set_title("Correlation Matrix", fontweight="bold")
    save(fig, "08_correlation.png")
    print(f"8 charts saved to {VIZ_DIR}")

    # standalone interactive preview (no database needed to open it)
    figs = [viz.monthly_trend(df), viz.category_treemap(df), viz.region_bar(df),
            viz.region_category_heatmap(df), viz.rfm_segments(rfm), viz.rfm_scatter(rfm),
            viz.top_products(df), viz.pareto(df)]
    k = {"Total Revenue": f"${df.revenue.sum():,.0f}", "Orders": f"{df.order_id.nunique():,}",
         "Customers": f"{df.customer_id.nunique():,}", "Units": f"{int(df.quantity.sum()):,}",
         "Avg Order Value": f"${df.revenue.sum() / df.order_id.nunique():,.0f}"}
    cards = "".join(f'<div class="c"><span>{a}</span><b>{b}</b></div>' for a, b in k.items())
    charts = "".join(f'<div class="g">{f.to_html(full_html=False, include_plotlyjs="cdn" if i == 0 else False)}</div>'
                     for i, f in enumerate(figs))
    html = ("<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>Sales BI Dashboard Preview</title><style>body{font-family:Arial,sans-serif;background:#f4f6f9;margin:0;padding:24px}"
            ".cs{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin:16px 0}"
            ".c{background:#fff;border-radius:10px;padding:14px;box-shadow:0 1px 4px #0002}.c span{display:block;color:#666;font-size:13px}.c b{font-size:24px}"
            ".gr{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:16px}.g{background:#fff;border-radius:10px;padding:6px;box-shadow:0 1px 4px #0002}"
            f"</style></head><body><h1>Sales BI Dashboard - Static Preview</h1><p>Snapshot exported from PostgreSQL. "
            f"For live filters run <code>streamlit run dashboard/app.py</code>.</p><div class='cs'>{cards}</div><div class='gr'>{charts}</div></body></html>")
    (DASH_DIR / "dashboard_preview.html").write_text(html, encoding="utf-8")
    print("dashboard_preview.html saved")


if __name__ == "__main__":
    main()
