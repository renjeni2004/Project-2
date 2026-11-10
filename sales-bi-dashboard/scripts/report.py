"""Executive report (Markdown) and formatted Excel workbook, built from PostgreSQL data."""
import io

import pandas as pd
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

import wrangling
from config import REPORT_DIR
from db import read_sql
from features import compute_rfm, load_sales

HEADER_FILL = PatternFill("solid", fgColor="1F3864")


def make_workbook(sheets: dict[str, pd.DataFrame]) -> bytes:
    """Write DataFrames to a styled .xlsx and return the bytes (for files or st.download_button)."""
    buf = io.BytesIO()
    with pd.ExcelWriter(buf, engine="openpyxl") as xw:
        for name, frame in sheets.items():
            frame.to_excel(xw, sheet_name=name[:31], index=False)
            ws = xw.sheets[name[:31]]
            ws.freeze_panes = "A2"
            for cell in ws[1]:
                cell.font = Font(name="Arial", bold=True, color="FFFFFF", size=10)
                cell.fill = HEADER_FILL
                cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            for col_idx, col in enumerate(frame.columns, start=1):
                letter = get_column_letter(col_idx)
                width = max(len(str(col)), *(len(str(v)) for v in frame[col].head(200))) + 2
                ws.column_dimensions[letter].width = min(width, 40)
                is_float = pd.api.types.is_float_dtype(frame[col])
                for row in ws.iter_rows(min_row=2, min_col=col_idx, max_col=col_idx):
                    for cell in row:
                        cell.font = Font(name="Arial", size=10)
                        if is_float:
                            cell.number_format = "#,##0.00"
                        elif pd.api.types.is_datetime64_any_dtype(frame[col]):
                            cell.number_format = "yyyy-mm-dd"
    return buf.getvalue()


def dashboard_workbook(df: pd.DataFrame, rfm: pd.DataFrame) -> bytes:
    """The workbook offered by the 'Export Excel' button (respects dashboard filters)."""
    k = {"Total revenue": df["revenue"].sum(), "Orders": df["order_id"].nunique(),
         "Customers": df["customer_id"].nunique(), "Units sold": int(df["quantity"].sum()),
         "Avg order value": df["revenue"].sum() / max(df["order_id"].nunique(), 1)}
    return make_workbook({
        "KPIs": pd.DataFrame({"KPI": list(k), "Value": [float(v) for v in k.values()]}),
        "Monthly": df.groupby("year_month", as_index=False).agg(revenue=("revenue", "sum"), orders=("order_id", "nunique")),
        "Products": df.groupby(["category", "product"], as_index=False).agg(units=("quantity", "sum"), revenue=("revenue", "sum")).sort_values("revenue", ascending=False),
        "Regions": df.groupby("region", as_index=False).agg(revenue=("revenue", "sum"), customers=("customer_id", "nunique")).sort_values("revenue", ascending=False),
        "Customers_RFM": rfm,
        "Sales_Detail": df,
    })


def _m(x: float) -> str:
    return f"${x:,.0f}"


def write_reports() -> None:
    df = load_sales()
    rfm = compute_rfm(df)
    monthly = read_sql("SELECT * FROM vw_monthly_revenue ORDER BY year_month")
    cat_year = read_sql("SELECT * FROM vw_category_yearly ORDER BY category, year")
    prod = read_sql("SELECT * FROM vw_product_performance ORDER BY overall_rank")
    att = wrangling.integrate_targets(df)

    total = df["revenue"].sum()
    yrs = df.groupby("year")["revenue"].sum()
    growth = (yrs.iloc[-1] / yrs.iloc[0] - 1) * 100
    orders = df["order_id"].nunique()
    reg = df.groupby("region")["revenue"].sum().sort_values(ascending=False)
    seg = (rfm.groupby("segment").agg(customers=("customer_id", "count"), revenue=("monetary", "sum"))
              .reindex(["Champions", "Loyal", "Needs Attention", "At Risk (high value)", "Hibernating"]))
    seg["share"] = seg["revenue"] / seg["revenue"].sum() * 100
    cy = cat_year[cat_year["year"] == cat_year["year"].max()].sort_values("yoy_growth_pct")
    best_m, worst_m = monthly.loc[monthly["revenue"].idxmax()], monthly.loc[monthly["revenue"].idxmin()]
    q4 = df[df["quarter"] == 4]["revenue"].sum() / total * 100
    cust = df.groupby("customer_id")["revenue"].sum().sort_values(ascending=False)
    top10 = cust.head(max(1, round(len(cust) * 0.1))).sum() / cust.sum() * 100
    att_avg = att.groupby("region")["attainment_pct"].mean().round(1).sort_values()

    L = ["# Executive Sales Report - Business Intelligence Dashboard", "",
         f"**Data source:** PostgreSQL database `salesdb` (views `vw_sales_detail`, `vw_monthly_revenue`, "
         f"`vw_product_performance`, `vw_category_yearly`)  ",
         f"**Period:** {df['order_date'].min():%d %b %Y} - {df['order_date'].max():%d %b %Y}", "",
         "## 1. Headline KPIs", "", "| KPI | Value | How it is defined |", "|---|---|---|",
         f"| Total revenue | {_m(total)} | SUM of line revenue (quantity x price x (1 - discount)) |",
         f"| Orders | {orders:,} | Distinct order_id |",
         f"| Customers | {df['customer_id'].nunique():,} | Distinct customer_id |",
         f"| Average order value | {_m(total / orders)} | Revenue / orders |",
         f"| Units sold | {int(df['quantity'].sum()):,} | SUM of quantity |",
         f"| Revenue growth {yrs.index[0]} to {yrs.index[-1]} | {growth:+.1f}% | Year-over-year change |", "",
         "## 2. Revenue analysis", "",
         f"- Best month: **{best_m['year_month']}** ({_m(best_m['revenue'])}); weakest: **{worst_m['year_month']}** ({_m(worst_m['revenue'])}).",
         f"- Q4 contributes **{q4:.1f}%** of revenue: clear holiday-season seasonality.", "",
         "| Category | Revenue (last year) | YoY growth |", "|---|---|---|"]
    L += [f"| {r['category']} | {_m(r['revenue'])} | {r['yoy_growth_pct']:+.1f}% |" for _, r in cy.iterrows()]
    L += ["", "## 3. Product performance", "", "| Rank | Product | Category | Revenue | Share |", "|---|---|---|---|---|"]
    L += [f"| {int(r['overall_rank'])} | {r['product']} | {r['category']} | {_m(r['revenue'])} | {r['revenue_share_pct']:.1f}% |"
          for _, r in prod.head(5).iterrows()]
    L += ["", "## 4. Customer analytics (RFM segmentation)", "",
          f"The top 10% of customers generate **{top10:.1f}%** of revenue.", "",
          "| Segment | Customers | Revenue | Share of revenue |", "|---|---|---|---|"]
    L += [f"| {s} | {int(r['customers'])} | {_m(r['revenue'])} | {r['share']:.1f}% |" for s, r in seg.iterrows()]
    L += ["", "## 5. Regional analysis", "", "| Region | Revenue | Share | Avg monthly target attainment* |", "|---|---|---|---|"]
    L += [f"| {r} | {_m(v)} | {v / total * 100:.1f}% | {att_avg[r]:.0f}% |" for r, v in reg.items()]
    L += ["", "*Targets are illustrative assumptions defined in `scripts/wrangling.py` (stand-in for an external targets file).", "",
          "## 6. Recommendations", "",
          f"1. **Protect the core:** {prod.iloc[0]['product']} and {prod.iloc[1]['product']} lead revenue; guarantee stock before Q4.",
          f"2. **Retain high-value customers:** {int(seg.loc['At Risk (high value)', 'customers'])} high-value customers have gone quiet; run a win-back campaign "
          f"({_m(seg.loc['At Risk (high value)', 'revenue'])} historic revenue).",
          f"3. **Reward Champions:** {int(seg.loc['Champions', 'customers'])} customers deliver {seg.loc['Champions', 'share']:.0f}% of revenue; launch a loyalty programme.",
          f"4. **Fix the weakest region:** {reg.index[-1]} is last in revenue; investigate coverage and stock.",
          f"5. **Review {cy.iloc[0]['category']}:** slowest YoY growth ({cy.iloc[0]['yoy_growth_pct']:+.1f}%).",
          "6. **Plan around seasonality:** build campaigns for Jan-Feb to soften the post-holiday drop.", ""]
    (REPORT_DIR / "executive_report.md").write_text("\n".join(L), encoding="utf-8")
    (REPORT_DIR / "sales_report.xlsx").write_bytes(dashboard_workbook(df, rfm))
    print(f"Reports saved to {REPORT_DIR}")


if __name__ == "__main__":
    write_reports()
