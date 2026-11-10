# Step-by-Step Guide: Building the Retail Sales Analysis Project

Follow these steps in order. Each step maps to Steps 1-12 of the task brief.

## Step 1 - Install Python, VS Code and Jupyter
1. Install Python 3.11+ from python.org (tick **Add Python to PATH**). Check: `python --version`
2. Install Visual Studio Code, then the extensions: Python, Pylance, Jupyter.
3. Install Git from git-scm.com. Check: `git --version`

## Step 2 - Create the project and install libraries
```bash
mkdir Data-Science-Internship && cd Data-Science-Internship
# copy this project's retail-sales-analysis/ folder here
cd retail-sales-analysis
python -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Step 3 - Learn Python fundamentals (Part A)
Open `notebooks/00_python_math_stats_numpy_foundations.ipynb`. Run every cell: variables, data
structures, loops, functions, exceptions, file handling, OOP. Then **modify** examples (change prices,
add a new method to `Product`) - typing code yourself is what builds the skill.

## Step 4 - Practise Maths, Statistics and NumPy (Parts B, C, D)
Same notebook, sections B-D. Exercise: compute the mean/median/std of your own list, build a 3x4
array, and prove NumPy is faster than a Python loop.

## Step 5 - Learn Pandas (Part E)
Read `scripts/analysis.py`. Every function uses `groupby`, `pivot_table`, `sort_values`, `agg`.
Practise: filter `df[df.region == "East"]`, merge two tables with `pd.merge`, build a pivot table.

## Step 6 - Import CSV and Excel (Parts F)
`scripts/clean_data.py -> load_raw()` reads `.csv` with `pd.read_csv` and `.xlsx` with `pd.read_excel`.
Generate the data: `python scripts/generate_dataset.py` (creates both files in `datasets/raw/`).

## Step 7 - Clean the dataset (Part G)
Run `python scripts/clean_data.py`. Read `reports/data_quality_report.md`. Always follow this order:
1. Inspect (`info()`, `isna().sum()`, `duplicated().sum()`)  2. Fix types and text
3. Remove duplicates  4. Handle outliers  5. Handle missing values  6. Re-validate (0 missing).

## Step 8 - Exploratory Data Analysis (Part H)
Open `notebooks/01_retail_sales_cleaning_and_eda.ipynb` and run it top to bottom. It covers descriptive
stats, distributions, correlations, trends, and business questions.

## Step 9 - Visualizations (Part I)
`python scripts/main.py --step analyse` creates 11 PNG charts in `visualizations/`
(line, bar, pie, histogram, scatter, box plot, heatmaps). Rule: every chart must answer a question.

## Step 10 - Business insights
Read `reports/business_report.md`. In your own words, explain *why* each number matters and what
action the business should take. Add your own observations to the notebook's insights section.

## Step 11 - Build the mini project (Part J)
`python scripts/main.py` runs everything. Open `dashboard/dashboard.html`: hover, zoom, use the region
dropdown and range slider. For live filters run `streamlit run scripts/streamlit_app.py`.
Take **screenshots** of the dashboard and save them in `dashboard/`.

## Step 12 - Upload to GitHub
```bash
cd retail-sales-analysis
git init
git add .
git commit -m "Initial commit: retail sales analysis project"
# create an empty repo on github.com (no README), then:
git branch -M main
git remote add origin https://github.com/<your-username>/retail-sales-analysis.git
git push -u origin main
```
Make several meaningful commits (the brief asks for commit history), e.g.:
`git commit -m "Add data cleaning pipeline"`, `"Add EDA notebook"`, `"Add dashboard"`, `"Update README with insights"`.

---
## Interview preparation: answers for the project questions
- **Data cleaning process?** Inspect -> fix types/text -> drop duplicates -> remove invalid outliers -> impute missing -> recompute revenue -> validate.
- **Missing values?** Region/name from the same customer's history (domain logic), quantity by product median (robust to outliers), rows lacking date/price dropped because they cannot be recovered.
- **Why Pandas over pure Python?** Vectorised, far less code, built-in groupby/pivot/IO, much faster on large data.
- **Most useful visualization?** Region x category heatmap and the monthly/YoY trend: they show where and when revenue comes from.
- **Trends and outliers?** Monthly and YoY lines for seasonality; boxplots and the 1.5 x IQR rule for outliers.
- **Project structure?** Raw data separate from cleaned data; scripts for reusable logic; notebooks for exploration; reports and visualizations as outputs.
