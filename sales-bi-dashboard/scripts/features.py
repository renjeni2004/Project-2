"""Feature engineering (Part G) + RFM customer segmentation (Part I).

Output tables are the input for machine learning in Task 3:
    datasets/processed/sales_features.csv  - one row per order line
    datasets/processed/customer_rfm.csv    - one row per customer
Both are also written back to PostgreSQL (ml_sales_features, customer_rfm).
"""
import numpy as np
import pandas as pd

from config import PROCESSED_DIR
from db import get_engine, read_sql

SEGMENT_ORDER = ["Champions", "Loyal", "Needs Attention", "At Risk (high value)", "Hibernating"]
NUMERIC_TO_SCALE = ["quantity", "unit_price", "discount", "revenue"]


def load_sales(engine=None) -> pd.DataFrame:
    return read_sql("SELECT * FROM vw_sales_detail ORDER BY order_date, item_id", engine=engine)


# ------------------------------------------------------------------ RFM
def _score(series: pd.Series, ascending: bool) -> pd.Series:
    """Quintile score 1-5 (ranking first avoids duplicate bin edges)."""
    if len(series) < 5:
        return pd.Series(3, index=series.index)
    return pd.qcut(series.rank(method="first", ascending=ascending), 5, labels=[1, 2, 3, 4, 5]).astype(int)


def _segment(r: int, fm: float) -> str:
    if r >= 4 and fm >= 4:
        return "Champions"
    if r >= 3 and fm >= 3:
        return "Loyal"
    if r <= 2 and fm >= 4:
        return "At Risk (high value)"
    if r <= 2 and fm <= 2:
        return "Hibernating"
    return "Needs Attention"


def compute_rfm(df: pd.DataFrame) -> pd.DataFrame:
    """Recency / Frequency / Monetary table with 1-5 scores and a named segment."""
    snapshot = df["order_date"].max() + pd.Timedelta(days=1)
    rfm = (df.groupby(["customer_id", "customer_name", "region"], as_index=False)
             .agg(last_order=("order_date", "max"), frequency=("order_id", "nunique"),
                  monetary=("revenue", "sum")))
    rfm["recency_days"] = (snapshot - rfm["last_order"]).dt.days
    rfm["r_score"] = _score(rfm["recency_days"], ascending=False)   # fewer days = better
    rfm["f_score"] = _score(rfm["frequency"], ascending=True)
    rfm["m_score"] = _score(rfm["monetary"], ascending=True)
    rfm["rfm_score"] = rfm["r_score"] * 100 + rfm["f_score"] * 10 + rfm["m_score"]
    fm = (rfm["f_score"] + rfm["m_score"]) / 2
    rfm["segment"] = [_segment(r, f) for r, f in zip(rfm["r_score"], fm)]
    rfm["monetary"] = rfm["monetary"].round(2)
    return rfm.sort_values("monetary", ascending=False).reset_index(drop=True)


# ------------------------------------------------------- line-level features
def engineer_sales_features(df: pd.DataFrame) -> pd.DataFrame:
    """Create date, time, maths, customer-history, encoded and scaled features."""
    df = df.sort_values(["order_date", "item_id"]).reset_index(drop=True).copy()
    d = df["order_date"]

    # 1. Date / time features
    df["week_of_year"] = d.dt.isocalendar().week.astype(int)
    df["day_of_month"] = d.dt.day
    df["is_weekend"] = (df["iso_weekday"] >= 6).astype(int)
    df["is_month_end"] = d.dt.is_month_end.astype(int)
    df["is_holiday_season"] = df["month"].isin([11, 12]).astype(int)
    df["month_sin"] = np.sin(2 * np.pi * df["month"] / 12).round(4)   # cyclical encoding:
    df["month_cos"] = np.cos(2 * np.pi * df["month"] / 12).round(4)   # Dec is next to Jan
    df["days_since_start"] = (d - d.min()).dt.days

    # 2. Mathematical features
    df["gross_amount"] = (df["quantity"] * df["unit_price"]).round(2)
    df["discount_amount"] = (df["gross_amount"] - df["revenue"]).round(2)
    df["log_revenue"] = np.log1p(df["revenue"]).round(4)
    df["price_tier"] = pd.qcut(df["unit_price"], 4, labels=["Budget", "Standard", "Premium", "Luxury"]).astype(str)
    df["is_bulk_order"] = (df["quantity"] >= 5).astype(int)

    # 3. Customer-history features (use only PAST rows -> no data leakage)
    df = df.sort_values(["customer_id", "order_date", "item_id"]).reset_index(drop=True)
    g = df.groupby("customer_id")
    df["customer_purchase_seq"] = g.cumcount() + 1
    df["days_since_prev_purchase"] = g["order_date"].diff().dt.days.fillna(0).astype(int)
    df["customer_revenue_before"] = (g["revenue"].cumsum() - df["revenue"]).round(2)
    df["prev3_avg_revenue"] = (g["revenue"].transform(lambda s: s.shift(1).rolling(3, min_periods=1).mean())
                               .fillna(0).round(2))

    # 4. Categorical encoding
    df["product_code"] = df["product"].astype("category").cat.codes          # label encoding
    df = pd.concat([df, pd.get_dummies(df[["category", "region", "payment_method"]],
                                       prefix=["cat", "reg", "pay"], dtype=int)], axis=1)  # one-hot

    # 5. Feature scaling (introduction): min-max and z-score
    for col in NUMERIC_TO_SCALE:
        lo, hi = df[col].min(), df[col].max()
        df[f"{col}_minmax"] = ((df[col] - lo) / (hi - lo)).round(4)
        df[f"{col}_z"] = ((df[col] - df[col].mean()) / df[col].std()).round(4)

    return df.sort_values(["order_date", "item_id"]).reset_index(drop=True)


def build_and_save(engine=None) -> tuple[pd.DataFrame, pd.DataFrame]:
    engine = engine or get_engine()
    sales = load_sales(engine)
    feats = engineer_sales_features(sales)
    rfm = compute_rfm(sales)

    feats.to_csv(PROCESSED_DIR / "sales_features.csv", index=False)
    rfm.to_csv(PROCESSED_DIR / "customer_rfm.csv", index=False)
    feats.to_sql("ml_sales_features", engine, if_exists="replace", index=False, method="multi", chunksize=1000)
    rfm.to_sql("customer_rfm", engine, if_exists="replace", index=False)
    print(f"Feature table: {feats.shape[0]:,} rows x {feats.shape[1]} columns")
    print(f"RFM table: {len(rfm)} customers | segments: {rfm['segment'].value_counts().to_dict()}")
    return feats, rfm


if __name__ == "__main__":
    build_and_save()
