-- 06 | Window functions: running total, share of year, ranking inside each year
-- Question: How does revenue accumulate through each year, and which months rank highest within their year?
WITH monthly AS (
    SELECT year, month, SUM(revenue) AS revenue
    FROM   vw_sales_detail
    GROUP  BY year, month
)
SELECT year, month,
       ROUND(revenue, 2)                                                  AS revenue,
       ROUND(SUM(revenue) OVER (PARTITION BY year ORDER BY month), 2)     AS running_total,
       ROUND(revenue * 100.0 / SUM(revenue) OVER (PARTITION BY year), 1)  AS pct_of_year,
       RANK() OVER (PARTITION BY year ORDER BY revenue DESC)              AS rank_in_year
FROM   monthly
ORDER  BY year, month;
