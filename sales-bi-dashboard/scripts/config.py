"""Project paths. Database credentials come from the environment (.env), never from code."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_CSV = ROOT / "datasets" / "source" / "retail_sales_clean.csv"
PROCESSED_DIR = ROOT / "datasets" / "processed"
SQL_DIR = ROOT / "database"
QUERY_DIR = SQL_DIR / "queries"
VIZ_DIR = ROOT / "visualizations"
REPORT_DIR = ROOT / "reports"
DASH_DIR = ROOT / "dashboard"

for _d in (PROCESSED_DIR, VIZ_DIR, REPORT_DIR, DASH_DIR):
    _d.mkdir(parents=True, exist_ok=True)
