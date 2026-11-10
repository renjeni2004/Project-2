# Task 2 - Step-by-Step Guide: BI Sales Analytics Dashboard

Follow the steps in order. They match Steps 1-12 of the task brief. Time estimate: 40-45 days of learning, 2-3 days to run and understand this project.

---
## Step 1 - Install PostgreSQL and pgAdmin 4
| OS | How |
|---|---|
| **Windows** | Download the installer from postgresql.org/download/windows. Keep pgAdmin 4 ticked. **Write down the `postgres` superuser password.** Keep port 5432. |
| **macOS** | Install Postgres.app, or `brew install postgresql@16 && brew services start postgresql@16`; get pgAdmin 4 from pgadmin.org |
| **Ubuntu/Linux** | `sudo apt install postgresql postgresql-contrib` then `sudo systemctl start postgresql`; pgAdmin from pgadmin.org |
| **Docker (any OS)** | `docker run --name salesdb -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16` |

Check: `psql --version` (or open pgAdmin and connect to "PostgreSQL 16").

## Step 2 - Create the relational database
Open pgAdmin -> Query Tool (or run `psql -U postgres`), then:
```sql
CREATE ROLE sales_user WITH LOGIN PASSWORD 'choose_a_strong_password' CREATEDB;
CREATE DATABASE salesdb OWNER sales_user;
```
Create the Python environment and the credentials file:
```bash
cd sales-bi-dashboard
python -m venv .venv && source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                                     # Windows: copy .env.example .env
```
Edit `.env`:
```
DATABASE_URL=postgresql+psycopg://sales_user:choose_a_strong_password@localhost:5432/salesdb
```
If your password contains `@ : / #` etc., URL-encode it (`@` becomes `%40`). **`.env` is git-ignored: never upload passwords to GitHub.**

Build the tables and load the data:
```bash
python scripts/load_database.py
```
Open pgAdmin -> Databases -> salesdb -> Schemas -> public -> Tables to see 6 tables. Read `database/schema.sql` line by line: it shows primary keys, foreign keys, CHECK constraints, a generated column and indexes.

## Step 3 - Practise SQL queries
1. Open `notebooks/01_sql_and_postgresql.ipynb` and run it top to bottom.
2. In pgAdmin's Query Tool, paste each file from `database/queries/` and run it. Read the comment on the first lines.
3. **Modify each query:** change the year, region or threshold. Predict the result before running it.
4. Practise further on SQLBolt, PostgreSQL Exercises (pgexercises.com), Mode SQL Tutorial, HackerRank SQL.

| Query file | Concept |
|---|---|
| 01 | SELECT, WHERE, ORDER BY, LIMIT |
| 02 | GROUP BY, HAVING, aggregates |
| 03 | INNER / LEFT JOIN across 6 tables |
| 04 | Subquery |
| 05 | CTE + LAG |
| 06 | Window functions: running total, RANK |
| 07 | Top-N per group |
| 08 | RFM with NTILE |
| 09 | Pareto with cumulative window |
| 10 | FILTER (conditional aggregation) |
| 11 | UNION ALL |
| 12 | EXPLAIN ANALYZE (optimisation) |

Also run `database/views.sql` objects: `SELECT * FROM vw_monthly_revenue;`

Optional: create the read-only dashboard user. In pgAdmin Query Tool connected as `postgres` to `salesdb`, run `database/roles.sql` **after** loading the data.

## Step 4 - Connect PostgreSQL with Python
Read `scripts/db.py`:
- `create_engine(DATABASE_URL)` builds the SQLAlchemy engine; `psycopg` is the driver underneath.
- `pd.read_sql` runs a query and returns a DataFrame.
- Values go in as **bound parameters** (`:name`), never into f-strings. This stops SQL injection (the notebook proves it).

## Step 5 - Load SQL data into Pandas
`scripts/features.py -> load_sales()` runs `SELECT * FROM vw_sales_detail`. Try in a notebook:
```python
import sys; sys.path.insert(0, "../scripts")
from features import load_sales
df = load_sales(); df.head()
```

## Step 6 - Data wrangling (Advanced Pandas)
Open `notebooks/02_advanced_pandas_wrangling.ipynb`. Each section runs one function from `scripts/wrangling.py`: MultiIndex, merge, join, concat, pivot, crosstab, apply/lambda, rolling windows, melt/stack, encoding, data integration. **Exercise:** add your own function, e.g. average order value per payment method per quarter.

## Step 7 - Feature engineering
Open `notebooks/03_feature_engineering_and_bi.ipynb`. Understand the five groups of features (date/time, maths, customer history, encoding, scaling) in `scripts/features.py`. Rule: **never use future information** (customer-history features only look at earlier rows). Output: `datasets/processed/sales_features.csv` and `customer_rfm.csv`.

## Step 8 - Interactive visualizations
`scripts/viz.py` holds 16 Plotly functions (Plotly Express and Graph Objects). Run `python scripts/make_charts.py` for PNG charts and `dashboard/dashboard_preview.html`.

## Step 9 - Streamlit dashboard
```bash
streamlit run dashboard/app.py
```
Use the sidebar filters and search; check that KPI cards change; open the SQL Explorer tab; click **Download Excel report**. Read `dashboard/app.py` top to bottom: connection check, cached SQL calls, filters, KPIs, 8 tabs.
Take screenshots of each tab for the README and your submission.

## Step 10 - Business reports
`python scripts/report.py` creates `reports/executive_report.md` and `reports/sales_report.xlsx`. Read the report, then write 5 sentences in your own words: what happened, why, and what the business should do.

## Step 11 - Upload to GitHub
```bash
cd sales-bi-dashboard
git init
git add .
git status                      # CHECK: .env must NOT appear in the list
git commit -m "Add PostgreSQL schema, views and SQL queries"
# make more commits as you go, for example:
#   "Add data loading and feature engineering"   "Add Streamlit dashboard"
#   "Add notebooks and reports"                  "Update README with screenshots"
git branch -M main
git remote add origin https://github.com/<your-username>/sales-bi-dashboard.git
git push -u origin main
```
If you ever commit a password by mistake, **change that password** immediately: deleting the file later does not remove it from history.

## Step 12 - Project documentation
Fill the screenshot placeholders in `README.md` and `documentation/TASK2_PROJECT_DOCUMENTATION.md`. Final check against the brief's submission checklist:
- [ ] PostgreSQL and pgAdmin installed, database `salesdb` created
- [ ] Python connected through SQLAlchemy (psycopg driver)
- [ ] SQL with joins, CTEs, window functions
- [ ] Advanced Pandas, wrangling and feature engineering
- [ ] Streamlit + Plotly dashboard, KPIs, filters, export
- [ ] Reports, notebooks, SQL scripts, database backup
- [ ] GitHub repo with meaningful commit history and a professional README

---
## Troubleshooting
| Error | Cause and fix |
|---|---|
| `DATABASE_URL is not set` | `.env` missing: copy `.env.example` to `.env` |
| `password authentication failed` | Wrong password in `.env`; test with `psql -U sales_user -d salesdb -h localhost` |
| `connection refused` / `could not connect` | PostgreSQL not running or wrong port (default 5432) |
| `database "salesdb" does not exist` | Run the `CREATE DATABASE` command from Step 2 |
| `permission denied for table ...` | Using `bi_readonly` before running `roles.sql`, or you loaded data as another user. Re-run `roles.sql` as `postgres` |
| `No module named psycopg` | `pip install "psycopg[binary]"` (inside the activated venv) |
| `relation "vw_sales_detail" does not exist` | Run `python scripts/load_database.py` |
| Streamlit shows old numbers | Data is cached for 10 minutes: press `C` in the app or restart it |
| `streamlit: command not found` | Activate the venv, or use `python -m streamlit run dashboard/app.py` |
| Password with `@` fails | URL-encode special characters in `DATABASE_URL` |

---
## Interview preparation: answers for the project questions
- **Dashboard architecture?** PostgreSQL stores normalised tables; views expose analysis-ready data; `bi_data.py` runs parameterised SQL with the user's filters; Pandas does the finishing aggregations; `viz.py` builds Plotly charts; Streamlit lays out tabs, filters and downloads. Results are cached for 10 minutes.
- **How did you connect PostgreSQL with Python?** SQLAlchemy `create_engine` with a `postgresql+psycopg://` URL read from `.env`; `pd.read_sql` for queries and `DataFrame.to_sql` for writing.
- **Why SQLAlchemy?** One consistent interface over drivers, connection pooling, bound parameters (injection-safe), easy to switch databases, and it integrates directly with Pandas.
- **How did you do feature engineering?** Date/time parts (including cyclical month sin/cos), maths features (gross, discount amount, log revenue), customer-history features using only past rows to avoid leakage, one-hot and label encoding, min-max and z-score scaling.
- **Which KPIs were most useful?** Revenue with growth vs the previous period, average order value, customer count, and RFM segment revenue share, because they point to actions (protect Champions, win back At-Risk customers).
- **How did the dashboard answer business questions?** Filters let a manager slice by time, region, category and payment method; each tab is built around one question (where does revenue come from, who are the best customers, which products drive sales, what is the seasonal pattern).
- **Primary vs foreign key?** A primary key uniquely identifies a row; a foreign key references another table's primary key and enforces valid relationships.
- **INNER vs LEFT JOIN?** INNER keeps matching rows only; LEFT keeps all rows from the left table, with NULLs where there is no match.
- **WHERE vs HAVING?** WHERE filters rows before grouping; HAVING filters groups after aggregation.
- **Window function vs GROUP BY?** GROUP BY collapses rows; a window function (`SUM() OVER`, `RANK() OVER`) keeps every row and adds a calculation across related rows.
- **What is an index and when does it help?** A data structure that speeds up lookups and joins on a column. In the notebook, indexing `orders.customer_id` changed a Seq Scan (0.58 ms) into an Index Scan (0.09 ms).

## Mapping to the 45-day plan
| Days | Topic | Where in this project |
|---|---|---|
| 1-6 | SQL fundamentals | queries 01-02, notebook 01 |
| 7-12 | Advanced SQL and PostgreSQL | queries 03-12, `schema.sql`, `views.sql`, `backup_restore.md` |
| 13-17 | SQLAlchemy, connectivity | `db.py`, `load_database.py` |
| 18-24 | Advanced Pandas | `wrangling.py`, notebook 02 |
| 25-30 | Wrangling, feature engineering | `features.py`, notebook 03 |
| 31-36 | Plotly | `viz.py`, `make_charts.py` |
| 37-42 | Streamlit | `dashboard/app.py` |
| 43-45 | BI project, GitHub, docs | `report.py`, README, this guide |
