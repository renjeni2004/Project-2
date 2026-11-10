-- 10 | Conditional aggregation with FILTER (pivot in SQL)
-- Question: Revenue per category for 2024 vs 2025 and the growth between them.
SELECT category,
       ROUND(SUM(revenue) FILTER (WHERE year = 2024), 2) AS revenue_2024,
       ROUND(SUM(revenue) FILTER (WHERE year = 2025), 2) AS revenue_2025,
       ROUND((SUM(revenue) FILTER (WHERE year = 2025) /
              SUM(revenue) FILTER (WHERE year = 2024) - 1) * 100, 1) AS growth_pct
FROM   vw_sales_detail
GROUP  BY category
ORDER  BY growth_pct;
