-- 09 | Cumulative share (Pareto / 80-20 analysis) with window functions
-- Question: How many customers does it take to reach 50% of revenue?
WITH ranked AS (
    SELECT customer_id, customer_name, revenue,
           ROW_NUMBER() OVER (ORDER BY revenue DESC)                              AS rnk,
           SUM(revenue) OVER (ORDER BY revenue DESC)                              AS cum_revenue,
           SUM(revenue) OVER ()                                                   AS total_revenue
    FROM   vw_customer_summary
)
SELECT rnk, customer_name,
       ROUND(revenue, 2)                                 AS revenue,
       ROUND(cum_revenue * 100.0 / total_revenue, 1)     AS cumulative_pct
FROM   ranked
WHERE  cum_revenue * 1.0 / total_revenue <= 0.5
ORDER  BY rnk;
