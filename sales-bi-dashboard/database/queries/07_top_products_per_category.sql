-- 07 | ROW_NUMBER() with PARTITION BY: "top N per group"
-- Question: What are the top 2 products in every category?
SELECT category, product, ROUND(revenue, 2) AS revenue, category_rank
FROM   vw_product_performance
WHERE  category_rank <= 2
ORDER  BY category, category_rank;
