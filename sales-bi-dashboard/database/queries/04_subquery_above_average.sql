-- 04 | Subqueries
-- Question: Which customers spend more than the average customer? (scalar subquery in HAVING)
SELECT customer_id, customer_name, region, orders, ROUND(revenue, 2) AS revenue
FROM   vw_customer_summary
WHERE  revenue > (SELECT AVG(revenue) FROM vw_customer_summary)
ORDER  BY revenue DESC
LIMIT  15;
