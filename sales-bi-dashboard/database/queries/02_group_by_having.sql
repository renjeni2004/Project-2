-- 02 | GROUP BY + HAVING + aggregate functions
-- Question: Which product categories have more than $100,000 in revenue, and what is their average order-line value?
SELECT category,
       COUNT(*)                    AS order_lines,
       SUM(quantity)               AS units_sold,
       ROUND(SUM(revenue), 2)      AS total_revenue,
       ROUND(AVG(revenue), 2)      AS avg_line_value
FROM   vw_sales_detail
GROUP  BY category
HAVING SUM(revenue) > 100000
ORDER  BY total_revenue DESC;
