-- 08 | RFM customer segmentation in pure SQL (CTE + NTILE)
-- Recency = days since last order, Frequency = number of orders, Monetary = total revenue.
-- NTILE(5) splits customers into 5 equal groups; 5 = best.
WITH snapshot AS (
    SELECT MAX(order_date) + 1 AS snap FROM orders
), rfm AS (
    SELECT cs.customer_id, cs.customer_name, cs.region,
           (s.snap - cs.last_order) AS recency_days,
           cs.orders                AS frequency,
           cs.revenue               AS monetary
    FROM   vw_customer_summary cs CROSS JOIN snapshot s
    WHERE  cs.orders > 0
), scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- fewer days = higher score
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM rfm
)
SELECT customer_id, customer_name, recency_days, frequency, ROUND(monetary, 2) AS monetary,
       r_score, f_score, m_score,
       CASE WHEN r_score >= 4 AND (f_score + m_score) / 2.0 >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND (f_score + m_score) / 2.0 >= 3 THEN 'Loyal'
            WHEN r_score <= 2 AND (f_score + m_score) / 2.0 >= 4 THEN 'At Risk (high value)'
            WHEN r_score <= 2 AND (f_score + m_score) / 2.0 <= 2 THEN 'Hibernating'
            ELSE 'Needs Attention' END AS segment
FROM   scored
ORDER  BY monetary DESC
LIMIT  25;
