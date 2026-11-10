-- =====================================================================
-- Reporting views: reusable, named queries the dashboard reads from.
-- =====================================================================
DROP VIEW IF EXISTS vw_category_yearly     CASCADE;
DROP VIEW IF EXISTS vw_product_performance CASCADE;
DROP VIEW IF EXISTS vw_customer_summary    CASCADE;
DROP VIEW IF EXISTS vw_monthly_revenue     CASCADE;
DROP VIEW IF EXISTS vw_sales_detail        CASCADE;

-- One row per order line with every dimension joined in (the "flat" analytics table)
CREATE VIEW vw_sales_detail AS
SELECT oi.item_id,
       o.order_id,
       o.order_date,
       EXTRACT(YEAR    FROM o.order_date)::int AS year,
       EXTRACT(QUARTER FROM o.order_date)::int AS quarter,
       EXTRACT(MONTH   FROM o.order_date)::int AS month,
       EXTRACT(ISODOW  FROM o.order_date)::int AS iso_weekday,
       TO_CHAR(o.order_date, 'YYYY-MM')        AS year_month,
       c.customer_id,
       c.customer_name,
       r.region_name   AS region,
       cat.category_name AS category,
       p.product_name  AS product,
       o.payment_method,
       oi.quantity,
       oi.unit_price,
       oi.discount,
       oi.line_revenue AS revenue
FROM order_items oi
JOIN orders     o   ON o.order_id    = oi.order_id
JOIN customers  c   ON c.customer_id = o.customer_id
JOIN regions    r   ON r.region_id   = c.region_id
JOIN products   p   ON p.product_id  = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id;

-- Monthly revenue with month-over-month growth and a 3-month rolling average
CREATE VIEW vw_monthly_revenue AS
WITH monthly AS (
    SELECT year_month,
           SUM(revenue)               AS revenue,
           COUNT(DISTINCT order_id)   AS orders
    FROM vw_sales_detail
    GROUP BY year_month
)
SELECT year_month,
       revenue,
       orders,
       LAG(revenue) OVER (ORDER BY year_month) AS prev_revenue,
       ROUND((revenue / NULLIF(LAG(revenue) OVER (ORDER BY year_month), 0) - 1) * 100, 2)
                                               AS mom_growth_pct,
       ROUND(AVG(revenue) OVER (ORDER BY year_month
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                               AS rolling_3m_avg
FROM monthly;

-- One row per customer
CREATE VIEW vw_customer_summary AS
SELECT c.customer_id,
       c.customer_name,
       r.region_name                      AS region,
       COUNT(DISTINCT o.order_id)         AS orders,
       COALESCE(SUM(oi.line_revenue), 0)  AS revenue,
       MIN(o.order_date)                  AS first_order,
       MAX(o.order_date)                  AS last_order
FROM customers c
JOIN regions r        ON r.region_id   = c.region_id
LEFT JOIN orders o    ON o.customer_id = c.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.customer_name, r.region_name;

-- Product ranking overall and inside its category (window functions)
CREATE VIEW vw_product_performance AS
WITH p AS (
    SELECT product, category,
           SUM(quantity) AS units,
           SUM(revenue)  AS revenue
    FROM vw_sales_detail
    GROUP BY product, category
)
SELECT product, category, units, revenue,
       ROUND(revenue * 100.0 / SUM(revenue) OVER (), 2)               AS revenue_share_pct,
       RANK() OVER (ORDER BY revenue DESC)                            AS overall_rank,
       RANK() OVER (PARTITION BY category ORDER BY revenue DESC)      AS category_rank
FROM p;

-- Category revenue per year with year-over-year growth
CREATE VIEW vw_category_yearly AS
WITH y AS (
    SELECT category, year, SUM(revenue) AS revenue
    FROM vw_sales_detail
    GROUP BY category, year
)
SELECT category, year, revenue,
       LAG(revenue) OVER (PARTITION BY category ORDER BY year) AS prev_year_revenue,
       ROUND((revenue / NULLIF(LAG(revenue) OVER (PARTITION BY category ORDER BY year), 0) - 1) * 100, 2)
                                                               AS yoy_growth_pct
FROM y;
