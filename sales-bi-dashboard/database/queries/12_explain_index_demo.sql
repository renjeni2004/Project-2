-- 12 | Query optimisation: read the execution plan with EXPLAIN ANALYZE
-- Look for "Index Scan" (fast, uses idx_orders_customer) instead of "Seq Scan" (reads the whole table).
EXPLAIN ANALYZE
SELECT o.order_id, o.order_date, oi.line_revenue
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
WHERE  o.customer_id = 'CUST-1269';
