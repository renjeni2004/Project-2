-- =====================================================================
-- Sales BI Database Schema (PostgreSQL 14+)
-- Star-like normalised design: 4 dimension tables + orders + order_items
-- Run order: schema.sql -> (load data) -> views.sql
-- =====================================================================
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders      CASCADE;
DROP TABLE IF EXISTS products    CASCADE;
DROP TABLE IF EXISTS customers   CASCADE;
DROP TABLE IF EXISTS categories  CASCADE;
DROP TABLE IF EXISTS regions     CASCADE;

CREATE TABLE regions (
    region_id    SMALLINT    PRIMARY KEY,
    region_name  VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE categories (
    category_id    SMALLINT    PRIMARY KEY,
    category_name  VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE customers (
    customer_id    VARCHAR(15) PRIMARY KEY,
    customer_name  VARCHAR(80) NOT NULL,
    region_id      SMALLINT    NOT NULL REFERENCES regions (region_id)
);

CREATE TABLE products (
    product_id    SMALLINT      PRIMARY KEY,
    product_name  VARCHAR(80)   NOT NULL UNIQUE,
    category_id   SMALLINT      NOT NULL REFERENCES categories (category_id),
    list_price    NUMERIC(10,2) NOT NULL CHECK (list_price > 0)
);

CREATE TABLE orders (
    order_id        INTEGER     PRIMARY KEY,
    order_date      DATE        NOT NULL,
    customer_id     VARCHAR(15) NOT NULL REFERENCES customers (customer_id),
    payment_method  VARCHAR(30) NOT NULL
);

CREATE TABLE order_items (
    item_id         INTEGER       PRIMARY KEY,
    order_id        INTEGER       NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    product_id      SMALLINT      NOT NULL REFERENCES products (product_id),
    quantity        INTEGER       NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    discount        NUMERIC(4,2)  NOT NULL DEFAULT 0 CHECK (discount >= 0 AND discount < 1),
    -- revenue is computed by the database itself, so it can never go out of sync
    line_revenue    NUMERIC(12,2) GENERATED ALWAYS AS
                        (ROUND(quantity * unit_price * (1 - discount), 2)) STORED,
    source_line_id  VARCHAR(20)   UNIQUE        -- original Task 1 order_id (traceability)
);

-- Indexes on foreign keys and common filter columns (speeds up joins and filters)
CREATE INDEX idx_orders_customer   ON orders (customer_id);
CREATE INDEX idx_orders_date       ON orders (order_date);
CREATE INDEX idx_items_order       ON order_items (order_id);
CREATE INDEX idx_items_product     ON order_items (product_id);
CREATE INDEX idx_products_category ON products (category_id);
CREATE INDEX idx_customers_region  ON customers (region_id);
