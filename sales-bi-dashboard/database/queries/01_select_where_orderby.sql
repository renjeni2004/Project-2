-- 01 | SELECT, WHERE, ORDER BY, LIMIT
-- Question: What are the 10 biggest single order lines in the East region in 2025?
SELECT order_id, order_date, customer_name, product, quantity, revenue
FROM   vw_sales_detail
WHERE  region = 'East'
  AND  year   = 2025
ORDER  BY revenue DESC
LIMIT  10;
