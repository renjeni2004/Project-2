"""Run the whole data pipeline:  python scripts/run_pipeline.py

    1. load_database  -> create PostgreSQL schema, load data, create views
    2. features       -> engineered feature table + RFM table (CSV + SQL tables)
    3. report         -> executive_report.md + sales_report.xlsx
    4. make_charts    -> PNG charts + dashboard_preview.html
Then start the dashboard:  streamlit run dashboard/app.py
"""
import features
import load_database
import make_charts
import report


def main() -> None:
    print("=== 1/4 Load PostgreSQL ===");     load_database.main()
    print("\n=== 2/4 Feature engineering ==="); features.build_and_save()
    print("\n=== 3/4 Reports ===");           report.write_reports()
    print("\n=== 4/4 Charts ===");            make_charts.main()
    print("\nDone. Next: streamlit run dashboard/app.py")


if __name__ == "__main__":
    main()
