-- 11 | UNION ALL: combine result sets of different entities
-- Question: A single leaderboard of the top 3 regions, top 3 categories and top 3 products.
(SELECT 'Region' AS entity, region AS name, ROUND(SUM(revenue), 2) AS revenue
 FROM vw_sales_detail GROUP BY region ORDER BY revenue DESC LIMIT 3)
UNION ALL
(SELECT 'Category', category, ROUND(SUM(revenue), 2)
 FROM vw_sales_detail GROUP BY category ORDER BY 3 DESC LIMIT 3)
UNION ALL
(SELECT 'Product', product, ROUND(SUM(revenue), 2)
 FROM vw_sales_detail GROUP BY product ORDER BY 3 DESC LIMIT 3);
