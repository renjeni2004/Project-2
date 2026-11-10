-- 03 | INNER JOIN, LEFT JOIN across the schema (not the view, to show the joins explicitly)
-- Question: Revenue per region and category, plus products that have never been sold (LEFT JOIN + IS NULL).
SELECT r.region_name,
       cat.category_name,
       COUNT(oi.item_id)              AS order_lines,
       ROUND(SUM(oi.line_revenue), 2) AS revenue
FROM   order_items oi
INNER JOIN orders     o   ON o.order_id      = oi.order_id
INNER JOIN customers  c   ON c.customer_id   = o.customer_id
INNER JOIN regions    r   ON r.region_id     = c.region_id
INNER JOIN products   p   ON p.product_id    = oi.product_id
INNER JOIN categories cat ON cat.category_id = p.category_id
GROUP  BY r.region_name, cat.category_name
ORDER  BY r.region_name, revenue DESC;

-- Products that have never been sold (empty result = every product sells)
-- SELECT p.product_name
-- FROM   products p
-- LEFT JOIN order_items oi ON oi.product_id = p.product_id
-- WHERE  oi.item_id IS NULL;
