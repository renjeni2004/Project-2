"""Build the PostgreSQL database from the Task 1 cleaned CSV.

Steps: create schema -> load dimensions -> load orders -> load order items -> create views
       -> ANALYZE -> reconcile totals against the source file.
Usage:  python scripts/load_database.py
"""
import pandas as pd

from config import SOURCE_CSV, SQL_DIR
from db import get_engine, run_sql_file


def build_tables(src: pd.DataFrame) -> dict[str, pd.DataFrame]:
    """Normalise the flat sales file into relational tables."""
    regions = (pd.DataFrame({"region_name": sorted(src["region"].unique())})
               .rename_axis("region_id").reset_index())
    regions["region_id"] += 1

    categories = (pd.DataFrame({"category_name": sorted(src["category"].unique())})
                  .rename_axis("category_id").reset_index())
    categories["category_id"] += 1

    customers = (src.groupby("customer_id", as_index=False)
                    .agg(customer_name=("customer_name", "first"), region=("region", "first"))
                    .merge(regions, left_on="region", right_on="region_name")
                    [["customer_id", "customer_name", "region_id"]])

    products = (src.groupby(["product", "category"], as_index=False)
                   .agg(list_price=("unit_price", "median")).round({"list_price": 2})
                   .merge(categories, left_on="category", right_on="category_name")
                   .sort_values("product").reset_index(drop=True))
    products["product_id"] = products.index + 1
    products = products.rename(columns={"product": "product_name"})[
        ["product_id", "product_name", "category_id", "list_price"]]

    # An order = all lines bought by one customer on one day with one payment method
    keys = ["customer_id", "order_date", "payment_method"]
    src = src.sort_values(keys + ["order_id"]).copy()
    src["order_key"] = src.groupby(keys, sort=False).ngroup() + 50001
    orders = (src.groupby("order_key", as_index=False)
                 .agg(order_date=("order_date", "first"), customer_id=("customer_id", "first"),
                      payment_method=("payment_method", "first"))
                 .rename(columns={"order_key": "order_id"}))

    items = (src.merge(products[["product_id", "product_name"]],
                       left_on="product", right_on="product_name")
                .sort_values("order_id").reset_index(drop=True))
    items["item_id"] = items.index + 1
    items = items.rename(columns={"order_id": "source_line_id", "order_key": "order_id"})[
        ["item_id", "order_id", "product_id", "quantity", "unit_price", "discount", "source_line_id"]]

    return {"regions": regions, "categories": categories, "customers": customers,
            "products": products, "orders": orders, "order_items": items}


def main() -> None:
    engine = get_engine()
    src = pd.read_csv(SOURCE_CSV, parse_dates=["order_date"])
    print(f"Source file: {len(src):,} rows, revenue ${src['revenue'].sum():,.2f}")

    run_sql_file(SQL_DIR / "schema.sql", engine)
    print("Schema created (6 tables, constraints, indexes)")

    tables = build_tables(src)
    for name in ["regions", "categories", "customers", "products", "orders", "order_items"]:
        tables[name].to_sql(name, engine, if_exists="append", index=False,
                            method="multi", chunksize=1000)
        print(f"  loaded {name:12s} {len(tables[name]):>6,} rows")

    run_sql_file(SQL_DIR / "views.sql", engine)
    with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
        conn.exec_driver_sql("ANALYZE")
    print("Views created, statistics updated (ANALYZE)")

    # Reconciliation: the database must match the source exactly
    db_total = pd.read_sql("SELECT SUM(line_revenue) AS t FROM order_items", engine)["t"][0]
    diff = abs(float(db_total) - src["revenue"].sum())
    print(f"Database revenue ${float(db_total):,.2f} | difference vs source: ${diff:,.2f}")
    assert diff < 1.0, "Revenue mismatch between database and source file!"
    print("OK: database loaded and reconciled")


if __name__ == "__main__":
    main()
