"""Advanced Pandas & data wrangling techniques (Part E + F).

Every function takes the flat sales DataFrame (from the SQL view vw_sales_detail)
and demonstrates ONE technique so you can read, run and modify it on its own.
"""
import numpy as np
import pandas as pd

# Assumed monthly revenue targets per region (stand-in for an external business file).
# Used to demonstrate DATA INTEGRATION: merging internal sales with an outside source.
REGIONAL_MONTHLY_TARGET = {"East": 24_000, "South": 12_500, "West": 12_500,
                           "North": 10_500, "Central": 6_000}


def multiindex_summary(df: pd.DataFrame) -> pd.DataFrame:
    """MultiIndex rows (region, category) x multiple aggregations."""
    return (df.groupby(["region", "category"])
              .agg(revenue=("revenue", "sum"), orders=("order_id", "nunique"),
                   avg_discount=("discount", "mean"))
              .round(2))


def multiindex_pivot(df: pd.DataFrame) -> pd.DataFrame:
    """MultiIndex rows AND columns: (region, category) x year, with totals."""
    return df.pivot_table(index=["region", "category"], columns="year", values="revenue",
                          aggfunc="sum", margins=True, margins_name="TOTAL").round(0)


def region_payment_crosstab(df: pd.DataFrame) -> pd.DataFrame:
    """Share (%) of each region's revenue by payment method."""
    return (pd.crosstab(df["region"], df["payment_method"], values=df["revenue"],
                        aggfunc="sum", normalize="index") * 100).round(1)


def merge_customer_summary(df: pd.DataFrame) -> pd.DataFrame:
    """MERGE (SQL-style join): attach each customer's lifetime totals to every sale."""
    lifetime = (df.groupby("customer_id")
                  .agg(lifetime_revenue=("revenue", "sum"), lifetime_orders=("order_id", "nunique"))
                  .reset_index())
    merged = df.merge(lifetime, on="customer_id", how="left", validate="m:1")
    merged["pct_of_customer_lifetime"] = (merged["revenue"] / merged["lifetime_revenue"] * 100).round(2)
    return merged


def join_on_index(df: pd.DataFrame) -> pd.DataFrame:
    """JOIN on index: two DataFrames indexed by region, combined side by side."""
    rev = df.groupby("region")["revenue"].sum().rename("revenue").to_frame()
    cust = df.groupby("region")["customer_id"].nunique().rename("customers").to_frame()
    out = rev.join(cust)
    out["revenue_per_customer"] = (out["revenue"] / out["customers"]).round(0)
    return out.sort_values("revenue", ascending=False)


def concat_years(df: pd.DataFrame) -> pd.DataFrame:
    """CONCAT: split by year, then stack back with keys (creates a MultiIndex)."""
    parts = {y: g.groupby("category")["revenue"].sum() for y, g in df.groupby("year")}
    return pd.concat(parts, axis=1).round(0)          # axis=1 -> side by side


def apply_lambda_features(df: pd.DataFrame) -> pd.DataFrame:
    """APPLY + LAMBDA: row-wise and column-wise custom logic."""
    out = df[["order_id", "customer_name", "product", "quantity", "revenue"]].copy()
    out["order_size"] = out["revenue"].apply(
        lambda v: "Large" if v >= 1000 else "Medium" if v >= 250 else "Small")
    out["initials"] = out["customer_name"].apply(lambda n: "".join(w[0] for w in n.split()))
    out["revenue_per_unit"] = out.apply(lambda r: round(r["revenue"] / r["quantity"], 2), axis=1)
    return out


def window_operations(df: pd.DataFrame) -> pd.DataFrame:
    """Window operations: rolling, expanding, shift, pct_change, rank on a monthly series."""
    m = df.groupby("year_month", as_index=False)["revenue"].sum()
    m["rolling_3m_avg"] = m["revenue"].rolling(3).mean().round(0)
    m["expanding_total"] = m["revenue"].expanding().sum().round(0)
    m["prev_month"] = m["revenue"].shift(1)
    m["mom_growth_pct"] = (m["revenue"].pct_change() * 100).round(1)
    m["revenue_rank"] = m["revenue"].rank(ascending=False).astype(int)
    return m.round(0)


def reshape_wide_long(df: pd.DataFrame):
    """RESHAPING: long -> wide (pivot) -> long again (melt); stack / unstack."""
    wide = df.pivot_table(index="year_month", columns="category", values="revenue",
                          aggfunc="sum", fill_value=0).round(0)
    long = wide.reset_index().melt(id_vars="year_month", var_name="category", value_name="revenue")
    stacked = wide.stack()                            # Series with (month, category) MultiIndex
    return wide, long, stacked


def encode_categories(df: pd.DataFrame) -> pd.DataFrame:
    """ENCODING: one-hot (nominal) and ordinal mapping."""
    out = pd.get_dummies(df[["category", "region"]], prefix=["cat", "reg"], dtype=int)
    tier = pd.qcut(df["unit_price"], 4, labels=["Budget", "Standard", "Premium", "Luxury"])
    out["price_tier_ordinal"] = tier.map({"Budget": 0, "Standard": 1, "Premium": 2, "Luxury": 3}).astype(int)
    return out


def integrate_targets(df: pd.DataFrame) -> pd.DataFrame:
    """DATA INTEGRATION: merge actuals with an external targets table -> attainment %."""
    actual = df.groupby(["region", "year_month"], as_index=False)["revenue"].sum()
    targets = pd.DataFrame({"region": list(REGIONAL_MONTHLY_TARGET),
                            "monthly_target": list(REGIONAL_MONTHLY_TARGET.values())})
    out = actual.merge(targets, on="region", how="left")
    out["attainment_pct"] = (out["revenue"] / out["monthly_target"] * 100).round(1)
    return out
