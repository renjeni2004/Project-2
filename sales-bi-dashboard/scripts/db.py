"""Database connectivity helpers (SQLAlchemy + psycopg 3)."""
import os
from datetime import date
from functools import lru_cache
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import bindparam, create_engine, text
from sqlalchemy.engine import Engine

from config import QUERY_DIR, ROOT

load_dotenv(ROOT / ".env")


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    """Create one shared engine from the DATABASE_URL environment variable."""
    url = os.getenv("DATABASE_URL")
    if not url:
        raise RuntimeError(
            "DATABASE_URL is not set. Copy .env.example to .env and fill in your PostgreSQL "
            "credentials (see documentation/TASK2_STEP_BY_STEP_GUIDE.md, Step 2).")
    return create_engine(url, pool_pre_ping=True)


def run_sql_file(path: Path, engine: Engine | None = None) -> None:
    """Execute a whole .sql script (schema, views...) in one transaction."""
    engine = engine or get_engine()
    with engine.begin() as conn:
        conn.exec_driver_sql(Path(path).read_text(encoding="utf-8"))


def read_sql(sql: str, params: dict | None = None, engine: Engine | None = None) -> pd.DataFrame:
    """Run a SELECT and return a DataFrame. Always pass user values via `params`."""
    engine = engine or get_engine()
    stmt = text(sql)
    for key, value in (params or {}).items():   # list values -> "IN (...)" lists
        if isinstance(value, (list, tuple)):
            stmt = stmt.bindparams(bindparam(key, expanding=True))
    df = pd.read_sql(stmt, engine, params=params)
    for col in df.columns:                      # PostgreSQL DATE -> pandas datetime
        if df[col].dtype == object and len(df) and isinstance(df[col].iloc[0], date):
            df[col] = pd.to_datetime(df[col])
    return df


def load_query(name: str) -> str:
    """Read a saved query from database/queries/<name>.sql"""
    return (QUERY_DIR / f"{name}.sql").read_text(encoding="utf-8")


def list_queries() -> list[str]:
    return sorted(p.stem for p in QUERY_DIR.glob("*.sql"))


def run_query(name: str, engine: Engine | None = None) -> pd.DataFrame:
    return read_sql(load_query(name), engine=engine)
