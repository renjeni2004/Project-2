-- 05 | CTE + LAG window function
-- Question: Which months grew the most vs the previous month, and which fell the most?
WITH monthly AS (
    SELECT year_month, SUM(revenue) AS revenue
    FROM   vw_sales_detail
    GROUP  BY year_month
), growth AS (
    SELECT year_month,
           ROUND(revenue, 2) AS revenue,
           ROUND((revenue / LAG(revenue) OVER (ORDER BY year_month) - 1) * 100, 1) AS mom_growth_pct
    FROM   monthly
)
SELECT *
FROM   growth
WHERE  mom_growth_pct IS NOT NULL
ORDER  BY mom_growth_pct DESC;
