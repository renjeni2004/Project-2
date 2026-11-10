--
-- PostgreSQL database dump
--

\restrict O8i12dvruRpM8Gr43k6MZ0Cv8hbWX5ehTwaXFMjOEs4nWVn3Z5t88sbbSu5Dc1M

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    category_id smallint NOT NULL,
    category_name character varying(50) NOT NULL
);


--
-- Name: customer_rfm; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_rfm (
    customer_id text,
    customer_name text,
    region text,
    last_order timestamp without time zone,
    frequency bigint,
    monetary double precision,
    recency_days bigint,
    r_score bigint,
    f_score bigint,
    m_score bigint,
    rfm_score bigint,
    segment text
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    customer_id character varying(15) NOT NULL,
    customer_name character varying(80) NOT NULL,
    region_id smallint NOT NULL
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    item_id integer NOT NULL,
    order_id integer NOT NULL,
    product_id smallint NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    discount numeric(4,2) DEFAULT 0 NOT NULL,
    line_revenue numeric(12,2) GENERATED ALWAYS AS (round((((quantity)::numeric * unit_price) * ((1)::numeric - discount)), 2)) STORED,
    source_line_id character varying(20),
    CONSTRAINT order_items_discount_check CHECK (((discount >= (0)::numeric) AND (discount < (1)::numeric))),
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT order_items_unit_price_check CHECK ((unit_price > (0)::numeric))
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    order_id integer NOT NULL,
    order_date date NOT NULL,
    customer_id character varying(15) NOT NULL,
    payment_method character varying(30) NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    product_id smallint NOT NULL,
    product_name character varying(80) NOT NULL,
    category_id smallint NOT NULL,
    list_price numeric(10,2) NOT NULL,
    CONSTRAINT products_list_price_check CHECK ((list_price > (0)::numeric))
);


--
-- Name: regions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.regions (
    region_id smallint NOT NULL,
    region_name character varying(30) NOT NULL
);


--
-- Name: vw_sales_detail; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_sales_detail AS
 SELECT oi.item_id,
    o.order_id,
    o.order_date,
    (EXTRACT(year FROM o.order_date))::integer AS year,
    (EXTRACT(quarter FROM o.order_date))::integer AS quarter,
    (EXTRACT(month FROM o.order_date))::integer AS month,
    (EXTRACT(isodow FROM o.order_date))::integer AS iso_weekday,
    to_char((o.order_date)::timestamp with time zone, 'YYYY-MM'::text) AS year_month,
    c.customer_id,
    c.customer_name,
    r.region_name AS region,
    cat.category_name AS category,
    p.product_name AS product,
    o.payment_method,
    oi.quantity,
    oi.unit_price,
    oi.discount,
    oi.line_revenue AS revenue
   FROM (((((public.order_items oi
     JOIN public.orders o ON ((o.order_id = oi.order_id)))
     JOIN public.customers c ON (((c.customer_id)::text = (o.customer_id)::text)))
     JOIN public.regions r ON ((r.region_id = c.region_id)))
     JOIN public.products p ON ((p.product_id = oi.product_id)))
     JOIN public.categories cat ON ((cat.category_id = p.category_id)));


--
-- Name: vw_category_yearly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_category_yearly AS
 WITH y AS (
         SELECT vw_sales_detail.category,
            vw_sales_detail.year,
            sum(vw_sales_detail.revenue) AS revenue
           FROM public.vw_sales_detail
          GROUP BY vw_sales_detail.category, vw_sales_detail.year
        )
 SELECT category,
    year,
    revenue,
    lag(revenue) OVER (PARTITION BY category ORDER BY year) AS prev_year_revenue,
    round((((revenue / NULLIF(lag(revenue) OVER (PARTITION BY category ORDER BY year), (0)::numeric)) - (1)::numeric) * (100)::numeric), 2) AS yoy_growth_pct
   FROM y;


--
-- Name: vw_customer_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_customer_summary AS
 SELECT c.customer_id,
    c.customer_name,
    r.region_name AS region,
    count(DISTINCT o.order_id) AS orders,
    COALESCE(sum(oi.line_revenue), (0)::numeric) AS revenue,
    min(o.order_date) AS first_order,
    max(o.order_date) AS last_order
   FROM (((public.customers c
     JOIN public.regions r ON ((r.region_id = c.region_id)))
     LEFT JOIN public.orders o ON (((o.customer_id)::text = (c.customer_id)::text)))
     LEFT JOIN public.order_items oi ON ((oi.order_id = o.order_id)))
  GROUP BY c.customer_id, c.customer_name, r.region_name;


--
-- Name: vw_monthly_revenue; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_monthly_revenue AS
 WITH monthly AS (
         SELECT vw_sales_detail.year_month,
            sum(vw_sales_detail.revenue) AS revenue,
            count(DISTINCT vw_sales_detail.order_id) AS orders
           FROM public.vw_sales_detail
          GROUP BY vw_sales_detail.year_month
        )
 SELECT year_month,
    revenue,
    orders,
    lag(revenue) OVER (ORDER BY year_month) AS prev_revenue,
    round((((revenue / NULLIF(lag(revenue) OVER (ORDER BY year_month), (0)::numeric)) - (1)::numeric) * (100)::numeric), 2) AS mom_growth_pct,
    round(avg(revenue) OVER (ORDER BY year_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS rolling_3m_avg
   FROM monthly;


--
-- Name: vw_product_performance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_product_performance AS
 WITH p AS (
         SELECT vw_sales_detail.product,
            vw_sales_detail.category,
            sum(vw_sales_detail.quantity) AS units,
            sum(vw_sales_detail.revenue) AS revenue
           FROM public.vw_sales_detail
          GROUP BY vw_sales_detail.product, vw_sales_detail.category
        )
 SELECT product,
    category,
    units,
    revenue,
    round(((revenue * 100.0) / sum(revenue) OVER ()), 2) AS revenue_share_pct,
    rank() OVER (ORDER BY revenue DESC) AS overall_rank,
    rank() OVER (PARTITION BY category ORDER BY revenue DESC) AS category_rank
   FROM p;


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (category_id, category_name) FROM stdin;
1	Clothing
2	Furniture
3	Home & Kitchen
4	Office Supplies
5	Technology
\.


--
-- Data for Name: customer_rfm; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer_rfm (customer_id, customer_name, region, last_order, frequency, monetary, recency_days, r_score, f_score, m_score, rfm_score, segment) FROM stdin;
CUST-1269	Liam Sharma	East	2025-12-31 00:00:00	262	65795.85	1	5	5	5	555	Champions
CUST-1054	Emma Wang	East	2025-12-31 00:00:00	162	48958.85	1	5	5	5	555	Champions
CUST-1099	Arjun Silva	East	2025-12-30 00:00:00	123	41390.61	2	5	5	5	555	Champions
CUST-1065	Olivia Garcia	East	2025-12-30 00:00:00	104	29109.7	2	5	5	5	555	Champions
CUST-1008	Liam Patel	South	2025-12-21 00:00:00	85	26093.4	11	4	5	5	455	Champions
CUST-1073	Aarav Reddy	South	2025-12-26 00:00:00	80	25531.96	6	4	5	5	455	Champions
CUST-1176	Sneha Smith	East	2025-12-28 00:00:00	93	23739.02	4	5	5	5	555	Champions
CUST-1169	Vikram Silva	East	2025-12-29 00:00:00	78	22552.15	3	5	5	5	555	Champions
CUST-1263	Chen Iyer	East	2025-12-28 00:00:00	84	21396.38	4	5	5	5	555	Champions
CUST-1193	Priya Muller	South	2025-12-31 00:00:00	68	21032.52	1	5	5	5	555	Champions
CUST-1177	Yuki Silva	East	2025-12-31 00:00:00	72	19558.68	1	5	5	5	555	Champions
CUST-1244	Mia Khan	North	2025-12-28 00:00:00	59	19431.84	4	5	5	5	555	Champions
CUST-1261	Anita Muller	South	2025-12-31 00:00:00	77	18943.5	1	5	5	5	555	Champions
CUST-1050	Carlos Iyer	East	2025-12-31 00:00:00	52	18427.82	1	5	5	5	555	Champions
CUST-1105	Sneha Wang	Central	2025-12-11 00:00:00	52	18149.11	21	3	5	5	355	Loyal
CUST-1015	Emma Reddy	South	2025-12-31 00:00:00	78	17814.06	1	5	5	5	555	Champions
CUST-1196	Meera Garcia	East	2025-12-20 00:00:00	66	17609.47	12	4	5	5	455	Champions
CUST-1205	Anita Reddy	West	2025-12-22 00:00:00	73	17246.07	10	4	5	5	455	Champions
CUST-1053	Mia Khan	East	2025-12-30 00:00:00	62	16677.54	2	5	5	5	555	Champions
CUST-1194	Fatima Iyer	West	2025-12-17 00:00:00	55	15223.79	15	4	5	5	455	Champions
CUST-1075	Fatima Nair	North	2025-12-31 00:00:00	66	14942.74	1	5	5	5	555	Champions
CUST-1183	Emma Nair	South	2025-12-07 00:00:00	46	14793.81	25	3	5	5	355	Loyal
CUST-1265	Olivia Iyer	West	2025-12-26 00:00:00	64	14785.36	6	5	5	5	555	Champions
CUST-1042	Noah Wang	West	2025-12-29 00:00:00	55	14752.11	3	5	5	5	555	Champions
CUST-1144	Liam Brown	South	2025-12-31 00:00:00	36	13811.1	1	5	5	5	555	Champions
CUST-1227	Olivia Garcia	Central	2025-12-27 00:00:00	44	13763.43	5	5	5	5	555	Champions
CUST-1192	Aarav Patel	West	2025-12-30 00:00:00	63	13481.69	2	5	5	5	555	Champions
CUST-1254	Sneha Reddy	North	2025-12-21 00:00:00	53	13194.02	11	4	5	5	455	Champions
CUST-1012	Mia Khan	South	2025-12-30 00:00:00	54	13071.81	2	5	5	5	555	Champions
CUST-1148	Carlos Smith	North	2025-12-25 00:00:00	47	12637.4	7	4	5	5	455	Champions
CUST-1164	Rahul Garcia	East	2025-12-26 00:00:00	49	12254.32	6	5	5	5	555	Champions
CUST-1110	Rahul Smith	West	2025-12-18 00:00:00	51	11767.42	14	4	5	5	455	Champions
CUST-1270	Ethan Sharma	South	2025-12-10 00:00:00	30	11271.3	22	3	5	5	355	Loyal
CUST-1275	Carlos Singh	East	2025-12-30 00:00:00	37	11233.59	2	5	5	5	555	Champions
CUST-1219	Priya Singh	West	2025-12-30 00:00:00	42	11165.75	2	5	5	5	555	Champions
CUST-1000	Priya Tanaka	West	2025-12-09 00:00:00	46	10651.76	23	3	5	5	355	Loyal
CUST-1260	Meera Iyer	North	2025-12-01 00:00:00	42	10635.36	31	3	5	5	355	Loyal
CUST-1025	Mia Iyer	West	2025-12-26 00:00:00	36	10359.83	6	4	5	5	455	Champions
CUST-1093	Anita Singh	West	2025-07-25 00:00:00	27	9923.75	160	1	5	5	155	At Risk (high value)
CUST-1115	Emma Muller	South	2025-12-26 00:00:00	46	9759.04	6	5	5	5	555	Champions
CUST-1069	Arjun Smith	Central	2025-11-27 00:00:00	24	9719.33	35	3	4	5	345	Loyal
CUST-1251	Yuki Rossi	North	2025-12-31 00:00:00	34	9619.29	1	5	5	5	555	Champions
CUST-1163	Vikram Sharma	South	2025-12-29 00:00:00	40	9580.92	3	5	5	5	555	Champions
CUST-1168	Yuki Nair	North	2025-12-23 00:00:00	39	9555.14	9	4	5	5	455	Champions
CUST-1133	John Singh	West	2025-12-31 00:00:00	21	9511.48	1	5	4	5	545	Champions
CUST-1186	John Singh	East	2025-12-20 00:00:00	31	9386.64	12	4	5	5	455	Champions
CUST-1081	John Smith	Central	2025-12-14 00:00:00	39	9263.03	18	4	5	5	455	Champions
CUST-1061	Sophia Brown	North	2025-12-31 00:00:00	28	8736.46	1	5	5	5	555	Champions
CUST-1140	Sneha Brown	West	2025-12-04 00:00:00	23	8689.03	28	3	4	5	345	Loyal
CUST-1277	Yuki Brown	East	2025-12-25 00:00:00	22	8639.3	7	4	4	5	445	Champions
CUST-1178	Anita Rossi	East	2025-12-22 00:00:00	48	8616.15	10	4	5	5	455	Champions
CUST-1220	Yuki Nair	West	2025-12-29 00:00:00	45	8594.73	3	5	5	5	555	Champions
CUST-1064	Olivia Khan	West	2025-12-14 00:00:00	19	8532.48	18	4	4	5	445	Champions
CUST-1123	Mia Smith	North	2025-12-18 00:00:00	41	8494.21	14	4	5	5	455	Champions
CUST-1184	Aarav Tanaka	North	2025-12-14 00:00:00	25	8281	18	4	4	5	445	Champions
CUST-1101	Emma Wang	Central	2025-12-30 00:00:00	22	7987.23	2	5	4	5	545	Champions
CUST-1185	Arjun Khan	East	2025-12-09 00:00:00	23	7839.08	23	3	4	5	345	Loyal
CUST-1206	Sneha Patel	South	2025-11-28 00:00:00	39	7646.58	34	3	5	5	355	Loyal
CUST-1039	Olivia Wang	Central	2025-12-24 00:00:00	31	7472.89	8	4	5	5	455	Champions
CUST-1282	Fatima Reddy	North	2025-12-27 00:00:00	23	7300.39	5	5	4	4	544	Champions
CUST-1047	Fatima Nair	South	2025-10-12 00:00:00	24	7083.52	81	2	4	4	244	At Risk (high value)
CUST-1150	Meera Muller	North	2025-12-28 00:00:00	22	6950.43	4	5	4	4	544	Champions
CUST-1279	Mia Muller	South	2025-11-27 00:00:00	21	6896.72	35	3	4	4	344	Loyal
CUST-1295	Carlos Rossi	South	2025-12-21 00:00:00	26	6862.86	11	4	4	4	444	Champions
CUST-1109	John Rossi	Central	2025-11-07 00:00:00	24	6820.71	55	2	4	4	244	At Risk (high value)
CUST-1187	Fatima Patel	South	2025-12-30 00:00:00	18	6803.62	2	5	4	4	544	Champions
CUST-1228	Rahul Khan	West	2025-12-21 00:00:00	29	6681.06	11	4	5	4	454	Champions
CUST-1094	Vikram Nair	North	2025-12-28 00:00:00	20	6674.73	4	5	4	4	544	Champions
CUST-1181	Vikram Rossi	South	2025-12-25 00:00:00	27	6641.71	7	4	5	4	454	Champions
CUST-1200	Yuki Tanaka	West	2025-12-26 00:00:00	21	6438.14	6	5	4	4	544	Champions
CUST-1103	Mia Silva	North	2025-12-08 00:00:00	28	6373.99	24	3	5	4	354	Loyal
CUST-1240	Sneha Muller	Central	2025-11-07 00:00:00	23	6362.96	55	2	4	4	244	At Risk (high value)
CUST-1238	Carlos Sharma	North	2025-12-18 00:00:00	18	6362.88	14	4	4	4	444	Champions
CUST-1032	John Nair	West	2025-12-18 00:00:00	26	6137.16	14	4	4	4	444	Champions
CUST-1272	Carlos Sharma	East	2025-12-07 00:00:00	32	6099.14	25	3	5	4	354	Loyal
CUST-1160	Arjun Patel	East	2025-12-19 00:00:00	27	6049.11	13	4	5	4	454	Champions
CUST-1215	Priya Tanaka	North	2025-12-23 00:00:00	24	5910.37	9	4	4	4	444	Champions
CUST-1127	Sophia Iyer	West	2025-12-31 00:00:00	30	5891.25	1	5	5	4	554	Champions
CUST-1097	Yuki Patel	South	2025-12-26 00:00:00	25	5878.31	6	4	4	4	444	Champions
CUST-1221	Rahul Brown	East	2025-12-27 00:00:00	31	5755.68	5	5	5	4	554	Champions
CUST-1288	Chen Brown	North	2025-12-04 00:00:00	23	5752.2	28	3	4	4	344	Loyal
CUST-1020	Anita Tanaka	Central	2025-12-10 00:00:00	27	5739.86	22	3	4	4	344	Loyal
CUST-1216	Carlos Patel	South	2025-12-30 00:00:00	23	5485.37	2	5	4	4	544	Champions
CUST-1293	Sophia Patel	East	2025-12-17 00:00:00	15	5477.82	15	4	3	4	434	Loyal
CUST-1098	Arjun Patel	East	2025-12-24 00:00:00	15	5461.21	8	4	3	4	434	Loyal
CUST-1233	Anita Garcia	West	2025-12-30 00:00:00	16	5456.36	2	5	4	4	544	Champions
CUST-1084	Arjun Sharma	East	2025-09-04 00:00:00	9	5419.25	119	1	2	4	124	Needs Attention
CUST-1074	Carlos Sharma	North	2025-10-16 00:00:00	12	5416.11	77	2	3	4	234	Needs Attention
CUST-1104	Sneha Tanaka	Central	2025-12-23 00:00:00	16	5406.55	9	4	4	4	444	Champions
CUST-1100	Meera Rossi	South	2025-12-27 00:00:00	17	5373.1	5	5	4	4	544	Champions
CUST-1130	Mia Iyer	Central	2025-11-01 00:00:00	21	5360.89	61	2	4	4	244	At Risk (high value)
CUST-1002	John Muller	East	2025-11-05 00:00:00	17	5221.21	57	2	4	4	244	At Risk (high value)
CUST-1226	Emma Sharma	Central	2025-12-25 00:00:00	19	5121.93	7	4	4	4	444	Champions
CUST-1134	Noah Garcia	North	2025-12-06 00:00:00	23	5065.91	26	3	4	4	344	Loyal
CUST-1198	Aarav Iyer	South	2025-10-22 00:00:00	11	5065.33	71	2	3	4	234	Needs Attention
CUST-1007	Ethan Tanaka	East	2025-12-29 00:00:00	21	4947.52	3	5	4	4	544	Champions
CUST-1158	Ethan Wang	West	2025-12-17 00:00:00	17	4878.92	15	4	4	4	444	Champions
CUST-1189	Meera Reddy	East	2025-10-12 00:00:00	8	4857.03	81	2	2	4	224	Needs Attention
CUST-1208	Yuki Patel	East	2025-12-31 00:00:00	20	4741.24	1	5	4	4	544	Champions
CUST-1280	Liam Sharma	East	2025-11-07 00:00:00	22	4638.45	55	2	4	4	244	At Risk (high value)
CUST-1155	Sophia Wang	North	2025-12-14 00:00:00	16	4501.13	18	4	4	4	444	Champions
CUST-1167	Emma Muller	Central	2025-11-05 00:00:00	15	4405.38	57	2	3	4	234	Needs Attention
CUST-1023	John Rossi	East	2025-12-28 00:00:00	22	4385.14	4	5	4	4	544	Champions
CUST-1210	Chen Wang	North	2025-11-24 00:00:00	12	4337.86	38	3	3	4	334	Loyal
CUST-1207	Aarav Wang	West	2025-11-18 00:00:00	14	4328.23	44	2	3	4	234	Needs Attention
CUST-1021	Ethan Singh	East	2025-11-30 00:00:00	13	4306.94	32	3	3	4	334	Loyal
CUST-1243	Arjun Brown	Central	2025-11-26 00:00:00	13	4292.68	36	3	3	4	334	Loyal
CUST-1107	Ethan Nair	West	2025-09-21 00:00:00	11	4251.27	102	1	3	4	134	Needs Attention
CUST-1071	Sneha Smith	South	2025-12-20 00:00:00	19	4217.12	12	4	4	4	444	Champions
CUST-1197	Ethan Rossi	East	2025-12-02 00:00:00	12	4146.96	30	3	3	4	334	Loyal
CUST-1159	Chen Tanaka	East	2025-12-21 00:00:00	22	4139.7	11	4	4	4	444	Champions
CUST-1180	Carlos Rossi	East	2025-11-30 00:00:00	20	4034.34	32	3	4	4	344	Loyal
CUST-1062	Fatima Garcia	North	2025-12-29 00:00:00	20	4027.13	3	5	4	4	544	Champions
CUST-1036	Emma Patel	North	2025-12-14 00:00:00	17	4022.76	18	4	4	4	444	Champions
CUST-1248	Rahul Singh	West	2025-12-30 00:00:00	13	3923.21	2	5	3	4	534	Loyal
CUST-1090	Chen Iyer	East	2025-11-16 00:00:00	20	3877.11	46	2	4	4	244	At Risk (high value)
CUST-1132	Yuki Garcia	West	2025-12-23 00:00:00	28	3864.99	9	4	5	4	454	Champions
CUST-1034	Priya Brown	North	2025-11-14 00:00:00	16	3847.92	48	2	4	3	243	Needs Attention
CUST-1087	Sophia Smith	Central	2025-12-01 00:00:00	12	3809	31	3	3	3	333	Loyal
CUST-1080	Yuki Khan	East	2025-12-22 00:00:00	15	3740.98	10	4	3	3	433	Loyal
CUST-1077	John Khan	East	2025-11-29 00:00:00	17	3728.92	33	3	4	3	343	Loyal
CUST-1204	Chen Sharma	East	2025-07-30 00:00:00	13	3707.58	155	1	3	3	133	Needs Attention
CUST-1029	Ethan Wang	South	2025-12-24 00:00:00	18	3684.52	8	4	4	3	443	Loyal
CUST-1267	Olivia Iyer	North	2025-12-23 00:00:00	15	3669.57	9	4	3	3	433	Loyal
CUST-1045	John Muller	West	2025-12-26 00:00:00	18	3615.7	6	4	4	3	443	Loyal
CUST-1285	Chen Smith	East	2025-12-26 00:00:00	14	3547.32	6	5	3	3	533	Loyal
CUST-1182	Rahul Brown	East	2025-12-21 00:00:00	17	3540.2	11	4	4	3	443	Loyal
CUST-1078	Rahul Garcia	East	2025-12-29 00:00:00	18	3539.23	3	5	4	3	543	Loyal
CUST-1086	Mia Wang	West	2025-12-23 00:00:00	10	3526	9	4	3	3	433	Loyal
CUST-1067	Mia Nair	West	2025-10-25 00:00:00	10	3496.25	68	2	2	3	223	Needs Attention
CUST-1157	Vikram Khan	East	2025-12-30 00:00:00	13	3453.34	2	5	3	3	533	Loyal
CUST-1286	Sneha Sharma	North	2025-11-24 00:00:00	17	3347.65	38	3	4	3	343	Loyal
CUST-1011	Anita Rossi	East	2025-12-29 00:00:00	15	3330.5	3	5	3	3	533	Loyal
CUST-1156	Rahul Nair	Central	2025-11-11 00:00:00	10	3328.12	51	2	3	3	233	Needs Attention
CUST-1218	Olivia Rossi	North	2025-11-08 00:00:00	10	3325.58	54	2	3	3	233	Needs Attention
CUST-1111	Ethan Reddy	West	2025-12-04 00:00:00	10	3311.97	28	3	3	3	333	Loyal
CUST-1268	Emma Patel	South	2025-12-26 00:00:00	11	3292.41	6	5	3	3	533	Loyal
CUST-1241	Sneha Tanaka	East	2025-12-16 00:00:00	17	3198.22	16	4	4	3	443	Loyal
CUST-1030	Chen Tanaka	West	2025-11-26 00:00:00	13	3171.9	36	3	3	3	333	Loyal
CUST-1125	Anita Brown	West	2024-12-18 00:00:00	4	3159.89	379	1	1	3	113	Hibernating
CUST-1278	Ethan Rossi	West	2025-12-16 00:00:00	16	3144.22	16	4	4	3	443	Loyal
CUST-1122	Noah Patel	North	2025-10-31 00:00:00	12	3116.48	62	2	3	3	233	Needs Attention
CUST-1066	Priya Garcia	West	2025-11-24 00:00:00	13	3099.8	38	3	3	3	333	Loyal
CUST-1209	Sneha Brown	North	2025-12-30 00:00:00	13	3087.19	2	5	3	3	533	Loyal
CUST-1225	Yuki Rossi	South	2025-12-21 00:00:00	17	3083.68	11	4	4	3	443	Loyal
CUST-1005	Liam Silva	East	2025-11-25 00:00:00	8	3080.78	37	3	2	3	323	Needs Attention
CUST-1213	Fatima Muller	South	2025-12-18 00:00:00	9	3062.12	14	4	2	3	423	Needs Attention
CUST-1154	Arjun Patel	North	2025-11-11 00:00:00	15	2989.28	51	2	3	3	233	Needs Attention
CUST-1195	Ethan Iyer	East	2025-12-09 00:00:00	18	2976.29	23	3	4	3	343	Loyal
CUST-1264	Chen Rossi	West	2025-12-29 00:00:00	12	2907.36	3	5	3	3	533	Loyal
CUST-1044	Mia Muller	West	2025-12-08 00:00:00	15	2887.33	24	3	3	3	333	Loyal
CUST-1040	Chen Smith	North	2025-11-12 00:00:00	11	2878.43	50	2	3	3	233	Needs Attention
CUST-1262	Arjun Nair	West	2025-09-02 00:00:00	7	2854.81	121	1	2	3	123	Needs Attention
CUST-1028	Liam Iyer	East	2025-12-13 00:00:00	17	2848.5	19	3	4	3	343	Loyal
CUST-1031	Meera Silva	South	2025-10-14 00:00:00	6	2799.69	79	2	2	3	223	Needs Attention
CUST-1014	Liam Smith	South	2025-12-30 00:00:00	20	2797.99	2	5	4	3	543	Loyal
CUST-1114	Liam Iyer	North	2025-12-11 00:00:00	12	2699.23	21	3	3	3	333	Loyal
CUST-1153	Arjun Garcia	North	2025-11-22 00:00:00	11	2651.51	40	3	3	3	333	Loyal
CUST-1057	Liam Garcia	West	2025-07-01 00:00:00	11	2606.13	184	1	3	3	133	Needs Attention
CUST-1001	Sophia Smith	North	2025-12-21 00:00:00	13	2598.51	11	4	3	3	433	Loyal
CUST-1259	Emma Garcia	East	2025-11-30 00:00:00	6	2547.91	32	3	2	3	323	Needs Attention
CUST-1170	Noah Nair	East	2025-11-01 00:00:00	19	2532.66	61	2	4	3	243	Needs Attention
CUST-1299	Noah Khan	East	2025-11-23 00:00:00	15	2479.66	39	3	3	3	333	Loyal
CUST-1274	Liam Wang	West	2025-10-27 00:00:00	11	2410.86	66	2	3	3	233	Needs Attention
CUST-1250	Rahul Khan	East	2025-11-28 00:00:00	11	2405.21	34	3	3	3	333	Loyal
CUST-1068	Noah Sharma	South	2025-11-19 00:00:00	11	2403.46	43	2	3	3	233	Needs Attention
CUST-1201	Arjun Silva	Central	2025-11-29 00:00:00	12	2401	33	3	3	3	333	Loyal
CUST-1235	Ethan Muller	South	2025-12-20 00:00:00	11	2322.94	12	4	3	3	433	Loyal
CUST-1256	Carlos Muller	South	2025-11-23 00:00:00	12	2275.19	39	3	3	3	333	Loyal
CUST-1102	Emma Reddy	West	2025-12-03 00:00:00	10	2266.39	29	3	3	3	333	Loyal
CUST-1117	Emma Wang	West	2025-12-08 00:00:00	7	2263.02	24	3	2	3	323	Needs Attention
CUST-1108	Priya Patel	North	2025-11-04 00:00:00	7	2262.28	58	2	2	3	223	Needs Attention
CUST-1174	Anita Iyer	South	2025-11-24 00:00:00	9	2250.97	38	3	2	3	323	Needs Attention
CUST-1292	John Rossi	South	2025-11-13 00:00:00	10	2212.63	49	2	3	3	233	Needs Attention
CUST-1239	Sophia Patel	West	2025-10-21 00:00:00	8	2201.06	72	2	2	3	223	Needs Attention
CUST-1249	Chen Smith	East	2025-11-28 00:00:00	13	2179.99	34	3	3	2	332	Needs Attention
CUST-1043	Priya Nair	East	2025-07-18 00:00:00	7	2174.47	167	1	2	2	122	Hibernating
CUST-1229	Carlos Patel	South	2025-12-23 00:00:00	11	2154.21	9	4	3	2	432	Needs Attention
CUST-1049	Noah Iyer	North	2025-12-16 00:00:00	12	2098.19	16	4	3	2	432	Needs Attention
CUST-1290	Priya Muller	Central	2025-07-08 00:00:00	6	2090.31	177	1	2	2	122	Hibernating
CUST-1253	Liam Reddy	Central	2025-12-23 00:00:00	15	2053.75	9	4	3	2	432	Needs Attention
CUST-1236	John Brown	East	2025-12-06 00:00:00	12	2035.18	26	3	3	2	332	Needs Attention
CUST-1211	Mia Garcia	West	2025-12-22 00:00:00	8	2015.37	10	4	2	2	422	Needs Attention
CUST-1212	John Iyer	North	2025-12-06 00:00:00	13	2008.92	26	3	3	2	332	Needs Attention
CUST-1112	Ethan Nair	North	2025-11-21 00:00:00	13	1986.56	41	2	3	2	232	Needs Attention
CUST-1232	Aarav Silva	East	2025-12-27 00:00:00	10	1972.1	5	5	3	2	532	Needs Attention
CUST-1010	Liam Singh	East	2025-11-08 00:00:00	9	1971.29	54	2	2	2	222	Hibernating
CUST-1129	Anita Garcia	West	2025-11-09 00:00:00	7	1968.72	53	2	2	2	222	Hibernating
CUST-1046	Carlos Singh	Central	2025-11-28 00:00:00	5	1966.8	34	3	2	2	322	Needs Attention
CUST-1138	Emma Tanaka	West	2025-10-09 00:00:00	6	1960.98	84	2	2	2	222	Hibernating
CUST-1199	Sneha Nair	East	2025-11-05 00:00:00	4	1957.28	57	2	1	2	212	Hibernating
CUST-1173	Yuki Silva	North	2025-12-28 00:00:00	11	1899.33	4	5	3	2	532	Needs Attention
CUST-1234	Anita Rossi	North	2025-10-10 00:00:00	7	1782.38	83	2	2	2	222	Hibernating
CUST-1296	Vikram Silva	West	2025-11-18 00:00:00	8	1711.6	44	2	2	2	222	Hibernating
CUST-1276	Carlos Nair	Central	2025-11-07 00:00:00	9	1689.38	55	2	2	2	222	Hibernating
CUST-1291	Rahul Sharma	East	2025-06-19 00:00:00	9	1687.43	196	1	2	2	122	Hibernating
CUST-1298	Olivia Tanaka	Central	2025-03-20 00:00:00	4	1678.15	287	1	1	2	112	Hibernating
CUST-1171	Noah Brown	East	2025-10-05 00:00:00	9	1676.72	88	2	2	2	222	Hibernating
CUST-1091	Emma Wang	North	2025-12-03 00:00:00	9	1637.35	29	3	2	2	322	Needs Attention
CUST-1131	Sneha Rossi	West	2025-12-07 00:00:00	12	1636.18	25	3	3	2	332	Needs Attention
CUST-1137	John Brown	East	2025-07-14 00:00:00	4	1581.61	171	1	1	2	112	Hibernating
CUST-1059	Vikram Patel	East	2025-06-14 00:00:00	6	1558.88	201	1	2	2	122	Hibernating
CUST-1224	Liam Nair	North	2025-11-24 00:00:00	7	1550.12	38	3	2	2	322	Needs Attention
CUST-1222	Liam Khan	North	2025-11-17 00:00:00	8	1475.76	45	2	2	2	222	Hibernating
CUST-1147	Liam Brown	East	2025-12-24 00:00:00	9	1465.85	8	4	2	2	422	Needs Attention
CUST-1203	John Iyer	East	2025-12-12 00:00:00	11	1432.15	20	3	3	2	332	Needs Attention
CUST-1085	Rahul Patel	Central	2025-11-15 00:00:00	5	1404.84	47	2	2	2	222	Hibernating
CUST-1190	Aarav Silva	West	2025-10-02 00:00:00	7	1380.29	91	2	2	2	222	Hibernating
CUST-1255	Yuki Tanaka	South	2025-10-28 00:00:00	5	1377.55	65	2	2	2	222	Hibernating
CUST-1126	Anita Nair	South	2025-09-01 00:00:00	8	1375.37	122	1	2	2	122	Hibernating
CUST-1024	Sophia Tanaka	West	2025-07-25 00:00:00	5	1358.5	160	1	2	2	122	Hibernating
CUST-1287	Aarav Singh	South	2025-04-24 00:00:00	7	1356.91	252	1	2	2	122	Hibernating
CUST-1149	Sneha Sharma	East	2025-04-26 00:00:00	9	1348.41	250	1	2	2	122	Hibernating
CUST-1013	John Muller	South	2025-11-25 00:00:00	4	1330.52	37	3	1	2	312	Needs Attention
CUST-1141	Sophia Brown	North	2025-09-21 00:00:00	4	1317.56	102	1	1	2	112	Hibernating
CUST-1019	Sneha Khan	Central	2025-09-29 00:00:00	5	1309.63	94	1	1	2	112	Hibernating
CUST-1058	Aarav Iyer	East	2025-11-25 00:00:00	14	1295.69	37	3	3	2	332	Needs Attention
CUST-1120	Rahul Garcia	West	2025-08-20 00:00:00	8	1264.05	134	1	2	2	122	Hibernating
CUST-1033	Chen Singh	Central	2025-10-10 00:00:00	5	1260.64	83	2	2	2	222	Hibernating
CUST-1121	Priya Khan	North	2025-07-01 00:00:00	3	1258.24	184	1	1	2	112	Hibernating
CUST-1076	Chen Nair	Central	2025-11-02 00:00:00	4	1252.15	60	2	1	2	212	Hibernating
CUST-1266	Anita Nair	West	2025-04-16 00:00:00	8	1238.39	260	1	2	2	122	Hibernating
CUST-1136	Anita Silva	North	2025-12-30 00:00:00	10	1164.31	2	5	3	2	532	Needs Attention
CUST-1048	Vikram Wang	East	2025-04-07 00:00:00	4	1160.12	269	1	1	2	112	Hibernating
CUST-1026	Meera Brown	West	2025-10-21 00:00:00	7	1156.15	72	2	2	2	222	Hibernating
CUST-1018	Fatima Muller	South	2025-11-15 00:00:00	7	1147.04	47	2	2	2	222	Hibernating
CUST-1237	Noah Tanaka	North	2025-08-26 00:00:00	4	1083.8	128	1	1	2	112	Hibernating
CUST-1095	Sophia Khan	East	2025-11-11 00:00:00	5	1075.41	51	2	2	2	222	Hibernating
CUST-1223	Arjun Silva	East	2025-11-07 00:00:00	6	1021.58	55	2	2	2	222	Hibernating
CUST-1258	Fatima Sharma	East	2025-09-25 00:00:00	5	983.6	98	1	2	2	122	Hibernating
CUST-1060	John Wang	Central	2025-11-15 00:00:00	5	958.1	47	2	2	2	222	Hibernating
CUST-1128	Sophia Patel	North	2025-10-18 00:00:00	6	951.76	75	2	2	2	222	Hibernating
CUST-1022	Priya Silva	South	2025-07-21 00:00:00	4	938.74	164	1	1	2	112	Hibernating
CUST-1082	John Muller	West	2025-11-10 00:00:00	5	926.57	52	2	2	1	221	Hibernating
CUST-1273	John Garcia	West	2025-11-19 00:00:00	6	867.45	43	2	2	1	221	Hibernating
CUST-1179	Priya Tanaka	East	2025-07-20 00:00:00	4	860.02	165	1	1	1	111	Hibernating
CUST-1106	Mia Smith	South	2025-11-13 00:00:00	5	856.57	49	2	2	1	221	Hibernating
CUST-1124	Mia Sharma	East	2025-12-17 00:00:00	5	854.31	15	4	2	1	421	Needs Attention
CUST-1038	Arjun Reddy	North	2025-03-17 00:00:00	5	833.19	290	1	2	1	121	Hibernating
CUST-1051	Carlos Sharma	North	2025-11-10 00:00:00	3	819.41	52	2	1	1	211	Hibernating
CUST-1004	Vikram Patel	West	2025-07-23 00:00:00	3	792.33	162	1	1	1	111	Hibernating
CUST-1283	Vikram Reddy	East	2025-03-25 00:00:00	2	751.87	282	1	1	1	111	Hibernating
CUST-1017	Fatima Sharma	West	2025-04-02 00:00:00	3	741.75	274	1	1	1	111	Hibernating
CUST-1152	Liam Iyer	West	2025-05-14 00:00:00	5	713.18	232	1	2	1	121	Hibernating
CUST-1055	Sneha Tanaka	East	2025-08-09 00:00:00	8	692.92	145	1	2	1	121	Hibernating
CUST-1006	Ethan Tanaka	East	2024-12-17 00:00:00	3	674.78	380	1	1	1	111	Hibernating
CUST-1113	Carlos Garcia	Central	2025-09-17 00:00:00	9	670.08	106	1	2	1	121	Hibernating
CUST-1027	Emma Sharma	East	2025-11-10 00:00:00	3	653.37	52	2	1	1	211	Hibernating
CUST-1072	Yuki Muller	South	2025-12-19 00:00:00	8	637.72	13	4	2	1	421	Needs Attention
CUST-1135	Sneha Sharma	South	2025-11-21 00:00:00	5	633.7	41	2	2	1	221	Hibernating
CUST-1037	Sophia Brown	West	2024-11-16 00:00:00	1	628.87	411	1	1	1	111	Hibernating
CUST-1247	Sneha Smith	North	2025-12-31 00:00:00	4	612.82	1	5	1	1	511	Needs Attention
CUST-1009	Carlos Smith	North	2025-12-26 00:00:00	6	598.9	6	4	2	1	421	Needs Attention
CUST-1242	Emma Reddy	West	2024-11-03 00:00:00	3	596.65	424	1	1	1	111	Hibernating
CUST-1202	Emma Brown	Central	2025-05-01 00:00:00	4	594.94	245	1	1	1	111	Hibernating
CUST-1289	Fatima Patel	North	2025-07-16 00:00:00	3	594.3	169	1	1	1	111	Hibernating
CUST-1035	Mia Iyer	East	2025-04-10 00:00:00	3	570.25	266	1	1	1	111	Hibernating
CUST-1172	Chen Reddy	North	2025-12-11 00:00:00	3	510.42	21	3	1	1	311	Needs Attention
CUST-1165	Liam Singh	West	2025-11-01 00:00:00	4	472.67	61	2	1	1	211	Hibernating
CUST-1143	Anita Garcia	North	2025-11-24 00:00:00	5	462.1	38	3	2	1	321	Needs Attention
CUST-1041	Anita Muller	Central	2025-11-23 00:00:00	4	454.22	39	3	1	1	311	Needs Attention
CUST-1217	John Patel	West	2025-09-11 00:00:00	2	454.1	112	1	1	1	111	Hibernating
CUST-1231	Ethan Smith	West	2025-12-17 00:00:00	4	382.51	15	4	1	1	411	Needs Attention
CUST-1284	Noah Garcia	Central	2025-09-19 00:00:00	3	363.83	104	1	1	1	111	Hibernating
CUST-1161	Noah Rossi	North	2025-11-29 00:00:00	2	359.83	33	3	1	1	311	Needs Attention
CUST-1191	Chen Reddy	West	2025-12-11 00:00:00	4	351.87	21	3	1	1	311	Needs Attention
CUST-1088	Ethan Iyer	North	2025-03-03 00:00:00	2	332.48	304	1	1	1	111	Hibernating
CUST-1257	Yuki Patel	East	2025-12-09 00:00:00	3	330.74	23	3	1	1	311	Needs Attention
CUST-1297	Arjun Muller	East	2025-03-03 00:00:00	2	313.73	304	1	1	1	111	Hibernating
CUST-1063	Priya Tanaka	North	2025-12-14 00:00:00	3	293.16	18	4	1	1	411	Needs Attention
CUST-1145	Carlos Nair	West	2025-06-01 00:00:00	1	287.63	214	1	1	1	111	Hibernating
CUST-1175	Liam Sharma	South	2025-10-31 00:00:00	3	272.24	62	2	1	1	211	Hibernating
CUST-1245	Chen Rossi	East	2025-06-02 00:00:00	2	254.76	213	1	1	1	111	Hibernating
CUST-1294	Carlos Muller	North	2025-09-09 00:00:00	4	225.39	114	1	1	1	111	Hibernating
CUST-1146	Yuki Nair	Central	2025-01-26 00:00:00	1	219.35	340	1	1	1	111	Hibernating
CUST-1151	Aarav Rossi	Central	2025-11-13 00:00:00	3	216.49	49	2	1	1	211	Hibernating
CUST-1079	Liam Tanaka	West	2025-06-30 00:00:00	3	216.4	185	1	1	1	111	Hibernating
CUST-1271	Anita Iyer	West	2024-12-07 00:00:00	3	211.39	390	1	1	1	111	Hibernating
CUST-1214	Aarav Wang	South	2024-12-07 00:00:00	3	198.49	390	1	1	1	111	Hibernating
CUST-1139	Priya Patel	East	2024-10-25 00:00:00	2	152.98	433	1	1	1	111	Hibernating
CUST-1096	Noah Singh	West	2025-11-24 00:00:00	1	151.44	38	3	1	1	311	Needs Attention
CUST-1016	Priya Garcia	East	2024-12-15 00:00:00	2	142.54	382	1	1	1	111	Hibernating
CUST-1089	Chen Brown	West	2025-09-17 00:00:00	1	140.94	106	1	1	1	111	Hibernating
CUST-1281	Emma Iyer	East	2025-11-11 00:00:00	1	133.04	51	2	1	1	211	Hibernating
CUST-1119	Arjun Khan	Central	2025-01-22 00:00:00	2	132.89	344	1	1	1	111	Hibernating
CUST-1246	Mia Khan	East	2025-11-24 00:00:00	2	128.6	38	3	1	1	311	Needs Attention
CUST-1230	Ethan Iyer	West	2025-12-27 00:00:00	1	90.74	5	5	1	1	511	Needs Attention
CUST-1188	Ethan Tanaka	East	2025-08-31 00:00:00	2	87.52	123	1	1	1	111	Hibernating
CUST-1056	Olivia Smith	West	2024-02-19 00:00:00	1	57.05	682	1	1	1	111	Hibernating
CUST-1083	Arjun Iyer	East	2025-10-08 00:00:00	1	24.1	85	2	1	1	211	Hibernating
CUST-1092	Emma Smith	East	2025-09-08 00:00:00	1	17.54	115	1	1	1	111	Hibernating
CUST-1142	John Silva	West	2025-07-20 00:00:00	1	15.32	165	1	1	1	111	Hibernating
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customers (customer_id, customer_name, region_id) FROM stdin;
CUST-1000	Priya Tanaka	5
CUST-1001	Sophia Smith	3
CUST-1002	John Muller	2
CUST-1004	Vikram Patel	5
CUST-1005	Liam Silva	2
CUST-1006	Ethan Tanaka	2
CUST-1007	Ethan Tanaka	2
CUST-1008	Liam Patel	4
CUST-1009	Carlos Smith	3
CUST-1010	Liam Singh	2
CUST-1011	Anita Rossi	2
CUST-1012	Mia Khan	4
CUST-1013	John Muller	4
CUST-1014	Liam Smith	4
CUST-1015	Emma Reddy	4
CUST-1016	Priya Garcia	2
CUST-1017	Fatima Sharma	5
CUST-1018	Fatima Muller	4
CUST-1019	Sneha Khan	1
CUST-1020	Anita Tanaka	1
CUST-1021	Ethan Singh	2
CUST-1022	Priya Silva	4
CUST-1023	John Rossi	2
CUST-1024	Sophia Tanaka	5
CUST-1025	Mia Iyer	5
CUST-1026	Meera Brown	5
CUST-1027	Emma Sharma	2
CUST-1028	Liam Iyer	2
CUST-1029	Ethan Wang	4
CUST-1030	Chen Tanaka	5
CUST-1031	Meera Silva	4
CUST-1032	John Nair	5
CUST-1033	Chen Singh	1
CUST-1034	Priya Brown	3
CUST-1035	Mia Iyer	2
CUST-1036	Emma Patel	3
CUST-1037	Sophia Brown	5
CUST-1038	Arjun Reddy	3
CUST-1039	Olivia Wang	1
CUST-1040	Chen Smith	3
CUST-1041	Anita Muller	1
CUST-1042	Noah Wang	5
CUST-1043	Priya Nair	2
CUST-1044	Mia Muller	5
CUST-1045	John Muller	5
CUST-1046	Carlos Singh	1
CUST-1047	Fatima Nair	4
CUST-1048	Vikram Wang	2
CUST-1049	Noah Iyer	3
CUST-1050	Carlos Iyer	2
CUST-1051	Carlos Sharma	3
CUST-1053	Mia Khan	2
CUST-1054	Emma Wang	2
CUST-1055	Sneha Tanaka	2
CUST-1056	Olivia Smith	5
CUST-1057	Liam Garcia	5
CUST-1058	Aarav Iyer	2
CUST-1059	Vikram Patel	2
CUST-1060	John Wang	1
CUST-1061	Sophia Brown	3
CUST-1062	Fatima Garcia	3
CUST-1063	Priya Tanaka	3
CUST-1064	Olivia Khan	5
CUST-1065	Olivia Garcia	2
CUST-1066	Priya Garcia	5
CUST-1067	Mia Nair	5
CUST-1068	Noah Sharma	4
CUST-1069	Arjun Smith	1
CUST-1071	Sneha Smith	4
CUST-1072	Yuki Muller	4
CUST-1073	Aarav Reddy	4
CUST-1074	Carlos Sharma	3
CUST-1075	Fatima Nair	3
CUST-1076	Chen Nair	1
CUST-1077	John Khan	2
CUST-1078	Rahul Garcia	2
CUST-1079	Liam Tanaka	5
CUST-1080	Yuki Khan	2
CUST-1081	John Smith	1
CUST-1082	John Muller	5
CUST-1083	Arjun Iyer	2
CUST-1084	Arjun Sharma	2
CUST-1085	Rahul Patel	1
CUST-1086	Mia Wang	5
CUST-1087	Sophia Smith	1
CUST-1088	Ethan Iyer	3
CUST-1089	Chen Brown	5
CUST-1090	Chen Iyer	2
CUST-1091	Emma Wang	3
CUST-1092	Emma Smith	2
CUST-1093	Anita Singh	5
CUST-1094	Vikram Nair	3
CUST-1095	Sophia Khan	2
CUST-1096	Noah Singh	5
CUST-1097	Yuki Patel	4
CUST-1098	Arjun Patel	2
CUST-1099	Arjun Silva	2
CUST-1100	Meera Rossi	4
CUST-1101	Emma Wang	1
CUST-1102	Emma Reddy	5
CUST-1103	Mia Silva	3
CUST-1104	Sneha Tanaka	1
CUST-1105	Sneha Wang	1
CUST-1106	Mia Smith	4
CUST-1107	Ethan Nair	5
CUST-1108	Priya Patel	3
CUST-1109	John Rossi	1
CUST-1110	Rahul Smith	5
CUST-1111	Ethan Reddy	5
CUST-1112	Ethan Nair	3
CUST-1113	Carlos Garcia	1
CUST-1114	Liam Iyer	3
CUST-1115	Emma Muller	4
CUST-1117	Emma Wang	5
CUST-1119	Arjun Khan	1
CUST-1120	Rahul Garcia	5
CUST-1121	Priya Khan	3
CUST-1122	Noah Patel	3
CUST-1123	Mia Smith	3
CUST-1124	Mia Sharma	2
CUST-1125	Anita Brown	5
CUST-1126	Anita Nair	4
CUST-1127	Sophia Iyer	5
CUST-1128	Sophia Patel	3
CUST-1129	Anita Garcia	5
CUST-1130	Mia Iyer	1
CUST-1131	Sneha Rossi	5
CUST-1132	Yuki Garcia	5
CUST-1133	John Singh	5
CUST-1134	Noah Garcia	3
CUST-1135	Sneha Sharma	4
CUST-1136	Anita Silva	3
CUST-1137	John Brown	2
CUST-1138	Emma Tanaka	5
CUST-1139	Priya Patel	2
CUST-1140	Sneha Brown	5
CUST-1141	Sophia Brown	3
CUST-1142	John Silva	5
CUST-1143	Anita Garcia	3
CUST-1144	Liam Brown	4
CUST-1145	Carlos Nair	5
CUST-1146	Yuki Nair	1
CUST-1147	Liam Brown	2
CUST-1148	Carlos Smith	3
CUST-1149	Sneha Sharma	2
CUST-1150	Meera Muller	3
CUST-1151	Aarav Rossi	1
CUST-1152	Liam Iyer	5
CUST-1153	Arjun Garcia	3
CUST-1154	Arjun Patel	3
CUST-1155	Sophia Wang	3
CUST-1156	Rahul Nair	1
CUST-1157	Vikram Khan	2
CUST-1158	Ethan Wang	5
CUST-1159	Chen Tanaka	2
CUST-1160	Arjun Patel	2
CUST-1161	Noah Rossi	3
CUST-1163	Vikram Sharma	4
CUST-1164	Rahul Garcia	2
CUST-1165	Liam Singh	5
CUST-1167	Emma Muller	1
CUST-1168	Yuki Nair	3
CUST-1169	Vikram Silva	2
CUST-1170	Noah Nair	2
CUST-1171	Noah Brown	2
CUST-1172	Chen Reddy	3
CUST-1173	Yuki Silva	3
CUST-1174	Anita Iyer	4
CUST-1175	Liam Sharma	4
CUST-1176	Sneha Smith	2
CUST-1177	Yuki Silva	2
CUST-1178	Anita Rossi	2
CUST-1179	Priya Tanaka	2
CUST-1180	Carlos Rossi	2
CUST-1181	Vikram Rossi	4
CUST-1182	Rahul Brown	2
CUST-1183	Emma Nair	4
CUST-1184	Aarav Tanaka	3
CUST-1185	Arjun Khan	2
CUST-1186	John Singh	2
CUST-1187	Fatima Patel	4
CUST-1188	Ethan Tanaka	2
CUST-1189	Meera Reddy	2
CUST-1190	Aarav Silva	5
CUST-1191	Chen Reddy	5
CUST-1192	Aarav Patel	5
CUST-1193	Priya Muller	4
CUST-1194	Fatima Iyer	5
CUST-1195	Ethan Iyer	2
CUST-1196	Meera Garcia	2
CUST-1197	Ethan Rossi	2
CUST-1198	Aarav Iyer	4
CUST-1199	Sneha Nair	2
CUST-1200	Yuki Tanaka	5
CUST-1201	Arjun Silva	1
CUST-1202	Emma Brown	1
CUST-1203	John Iyer	2
CUST-1204	Chen Sharma	2
CUST-1205	Anita Reddy	5
CUST-1206	Sneha Patel	4
CUST-1207	Aarav Wang	5
CUST-1208	Yuki Patel	2
CUST-1209	Sneha Brown	3
CUST-1210	Chen Wang	3
CUST-1211	Mia Garcia	5
CUST-1212	John Iyer	3
CUST-1213	Fatima Muller	4
CUST-1214	Aarav Wang	4
CUST-1215	Priya Tanaka	3
CUST-1216	Carlos Patel	4
CUST-1217	John Patel	5
CUST-1218	Olivia Rossi	3
CUST-1219	Priya Singh	5
CUST-1220	Yuki Nair	5
CUST-1221	Rahul Brown	2
CUST-1222	Liam Khan	3
CUST-1223	Arjun Silva	2
CUST-1224	Liam Nair	3
CUST-1225	Yuki Rossi	4
CUST-1226	Emma Sharma	1
CUST-1227	Olivia Garcia	1
CUST-1228	Rahul Khan	5
CUST-1229	Carlos Patel	4
CUST-1230	Ethan Iyer	5
CUST-1231	Ethan Smith	5
CUST-1232	Aarav Silva	2
CUST-1233	Anita Garcia	5
CUST-1234	Anita Rossi	3
CUST-1235	Ethan Muller	4
CUST-1236	John Brown	2
CUST-1237	Noah Tanaka	3
CUST-1238	Carlos Sharma	3
CUST-1239	Sophia Patel	5
CUST-1240	Sneha Muller	1
CUST-1241	Sneha Tanaka	2
CUST-1242	Emma Reddy	5
CUST-1243	Arjun Brown	1
CUST-1244	Mia Khan	3
CUST-1245	Chen Rossi	2
CUST-1246	Mia Khan	2
CUST-1247	Sneha Smith	3
CUST-1248	Rahul Singh	5
CUST-1249	Chen Smith	2
CUST-1250	Rahul Khan	2
CUST-1251	Yuki Rossi	3
CUST-1253	Liam Reddy	1
CUST-1254	Sneha Reddy	3
CUST-1255	Yuki Tanaka	4
CUST-1256	Carlos Muller	4
CUST-1257	Yuki Patel	2
CUST-1258	Fatima Sharma	2
CUST-1259	Emma Garcia	2
CUST-1260	Meera Iyer	3
CUST-1261	Anita Muller	4
CUST-1262	Arjun Nair	5
CUST-1263	Chen Iyer	2
CUST-1264	Chen Rossi	5
CUST-1265	Olivia Iyer	5
CUST-1266	Anita Nair	5
CUST-1267	Olivia Iyer	3
CUST-1268	Emma Patel	4
CUST-1269	Liam Sharma	2
CUST-1270	Ethan Sharma	4
CUST-1271	Anita Iyer	5
CUST-1272	Carlos Sharma	2
CUST-1273	John Garcia	5
CUST-1274	Liam Wang	5
CUST-1275	Carlos Singh	2
CUST-1276	Carlos Nair	1
CUST-1277	Yuki Brown	2
CUST-1278	Ethan Rossi	5
CUST-1279	Mia Muller	4
CUST-1280	Liam Sharma	2
CUST-1281	Emma Iyer	2
CUST-1282	Fatima Reddy	3
CUST-1283	Vikram Reddy	2
CUST-1284	Noah Garcia	1
CUST-1285	Chen Smith	2
CUST-1286	Sneha Sharma	3
CUST-1287	Aarav Singh	4
CUST-1288	Chen Brown	3
CUST-1289	Fatima Patel	3
CUST-1290	Priya Muller	1
CUST-1291	Rahul Sharma	2
CUST-1292	John Rossi	4
CUST-1293	Sophia Patel	2
CUST-1294	Carlos Muller	3
CUST-1295	Carlos Rossi	4
CUST-1296	Vikram Silva	5
CUST-1297	Arjun Muller	2
CUST-1298	Olivia Tanaka	1
CUST-1299	Noah Khan	2
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_items (item_id, order_id, product_id, quantity, unit_price, discount, source_line_id) FROM stdin;
1	53642	12	2	25.86	0.00	ORD-100000
2	51997	13	1	530.24	0.05	ORD-100001
3	51975	6	2	96.21	0.00	ORD-100002
4	51505	15	1	81.91	0.00	ORD-100003
5	55544	9	4	11.86	0.15	ORD-100004
6	53579	14	3	212.84	0.05	ORD-100005
7	55163	15	2	76.95	0.05	ORD-100006
8	51224	12	4	25.32	0.10	ORD-100007
9	54744	7	1	59.15	0.00	ORD-100008
10	52804	6	2	91.78	0.05	ORD-100009
11	54710	4	2	156.37	0.00	ORD-100010
12	54885	3	1	126.33	0.10	ORD-100011
13	51225	7	2	61.59	0.10	ORD-100012
14	50091	18	6	14.57	0.10	ORD-100013
15	53765	14	1	205.01	0.05	ORD-100014
16	55496	14	1	210.33	0.00	ORD-100015
17	52245	16	1	669.09	0.00	ORD-100016
18	54843	1	3	108.51	0.10	ORD-100017
19	54508	5	2	92.94	0.05	ORD-100018
20	54165	8	1	744.14	0.10	ORD-100019
21	50305	8	2	750.63	0.00	ORD-100020
22	53580	9	4	12.51	0.00	ORD-100021
23	53581	7	3	57.89	0.00	ORD-100022
24	50197	11	4	9.22	0.05	ORD-100023
25	54969	6	3	94.99	0.00	ORD-100024
26	51697	14	2	215.02	0.05	ORD-100026
27	50675	4	1	144.52	0.00	ORD-100027
28	55458	11	1	8.67	0.20	ORD-100028
29	54096	6	4	96.93	0.00	ORD-100029
30	52445	1	1	105.74	0.00	ORD-100030
31	54200	11	3	8.98	0.20	ORD-100031
32	53575	6	2	92.59	0.10	ORD-100032
33	50001	14	2	215.31	0.10	ORD-100033
34	53227	5	2	91.18	0.00	ORD-100034
35	52246	15	3	82.39	0.05	ORD-100035
36	53861	5	1	91.86	0.00	ORD-100036
37	50830	18	7	15.24	0.00	ORD-100037
38	51958	15	3	81.31	0.00	ORD-100038
39	54886	10	1	178.09	0.00	ORD-100039
40	54711	1	1	112.60	0.00	ORD-100040
41	50676	14	1	202.43	0.05	ORD-100041
42	52963	4	1	144.67	0.00	ORD-100042
43	51592	19	3	22.13	0.15	ORD-100043
44	53509	11	1	8.74	0.10	ORD-100044
45	54375	19	2	22.58	0.00	ORD-100045
46	52150	7	5	57.41	0.05	ORD-100046
47	53909	4	2	146.85	0.00	ORD-100047
48	51959	20	1	319.77	0.10	ORD-100048
49	53351	4	2	143.03	0.00	ORD-100049
50	51795	13	1	539.60	0.05	ORD-100050
51	50690	19	3	21.70	0.15	ORD-100051
52	53897	11	6	9.08	0.15	ORD-100052
53	54083	2	1	66.92	0.00	ORD-100053
54	54970	1	2	106.00	0.05	ORD-100054
55	55164	18	3	14.52	0.00	ORD-100055
56	54832	2	1	70.40	0.00	ORD-100056
57	54166	18	3	14.64	0.10	ORD-100057
58	54097	4	2	155.18	0.05	ORD-100058
59	55811	1	2	105.96	0.00	ORD-100059
60	55733	7	2	61.05	0.00	ORD-100060
61	53766	10	1	176.51	0.00	ORD-100061
62	55165	20	1	335.50	0.10	ORD-100062
63	55166	7	2	61.62	0.20	ORD-100063
64	50621	1	1	106.57	0.00	ORD-100064
65	55459	10	1	172.30	0.15	ORD-100065
66	55065	4	1	156.90	0.10	ORD-100066
67	54550	4	1	151.40	0.10	ORD-100067
68	53558	19	1	21.23	0.00	ORD-100068
69	54356	15	2	78.37	0.15	ORD-100069
70	53002	5	4	89.19	0.05	ORD-100070
71	55771	19	2	21.08	0.00	ORD-100071
72	52108	16	1	608.62	0.00	ORD-100072
73	54201	11	4	9.23	0.00	ORD-100073
74	55497	7	2	58.26	0.10	ORD-100074
75	52584	9	6	11.55	0.00	ORD-100075
76	52805	18	2	15.56	0.10	ORD-100076
77	50691	9	2	12.27	0.05	ORD-100077
78	50471	15	2	78.00	0.05	ORD-100078
79	53371	4	2	156.89	0.10	ORD-100079
80	54887	12	7	26.17	0.00	ORD-100080
81	55066	11	3	8.78	0.05	ORD-100081
82	51820	14	1	217.97	0.15	ORD-100082
83	52417	14	3	205.60	0.00	ORD-100083
84	53643	5	2	91.00	0.15	ORD-100084
85	50227	15	2	81.08	0.10	ORD-100085
86	54419	7	1	61.19	0.05	ORD-100086
87	53582	2	1	70.75	0.00	ORD-100087
88	51226	14	1	213.29	0.10	ORD-100088
89	50400	18	6	14.61	0.20	ORD-100089
90	53644	2	2	68.59	0.05	ORD-100090
91	54759	12	4	24.01	0.15	ORD-100091
92	55167	17	1	414.06	0.00	ORD-100092
93	55167	10	1	181.65	0.05	ORD-100093
94	53486	13	1	531.47	0.20	ORD-100094
95	53937	7	1	58.68	0.00	ORD-100095
96	51667	4	1	143.66	0.00	ORD-100096
97	54339	2	2	69.06	0.10	ORD-100097
98	52119	7	2	58.21	0.15	ORD-100098
99	55772	20	1	326.63	0.00	ORD-100099
100	50002	7	3	58.26	0.00	ORD-100100
101	51227	7	1	60.90	0.15	ORD-100101
102	55591	2	2	73.01	0.10	ORD-100102
103	50947	18	5	15.67	0.00	ORD-100103
104	55168	9	4	12.41	0.20	ORD-100104
105	52895	19	1	23.08	0.00	ORD-100105
106	50885	2	2	69.38	0.00	ORD-100106
107	53372	3	1	132.48	0.00	ORD-100107
108	51205	6	3	95.36	0.10	ORD-100108
109	51593	17	2	408.72	0.10	ORD-100109
110	50092	4	2	145.18	0.00	ORD-100110
111	52247	20	1	328.12	0.00	ORD-100111
112	50831	4	4	148.16	0.05	ORD-100112
113	55152	11	3	8.90	0.00	ORD-100113
114	53398	10	1	177.01	0.05	ORD-100114
115	53583	6	2	98.02	0.00	ORD-100115
116	50832	9	1	11.94	0.10	ORD-100116
117	52806	10	1	173.09	0.00	ORD-100117
118	53876	2	2	73.26	0.15	ORD-100118
119	50112	8	4	785.56	0.10	ORD-100119
120	55460	10	1	176.11	0.00	ORD-100120
121	52126	20	1	345.19	0.15	ORD-100121
122	50198	2	1	71.96	0.00	ORD-100122
123	53080	8	1	725.31	0.05	ORD-100123
124	52485	14	1	218.52	0.10	ORD-100124
125	53924	8	1	728.74	0.10	ORD-100125
126	50285	1	2	111.61	0.05	ORD-100126
127	53228	5	1	92.57	0.00	ORD-100127
128	50228	12	2	24.08	0.05	ORD-100129
129	52224	9	5	12.39	0.05	ORD-100130
130	51129	11	5	8.92	0.10	ORD-100131
131	55169	1	1	110.44	0.00	ORD-100132
132	55425	19	2	21.05	0.00	ORD-100133
133	50833	18	4	14.61	0.05	ORD-100134
134	55170	19	1	21.81	0.00	ORD-100135
135	52556	16	1	614.84	0.05	ORD-100136
136	53938	14	2	202.64	0.15	ORD-100137
137	55658	16	1	614.85	0.00	ORD-100138
138	53487	11	6	9.13	0.00	ORD-100139
139	53584	12	4	25.71	0.00	ORD-100140
140	51835	2	3	72.62	0.00	ORD-100141
141	53373	15	1	82.13	0.10	ORD-100142
142	54712	8	2	773.89	0.05	ORD-100143
143	50088	17	1	428.41	0.00	ORD-100144
144	52151	14	1	204.84	0.20	ORD-100145
145	50060	3	1	133.61	0.00	ORD-100146
146	50517	2	2	72.43	0.05	ORD-100147
147	50767	10	3	172.77	0.10	ORD-100148
148	54760	18	5	14.34	0.15	ORD-100149
149	52457	11	4	9.33	0.00	ORD-100150
150	51698	10	1	174.93	0.05	ORD-100151
151	55507	13	1	499.57	0.15	ORD-100152
152	50113	5	1	92.44	0.00	ORD-100153
153	50790	19	2	22.38	0.05	ORD-100154
154	52855	4	1	155.84	0.00	ORD-100155
155	55171	14	1	202.33	0.00	ORD-100156
156	51206	18	4	15.71	0.00	ORD-100157
157	50948	7	2	59.54	0.15	ORD-100158
158	50692	6	2	97.96	0.00	ORD-100159
159	50834	12	4	24.52	0.00	ORD-100160
160	53510	8	4	773.99	0.00	ORD-100161
161	52722	12	3	24.84	0.10	ORD-100162
162	52051	16	2	658.71	0.15	ORD-100163
163	55172	11	2	9.31	0.00	ORD-100164
164	52589	11	4	9.02	0.00	ORD-100165
165	55797	6	2	95.62	0.00	ORD-100166
166	53488	8	2	749.42	0.05	ORD-100167
167	53461	20	1	324.65	0.10	ORD-100168
168	55067	3	1	126.21	0.00	ORD-100169
169	55752	11	4	8.87	0.20	ORD-100170
170	51836	13	1	509.65	0.00	ORD-100171
171	53849	2	1	68.83	0.05	ORD-100172
172	50047	5	1	89.88	0.05	ORD-100173
173	54167	17	2	404.36	0.20	ORD-100174
174	54509	14	1	203.85	0.00	ORD-100175
175	54551	8	1	748.95	0.00	ORD-100176
176	53134	1	2	112.02	0.05	ORD-100177
177	54464	19	3	22.88	0.15	ORD-100178
178	50212	11	6	8.64	0.00	ORD-100179
179	53347	17	1	414.10	0.15	ORD-100180
180	54686	14	1	200.12	0.05	ORD-100181
181	52052	6	2	94.80	0.00	ORD-100182
182	55129	5	3	92.85	0.00	ORD-100183
183	53710	12	2	25.90	0.00	ORD-100184
184	55773	5	1	90.77	0.00	ORD-100185
185	55130	12	3	26.25	0.15	ORD-100186
186	50093	8	1	783.05	0.00	ORD-100187
187	51837	8	2	714.92	0.10	ORD-100188
188	53374	13	2	497.14	0.10	ORD-100189
189	53003	18	2	15.48	0.00	ORD-100190
190	55069	15	1	80.36	0.10	ORD-100191
191	55068	6	3	96.94	0.00	ORD-100192
192	53877	14	2	204.98	0.00	ORD-100193
193	51699	20	2	327.44	0.15	ORD-100194
194	54971	14	2	202.65	0.05	ORD-100195
195	54202	17	1	407.45	0.00	ORD-100197
196	54332	13	2	516.62	0.15	ORD-100198
197	50472	14	1	203.49	0.15	ORD-100199
198	51351	15	2	77.47	0.05	ORD-100200
199	52964	12	7	25.50	0.05	ORD-100201
200	51742	12	4	26.12	0.00	ORD-100202
201	52152	12	5	26.10	0.00	ORD-100203
202	53711	10	1	175.45	0.05	ORD-100204
203	52127	6	1	97.93	0.00	ORD-100205
204	51182	4	1	153.02	0.15	ORD-100206
205	50229	20	1	344.24	0.10	ORD-100207
206	50949	6	3	96.99	0.00	ORD-100208
207	54844	11	4	8.75	0.00	ORD-100209
208	50114	16	3	648.55	0.00	ORD-100210
209	54844	14	3	207.90	0.05	ORD-100211
210	52948	11	3	9.16	0.00	ORD-100212
211	54972	12	3	23.79	0.15	ORD-100213
212	51796	20	1	321.36	0.05	ORD-100214
213	52153	15	1	76.55	0.20	ORD-100215
214	53135	20	2	323.41	0.00	ORD-100216
215	54888	15	2	78.24	0.00	ORD-100217
216	51998	1	1	114.72	0.00	ORD-100218
217	52590	13	2	531.24	0.00	ORD-100219
218	55508	7	1	59.55	0.00	ORD-100220
219	55070	11	5	9.43	0.00	ORD-100221
220	50444	15	2	77.90	0.05	ORD-100222
221	55694	7	2	58.47	0.00	ORD-100223
222	55805	1	1	112.37	0.05	ORD-100224
223	52692	2	1	72.51	0.00	ORD-100225
224	54606	11	6	8.56	0.05	ORD-100226
225	55592	13	1	504.70	0.10	ORD-100227
226	50115	3	1	129.16	0.05	ORD-100228
227	52381	1	1	107.04	0.00	ORD-100229
228	54837	4	1	148.97	0.10	ORD-100230
229	51838	8	1	720.06	0.00	ORD-100231
230	52007	7	1	62.95	0.05	ORD-100232
231	54138	6	1	94.07	0.00	ORD-100233
232	55173	13	1	533.59	0.00	ORD-100234
233	50230	15	1	83.22	0.00	ORD-100235
234	54973	8	1	764.24	0.05	ORD-100236
235	55701	13	1	501.95	0.10	ORD-100237
236	54889	4	2	156.26	0.05	ORD-100238
237	51743	17	2	421.87	0.00	ORD-100239
238	55174	15	3	77.34	0.00	ORD-100240
239	51821	1	1	106.01	0.00	ORD-100241
240	50752	5	1	92.86	0.15	ORD-100242
241	52311	9	6	12.47	0.05	ORD-100243
242	51976	2	1	68.17	0.10	ORD-100244
243	53585	1	1	112.57	0.00	ORD-100245
244	53375	11	4	9.14	0.00	ORD-100246
245	54203	15	2	83.77	0.15	ORD-100247
246	51613	16	1	664.88	0.00	ORD-100248
247	52506	5	1	93.60	0.05	ORD-100249
248	50886	13	2	504.13	0.10	ORD-100250
249	51207	3	1	128.19	0.20	ORD-100251
250	50950	17	1	416.32	0.00	ORD-100252
251	50602	14	2	206.49	0.00	ORD-100253
252	51413	17	2	409.57	0.00	ORD-100254
253	54357	12	5	24.97	0.10	ORD-100255
254	54761	11	3	8.92	0.00	ORD-100256
255	53939	6	1	97.88	0.00	ORD-100257
256	51386	7	2	61.79	0.00	ORD-100258
257	52300	1	1	113.90	0.00	ORD-100259
258	53352	11	4	9.38	0.00	ORD-100260
259	55426	4	2	149.71	0.00	ORD-100261
260	54838	4	3	146.92	0.05	ORD-100263
261	55175	3	1	130.37	0.00	ORD-100264
262	51228	2	2	72.54	0.00	ORD-100265
263	54049	13	2	511.95	0.05	ORD-100266
264	55774	12	4	24.03	0.00	ORD-100267
265	54010	14	2	215.85	0.00	ORD-100268
266	54890	19	1	22.29	0.05	ORD-100269
267	51117	9	5	11.41	0.00	ORD-100270
268	55775	18	3	15.26	0.20	ORD-100271
269	52896	16	3	659.82	0.00	ORD-100272
270	55553	8	1	751.75	0.05	ORD-100273
271	51229	12	8	24.71	0.05	ORD-100274
272	54845	9	3	11.66	0.05	ORD-100275
273	53415	20	1	327.52	0.00	ORD-100276
274	55612	4	1	144.94	0.00	ORD-100277
275	53462	2	2	73.42	0.00	ORD-100278
276	50445	20	1	324.05	0.00	ORD-100279
277	52683	15	1	80.32	0.00	ORD-100280
278	50951	14	2	215.64	0.00	ORD-100281
279	52458	14	1	200.10	0.10	ORD-100282
280	55177	2	2	73.27	0.15	ORD-100283
281	55176	4	1	143.18	0.10	ORD-100284
282	52897	10	1	185.91	0.00	ORD-100285
283	53122	1	2	114.50	0.10	ORD-100286
284	52323	12	6	25.42	0.20	ORD-100287
285	54812	14	2	200.11	0.15	ORD-100288
286	54420	10	1	180.74	0.00	ORD-100289
287	52529	19	2	22.75	0.00	ORD-100290
288	52248	4	1	144.82	0.10	ORD-100291
289	51341	19	2	22.09	0.00	ORD-100292
290	53645	11	5	8.97	0.00	ORD-100293
291	50306	14	2	217.02	0.20	ORD-100294
292	50768	12	6	25.31	0.05	ORD-100295
293	50887	1	2	114.47	0.15	ORD-100296
294	52548	12	4	24.95	0.00	ORD-100297
295	54168	16	1	622.61	0.05	ORD-100298
296	54607	4	1	153.38	0.00	ORD-100299
297	52693	4	2	147.65	0.00	ORD-100300
298	52324	1	2	111.35	0.15	ORD-100301
299	54141	1	1	104.58	0.00	ORD-100302
300	50116	6	1	98.54	0.15	ORD-100303
301	54376	2	2	69.29	0.00	ORD-100304
302	50952	14	1	204.68	0.20	ORD-100305
303	55153	8	1	752.00	0.05	ORD-100306
304	55053	6	4	92.54	0.00	ORD-100307
305	52898	4	1	153.81	0.00	ORD-100308
306	55178	20	3	316.15	0.15	ORD-100309
307	55179	12	4	26.01	0.10	ORD-100310
308	53353	14	2	210.69	0.00	ORD-100311
309	52364	7	2	59.10	0.05	ORD-100312
310	50693	20	1	341.64	0.20	ORD-100313
311	50401	9	6	12.47	0.10	ORD-100314
312	54974	11	3	9.18	0.15	ORD-100315
313	51628	6	1	93.16	0.05	ORD-100316
314	52636	9	4	12.49	0.20	ORD-100317
315	53646	16	2	641.00	0.15	ORD-100318
316	52557	2	1	72.92	0.00	ORD-100319
317	50383	11	2	9.02	0.00	ORD-100320
318	54817	13	1	496.83	0.00	ORD-100322
319	54142	12	3	24.80	0.00	ORD-100323
320	52249	1	1	107.01	0.00	ORD-100324
321	51769	18	3	14.69	0.10	ORD-100325
322	55071	11	5	9.36	0.20	ORD-100326
323	55593	6	1	97.99	0.00	ORD-100327
324	52250	15	3	82.30	0.10	ORD-100328
325	54975	9	2	12.36	0.10	ORD-100329
326	50466	11	4	9.19	0.00	ORD-100330
327	55427	8	2	777.46	0.00	ORD-100331
328	55180	13	1	522.43	0.05	ORD-100332
329	53004	3	2	126.49	0.00	ORD-100333
330	52298	15	1	78.23	0.05	ORD-100334
331	50597	3	1	131.73	0.05	ORD-100335
332	53586	13	1	522.46	0.20	ORD-100336
333	50791	16	2	647.06	0.00	ORD-100337
334	54762	8	1	746.14	0.00	ORD-100338
335	52591	16	5	637.03	0.00	ORD-100339
336	52637	19	2	21.81	0.00	ORD-100340
337	54421	2	2	73.08	0.05	ORD-100341
338	55181	11	8	8.64	0.00	ORD-100342
339	53647	7	2	57.64	0.00	ORD-100343
340	53783	3	1	132.36	0.00	ORD-100344
341	53354	9	6	12.05	0.00	ORD-100345
342	51362	18	1	15.50	0.00	ORD-100346
343	51839	1	2	113.38	0.10	ORD-100347
344	55182	2	2	67.70	0.00	ORD-100348
345	50307	11	4	8.56	0.10	ORD-100349
346	55753	6	2	95.55	0.15	ORD-100350
347	54460	11	3	8.77	0.00	ORD-100351
348	53299	10	1	184.19	0.00	ORD-100352
349	54340	14	2	219.29	0.05	ORD-100353
350	52558	20	2	332.64	0.00	ORD-100354
351	54287	7	3	62.46	0.00	ORD-100355
352	55498	13	2	515.36	0.05	ORD-100356
353	50953	2	3	73.30	0.00	ORD-100357
354	55509	12	4	25.58	0.00	ORD-100358
355	52899	20	1	336.96	0.05	ORD-100359
356	51789	11	2	8.64	0.10	ORD-100360
357	50694	10	1	172.88	0.00	ORD-100361
358	55554	5	3	93.30	0.15	ORD-100362
359	51183	11	5	8.81	0.05	ORD-100363
360	51629	4	1	147.66	0.20	ORD-100364
361	54590	4	1	143.59	0.10	ORD-100365
362	51184	3	1	124.85	0.05	ORD-100366
363	54891	16	1	651.12	0.00	ORD-100367
364	51143	13	2	530.11	0.00	ORD-100368
365	52411	19	1	21.72	0.15	ORD-100369
366	50308	2	1	70.62	0.10	ORD-100370
367	50117	1	1	111.39	0.00	ORD-100371
368	54377	17	1	399.90	0.20	ORD-100372
369	50835	15	2	81.39	0.00	ORD-100373
370	50571	3	1	127.51	0.00	ORD-100374
371	53940	11	5	9.21	0.20	ORD-100375
372	51960	17	2	408.62	0.00	ORD-100376
373	51185	13	3	537.92	0.15	ORD-100377
374	50003	13	1	538.01	0.00	ORD-100378
375	51154	4	1	143.56	0.05	ORD-100379
376	51414	12	4	24.52	0.00	ORD-100380
377	53136	14	1	211.16	0.00	ORD-100381
378	53416	12	4	25.25	0.15	ORD-100382
379	55461	18	5	15.00	0.00	ORD-100383
380	54976	13	1	536.32	0.00	ORD-100384
381	55183	11	4	9.14	0.00	ORD-100385
382	51614	7	3	62.81	0.00	ORD-100386
383	55575	17	1	407.37	0.15	ORD-100387
384	54422	16	1	670.06	0.00	ORD-100388
385	55184	18	6	15.04	0.10	ORD-100389
386	52233	8	1	778.43	0.00	ORD-100390
387	52856	19	1	22.56	0.00	ORD-100391
388	55185	13	1	526.04	0.20	ORD-100392
389	51130	18	3	15.16	0.00	ORD-100393
390	53417	1	2	113.93	0.00	ORD-100394
391	52900	10	2	183.84	0.15	ORD-100395
392	55807	12	4	24.73	0.05	ORD-100396
393	54593	2	2	70.97	0.05	ORD-100397
394	50695	20	1	329.90	0.05	ORD-100398
395	54378	7	3	60.60	0.00	ORD-100399
396	50888	16	1	610.99	0.10	ORD-100400
397	53138	2	1	71.49	0.00	ORD-100401
398	53587	14	1	212.06	0.00	ORD-100402
399	53137	19	2	22.88	0.00	ORD-100403
400	55186	18	5	14.54	0.00	ORD-100404
401	51840	12	2	25.46	0.00	ORD-100405
402	53941	9	2	12.03	0.00	ORD-100406
403	53418	19	2	23.02	0.10	ORD-100407
404	51387	13	2	504.10	0.20	ORD-100408
405	54608	5	1	94.05	0.00	ORD-100409
406	52807	18	4	15.70	0.05	ORD-100410
407	50696	5	1	90.63	0.05	ORD-100411
408	53862	16	1	610.90	0.00	ORD-100412
409	51149	3	1	131.97	0.05	ORD-100413
410	51841	9	4	11.67	0.05	ORD-100414
411	52965	17	1	415.73	0.05	ORD-100415
412	53229	17	1	434.38	0.00	ORD-100416
413	54318	9	5	12.04	0.05	ORD-100417
414	51415	4	1	143.96	0.00	ORD-100418
415	55187	19	1	22.45	0.00	ORD-100419
416	54011	6	2	90.98	0.00	ORD-100420
417	51770	8	2	723.62	0.00	ORD-100421
418	55189	10	3	180.65	0.10	ORD-100422
419	55188	1	2	105.24	0.00	ORD-100423
420	55742	7	2	60.51	0.00	ORD-100424
421	55188	20	1	316.65	0.05	ORD-100425
422	52638	17	1	423.80	0.05	ORD-100426
423	54846	12	5	25.07	0.00	ORD-100427
424	54524	8	2	758.09	0.00	ORD-100428
425	50792	4	1	152.85	0.00	ORD-100429
426	50004	9	3	12.46	0.00	ORD-100430
427	53230	13	1	519.55	0.00	ORD-100431
428	55054	3	1	128.62	0.00	ORD-100432
429	55576	14	1	216.32	0.00	ORD-100433
430	50005	11	5	9.44	0.00	ORD-100434
431	54609	2	5	70.20	0.00	ORD-100435
432	52008	18	4	15.15	0.20	ORD-100436
433	54139	18	5	15.56	0.00	ORD-100437
434	50753	17	1	413.65	0.00	ORD-100438
435	51186	15	5	77.93	0.00	ORD-100439
436	53712	17	3	415.11	0.00	ORD-100440
437	55190	11	4	9.42	0.10	ORD-100441
438	52312	14	2	213.88	0.05	ORD-100442
439	54763	2	3	72.77	0.00	ORD-100443
440	54594	20	1	320.84	0.10	ORD-100444
441	50697	15	1	78.85	0.05	ORD-100445
442	50402	18	5	15.11	0.00	ORD-100446
443	51977	11	2	8.93	0.10	ORD-100447
444	50889	18	6	14.61	0.00	ORD-100448
445	52154	17	2	424.65	0.00	ORD-100449
446	54764	4	1	154.70	0.05	ORD-100450
447	53231	19	4	21.46	0.05	ORD-100451
448	55191	19	1	21.15	0.00	ORD-100452
449	54892	10	1	172.87	0.05	ORD-100453
450	54977	6	2	98.24	0.00	ORD-100454
451	52901	16	1	616.73	0.00	ORD-100455
452	51842	2	1	72.68	0.00	ORD-100456
453	52684	1	2	113.92	0.05	ORD-100457
454	54525	13	4	503.04	0.00	ORD-100458
455	50473	14	2	202.64	0.10	ORD-100459
456	50698	1	2	107.54	0.00	ORD-100460
457	53081	11	4	8.80	0.10	ORD-100461
458	53713	12	3	24.29	0.05	ORD-100462
459	52639	5	1	92.25	0.05	ORD-100463
460	51388	9	2	11.89	0.05	ORD-100465
461	50890	12	2	26.14	0.05	ORD-100466
462	51493	3	1	133.33	0.00	ORD-100467
463	53784	1	2	104.58	0.00	ORD-100468
464	50534	2	1	67.06	0.00	ORD-100469
465	52902	19	4	21.88	0.10	ORD-100470
466	51822	13	1	511.79	0.00	ORD-100471
467	52424	8	1	741.57	0.00	ORD-100472
468	55734	17	1	440.83	0.00	ORD-100473
469	51363	15	3	80.01	0.10	ORD-100474
470	52507	11	4	8.64	0.15	ORD-100475
471	54063	12	5	24.84	0.00	ORD-100476
472	53082	12	3	25.31	0.05	ORD-100477
473	55428	16	1	666.79	0.00	ORD-100478
474	55735	12	2	24.09	0.00	ORD-100479
475	52128	14	1	201.00	0.05	ORD-100480
476	52009	16	1	650.25	0.00	ORD-100481
477	54847	1	2	107.21	0.05	ORD-100482
478	50818	2	2	68.51	0.05	ORD-100483
479	54699	12	2	25.14	0.00	ORD-100484
480	50213	18	4	15.16	0.05	ORD-100485
481	52857	1	3	104.52	0.05	ORD-100486
482	55510	10	1	185.42	0.00	ORD-100487
483	52733	9	2	12.05	0.10	ORD-100488
484	52903	14	1	200.55	0.00	ORD-100489
485	53942	15	1	77.28	0.15	ORD-100490
486	52640	7	1	62.47	0.00	ORD-100491
487	54573	11	2	9.26	0.05	ORD-100492
488	54818	11	2	9.19	0.00	ORD-100493
489	50891	5	1	93.52	0.00	ORD-100494
490	50048	9	2	11.67	0.10	ORD-100495
491	51771	3	1	128.32	0.00	ORD-100496
492	50061	3	2	131.19	0.00	ORD-100498
493	50954	20	1	329.54	0.10	ORD-100499
494	55192	15	5	79.09	0.15	ORD-100500
495	55555	14	2	202.30	0.00	ORD-100501
496	51405	1	1	112.07	0.15	ORD-100502
497	52627	19	2	21.64	0.10	ORD-100503
498	55702	16	1	651.52	0.00	ORD-100504
499	50118	4	2	150.39	0.15	ORD-100505
500	55193	7	2	59.65	0.00	ORD-100506
501	54012	14	1	219.66	0.10	ORD-100507
502	50769	1	1	104.96	0.00	ORD-100508
503	52010	8	1	731.87	0.00	ORD-100509
504	50793	15	2	83.60	0.10	ORD-100510
505	50094	5	1	90.24	0.00	ORD-100511
506	51610	3	1	127.95	0.00	ORD-100512
507	53898	18	4	15.46	0.05	ORD-100514
508	50309	17	1	405.06	0.00	ORD-100515
509	55511	10	1	175.42	0.00	ORD-100516
510	51506	19	5	23.06	0.10	ORD-100517
511	51630	14	1	209.24	0.00	ORD-100518
512	52155	19	1	21.88	0.00	ORD-100519
513	50836	20	1	342.36	0.10	ORD-100520
514	53785	5	1	89.21	0.20	ORD-100521
515	50770	1	1	110.43	0.00	ORD-100522
516	50119	2	1	67.87	0.15	ORD-100523
517	53232	7	2	60.27	0.10	ORD-100524
518	54341	3	2	124.70	0.05	ORD-100525
519	50644	2	1	71.43	0.00	ORD-100526
520	52325	19	2	21.29	0.00	ORD-100527
521	52011	13	2	497.59	0.10	ORD-100528
522	54713	20	1	325.26	0.00	ORD-100529
523	53511	4	2	157.37	0.15	ORD-100530
524	51631	17	1	400.69	0.00	ORD-100531
525	53108	12	8	24.17	0.05	ORD-100533
526	53786	12	2	23.98	0.00	ORD-100534
527	54423	17	1	400.64	0.00	ORD-100535
528	53233	7	3	61.70	0.15	ORD-100536
529	51406	3	1	136.11	0.05	ORD-100537
530	50062	15	2	81.67	0.15	ORD-100538
531	53111	19	3	22.06	0.00	ORD-100539
532	52251	1	1	110.98	0.00	ORD-100540
533	53787	4	1	149.36	0.15	ORD-100541
534	54333	9	4	11.49	0.05	ORD-100542
535	55455	5	1	89.86	0.10	ORD-100543
536	53715	8	1	766.87	0.05	ORD-100544
537	54143	14	1	219.52	0.10	ORD-100545
538	50120	13	3	539.52	0.05	ORD-100546
539	50518	19	3	22.27	0.05	ORD-100547
540	53714	5	3	89.17	0.00	ORD-100548
541	50049	12	5	25.87	0.05	ORD-100549
542	50006	3	1	135.31	0.00	ORD-100550
543	53943	12	2	24.14	0.20	ORD-100551
544	55194	6	2	95.16	0.00	ORD-100552
545	50955	14	2	204.95	0.00	ORD-100553
546	53300	11	4	8.66	0.00	ORD-100554
547	51494	10	2	185.18	0.00	ORD-100555
548	50956	6	1	92.46	0.00	ORD-100556
549	51416	8	1	777.84	0.15	ORD-100557
550	55429	7	2	60.29	0.10	ORD-100558
551	50955	14	2	219.92	0.00	ORD-100559
552	51797	1	1	111.31	0.00	ORD-100560
553	54379	15	1	79.89	0.00	ORD-100561
554	54893	18	6	15.06	0.20	ORD-100562
555	51632	8	1	745.97	0.15	ORD-100563
556	51843	19	3	21.51	0.00	ORD-100564
557	55195	4	1	144.06	0.10	ORD-100565
558	50699	16	1	644.63	0.05	ORD-100566
559	51732	8	1	737.68	0.00	ORD-100567
560	54978	2	4	70.12	0.05	ORD-100568
561	55577	18	5	15.22	0.00	ORD-100569
562	55812	17	1	404.66	0.15	ORD-100570
563	53540	5	4	93.61	0.10	ORD-100571
564	52211	12	4	25.24	0.15	ORD-100572
565	54448	5	2	94.47	0.05	ORD-100573
566	54978	7	3	57.06	0.15	ORD-100574
567	54595	2	1	72.39	0.00	ORD-100575
568	53355	6	1	97.02	0.00	ORD-100576
569	50572	3	2	125.22	0.00	ORD-100577
570	55196	15	3	82.99	0.05	ORD-100578
571	54424	12	1	26.06	0.00	ORD-100579
572	55635	1	2	113.74	0.00	ORD-100580
573	55072	15	2	78.41	0.10	ORD-100581
574	52425	19	3	22.46	0.20	ORD-100582
575	53716	7	2	58.75	0.20	ORD-100583
576	53301	13	1	503.59	0.10	ORD-100584
577	50427	8	2	770.97	0.05	ORD-100585
578	50446	2	1	73.06	0.00	ORD-100586
579	54591	4	2	146.91	0.05	ORD-100587
580	55197	11	5	8.73	0.10	ORD-100588
581	52641	5	1	94.01	0.00	ORD-100589
582	53083	15	2	82.94	0.10	ORD-100590
583	53648	2	3	68.56	0.00	ORD-100591
584	50957	8	2	765.74	0.10	ORD-100592
585	54596	14	1	213.89	0.00	ORD-100593
586	55198	17	1	430.41	0.10	ORD-100594
587	55727	3	1	133.32	0.10	ORD-100595
588	55199	16	1	668.87	0.00	ORD-100596
589	50007	12	4	25.57	0.05	ORD-100597
590	51576	15	1	83.01	0.20	ORD-100598
591	53717	20	1	317.44	0.00	ORD-100599
592	53139	20	1	319.86	0.10	ORD-100600
593	52559	4	3	155.77	0.05	ORD-100601
594	51576	10	2	175.01	0.05	ORD-100602
595	53878	14	1	219.82	0.05	ORD-100603
596	51575	18	3	14.84	0.00	ORD-100604
597	54144	20	1	322.38	0.20	ORD-100605
598	53112	6	2	98.19	0.05	ORD-100606
599	52234	13	1	531.44	0.00	ORD-100607
600	54765	16	1	632.68	0.00	ORD-100608
601	52129	7	2	59.81	0.05	ORD-100609
602	51844	14	1	209.00	0.00	ORD-100610
603	51155	8	3	715.18	0.00	ORD-100611
604	50892	11	6	8.86	0.10	ORD-100612
605	55200	6	3	91.87	0.00	ORD-100614
606	51417	16	2	631.30	0.20	ORD-100615
607	53788	2	2	71.35	0.15	ORD-100616
608	52748	16	1	643.05	0.10	ORD-100617
609	55594	20	1	319.47	0.00	ORD-100618
610	53419	14	1	210.12	0.00	ORD-100619
611	53356	11	4	8.99	0.00	ORD-100620
612	54894	11	2	8.71	0.10	ORD-100621
613	52426	3	1	130.58	0.10	ORD-100623
614	54380	20	1	321.03	0.00	ORD-100624
615	54979	7	1	62.61	0.15	ORD-100625
616	54425	20	1	326.79	0.15	ORD-100626
617	55201	1	1	105.64	0.05	ORD-100627
618	51507	13	2	509.37	0.00	ORD-100628
619	53789	4	1	149.28	0.00	ORD-100629
620	53234	17	1	415.43	0.00	ORD-100630
621	52585	3	1	128.21	0.20	ORD-100631
622	54610	18	3	14.45	0.05	ORD-100632
623	55512	8	1	721.22	0.00	ORD-100633
624	52949	8	1	769.26	0.00	ORD-100634
625	52554	19	2	22.51	0.10	ORD-100635
626	54461	5	3	87.82	0.05	ORD-100636
627	54848	9	5	12.00	0.10	ORD-100637
628	54449	9	5	11.44	0.10	ORD-100638
629	52035	14	2	204.99	0.10	ORD-100639
630	53005	15	2	82.44	0.00	ORD-100640
631	50622	18	4	15.71	0.15	ORD-100641
632	52904	9	7	12.46	0.00	ORD-100642
633	50050	18	4	14.86	0.00	ORD-100643
634	55202	20	1	335.10	0.00	ORD-100644
635	52308	7	3	62.52	0.00	ORD-100645
636	54552	6	1	97.77	0.00	ORD-100646
637	51508	14	4	202.92	0.10	ORD-100647
638	51823	12	3	25.68	0.00	ORD-100648
639	51823	4	1	156.55	0.10	ORD-100649
640	52053	18	2	15.61	0.00	ORD-100650
641	55055	10	1	182.87	0.20	ORD-100651
642	50121	11	5	8.59	0.00	ORD-100652
643	52826	20	2	343.84	0.00	ORD-100653
644	51509	9	6	11.91	0.15	ORD-100654
645	51418	3	1	132.17	0.20	ORD-100655
646	53140	5	1	89.40	0.00	ORD-100656
647	52774	19	1	23.09	0.10	ORD-100657
648	52459	14	1	212.79	0.20	ORD-100658
649	54714	10	1	171.98	0.00	ORD-100659
650	55073	10	1	185.96	0.00	ORD-100660
651	53141	2	1	69.02	0.15	ORD-100661
652	50893	11	5	9.09	0.05	ORD-100662
653	50008	18	2	15.62	0.00	ORD-100663
654	53790	13	2	503.69	0.15	ORD-100664
655	54116	1	1	113.39	0.10	ORD-100665
656	50009	9	4	11.74	0.10	ORD-100666
657	50403	2	1	67.47	0.00	ORD-100667
658	53235	6	2	94.03	0.00	ORD-100668
659	51633	5	3	87.80	0.05	ORD-100669
660	54673	2	1	73.14	0.05	ORD-100670
661	53236	20	1	329.97	0.00	ORD-100671
662	51230	19	2	22.73	0.15	ORD-100672
663	52787	1	1	111.21	0.10	ORD-100673
664	52694	20	1	329.87	0.10	ORD-100674
665	53006	15	2	80.00	0.05	ORD-100675
666	53767	2	1	70.27	0.05	ORD-100676
667	52054	18	4	14.42	0.15	ORD-100677
668	55203	13	2	534.63	0.10	ORD-100678
669	50958	14	1	212.97	0.05	ORD-100679
670	54980	4	1	154.74	0.15	ORD-100680
671	52156	2	1	72.10	0.10	ORD-100681
672	55203	16	1	630.04	0.00	ORD-100682
673	54981	12	1	25.66	0.10	ORD-100683
674	54553	8	1	749.22	0.00	ORD-100684
675	53420	18	4	15.55	0.00	ORD-100685
676	53718	19	3	22.62	0.05	ORD-100686
677	51510	9	5	12.51	0.20	ORD-100687
678	53879	13	2	500.26	0.00	ORD-100688
679	53768	3	2	133.88	0.05	ORD-100689
680	51978	4	1	152.21	0.05	ORD-100690
681	51389	9	9	11.62	0.00	ORD-100691
682	53421	11	5	8.81	0.00	ORD-100692
683	52905	18	3	15.55	0.00	ORD-100693
684	52734	8	2	712.72	0.10	ORD-100694
685	55074	18	3	14.76	0.00	ORD-100695
686	51231	15	3	80.88	0.05	ORD-100696
687	50122	16	1	671.39	0.00	ORD-100697
688	50535	12	3	23.88	0.00	ORD-100698
689	54381	10	1	181.42	0.05	ORD-100699
690	51231	8	1	740.76	0.00	ORD-100700
691	53302	10	1	187.54	0.05	ORD-100701
692	51419	6	4	90.74	0.15	ORD-100702
693	52544	1	1	111.31	0.10	ORD-100703
694	50700	7	3	59.23	0.10	ORD-100704
695	50123	12	5	24.02	0.00	ORD-100705
696	52036	6	2	96.21	0.05	ORD-100706
697	54597	9	6	11.94	0.10	ORD-100707
698	50123	18	5	14.42	0.15	ORD-100708
699	50123	9	4	12.32	0.05	ORD-100709
700	54013	10	1	173.92	0.00	ORD-100710
701	51420	15	2	78.00	0.00	ORD-100711
702	52427	3	1	124.53	0.05	ORD-100712
703	52858	18	6	14.41	0.15	ORD-100713
704	52252	13	1	541.30	0.00	ORD-100714
705	53649	11	5	9.16	0.00	ORD-100715
706	53237	17	1	406.95	0.05	ORD-100716
707	54169	11	2	9.14	0.20	ORD-100717
708	50124	1	1	106.27	0.10	ORD-100718
709	53850	10	1	186.82	0.00	ORD-100719
710	53109	6	3	96.71	0.00	ORD-100720
711	50063	19	1	22.23	0.10	ORD-100721
712	53588	20	2	325.40	0.00	ORD-100722
713	54510	11	4	9.17	0.05	ORD-100723
714	53899	3	1	129.61	0.05	ORD-100724
715	52369	19	3	21.30	0.15	ORD-100725
716	50677	3	2	126.10	0.05	ORD-100726
717	51700	12	3	25.46	0.00	ORD-100727
718	54426	19	4	22.09	0.05	ORD-100728
719	52723	14	1	207.52	0.10	ORD-100729
720	54288	10	1	181.97	0.00	ORD-100730
721	52592	2	1	70.93	0.00	ORD-100731
722	51687	10	1	180.50	0.10	ORD-100732
723	53399	9	7	11.47	0.05	ORD-100733
724	55663	20	1	327.21	0.05	ORD-100734
725	51634	4	2	143.60	0.05	ORD-100735
726	55724	14	1	217.30	0.00	ORD-100736
727	55677	15	2	77.88	0.15	ORD-100737
728	55813	10	1	177.25	0.00	ORD-100738
729	54520	5	1	86.48	0.05	ORD-100739
730	54289	19	2	21.91	0.15	ORD-100740
731	50814	12	3	25.99	0.00	ORD-100741
732	52642	1	3	114.46	0.10	ORD-100742
733	54674	10	1	184.36	0.05	ORD-100743
734	55204	4	2	143.10	0.00	ORD-100744
735	52301	7	1	58.23	0.05	ORD-100745
736	54766	6	2	96.55	0.00	ORD-100746
737	51421	9	2	11.87	0.05	ORD-100747
738	54242	11	3	8.91	0.00	ORD-100748
739	53489	15	1	79.42	0.15	ORD-100749
740	50474	13	1	536.52	0.15	ORD-100750
741	54526	9	1	11.75	0.00	ORD-100751
742	53791	20	1	345.80	0.00	ORD-100752
743	51712	2	1	71.01	0.10	ORD-100753
744	55613	12	4	24.61	0.10	ORD-100754
745	50203	18	5	15.03	0.00	ORD-100755
746	53512	15	2	79.73	0.15	ORD-100756
747	52157	17	1	438.69	0.05	ORD-100757
748	50388	18	4	14.56	0.10	ORD-100758
749	50959	7	1	58.40	0.00	ORD-100759
750	53376	10	2	180.52	0.00	ORD-100760
751	50125	11	6	9.28	0.00	ORD-100761
752	54849	18	5	15.60	0.10	ORD-100762
753	52326	14	1	199.51	0.15	ORD-100763
754	54170	12	1	24.17	0.10	ORD-100764
755	55798	1	2	106.16	0.00	ORD-100765
756	52593	18	2	15.00	0.05	ORD-100766
757	50573	9	2	12.10	0.05	ORD-100767
758	53589	9	5	11.82	0.00	ORD-100769
759	55664	15	2	78.40	0.20	ORD-100770
760	51845	20	1	328.38	0.10	ORD-100771
761	55556	12	6	25.43	0.00	ORD-100772
762	50475	10	3	173.23	0.00	ORD-100773
763	51232	6	1	95.88	0.00	ORD-100774
764	53513	20	2	320.33	0.15	ORD-100775
765	54171	20	4	329.42	0.00	ORD-100776
766	52235	15	3	83.88	0.20	ORD-100777
767	50960	13	1	516.79	0.00	ORD-100778
768	54554	9	2	12.07	0.00	ORD-100779
769	51118	20	1	335.48	0.00	ORD-100780
770	55205	14	1	219.70	0.00	ORD-100781
771	53792	4	1	147.05	0.10	ORD-100782
772	53303	7	2	57.71	0.00	ORD-100783
773	54204	5	3	91.29	0.00	ORD-100784
774	54243	15	1	80.59	0.00	ORD-100785
775	53490	17	3	420.64	0.00	ORD-100786
776	50819	10	1	188.18	0.05	ORD-100787
777	51772	4	1	143.01	0.00	ORD-100788
778	50310	1	1	109.16	0.10	ORD-100789
779	51846	20	1	345.12	0.00	ORD-100790
780	54014	13	1	501.59	0.05	ORD-100791
781	53793	16	1	653.84	0.05	ORD-100792
782	54427	16	2	634.19	0.00	ORD-100793
783	55703	17	1	416.76	0.00	ORD-100794
784	52055	20	3	340.44	0.05	ORD-100795
785	54962	14	1	204.52	0.15	ORD-100796
786	52056	15	1	82.30	0.00	ORD-100797
787	50961	3	1	135.78	0.00	ORD-100798
788	52373	1	1	105.77	0.00	ORD-100799
789	53491	2	2	69.52	0.20	ORD-100800
790	52012	15	2	77.70	0.20	ORD-100801
791	50231	10	1	181.55	0.20	ORD-100802
792	51364	13	3	540.83	0.15	ORD-100803
793	53142	12	3	25.51	0.20	ORD-100804
794	54490	17	2	428.88	0.00	ORD-100805
795	52037	8	1	762.01	0.00	ORD-100806
796	53590	14	1	204.21	0.05	ORD-100807
797	52594	11	1	8.57	0.10	ORD-100808
798	54715	20	2	337.54	0.00	ORD-100809
799	52058	14	1	210.46	0.00	ORD-100810
800	52057	14	1	217.52	0.00	ORD-100811
801	53719	16	2	609.78	0.10	ORD-100812
802	55206	2	1	69.31	0.00	ORD-100813
803	50126	6	4	93.25	0.05	ORD-100814
804	51744	18	4	15.13	0.15	ORD-100815
805	50771	13	2	539.15	0.00	ORD-100816
806	50962	13	2	525.65	0.00	ORD-100817
807	50894	8	3	759.86	0.00	ORD-100818
808	53794	7	3	58.57	0.00	ORD-100819
809	54145	5	1	86.92	0.10	ORD-100820
810	54611	14	1	205.31	0.00	ORD-100821
811	51701	11	4	9.12	0.00	ORD-100822
812	53650	12	4	23.94	0.00	ORD-100823
813	52201	11	3	8.83	0.10	ORD-100824
814	52212	11	3	8.86	0.05	ORD-100825
815	54675	8	1	769.99	0.10	ORD-100826
816	50232	12	6	24.50	0.15	ORD-100827
817	52643	4	2	145.93	0.05	ORD-100828
818	54895	2	1	72.81	0.10	ORD-100829
819	52508	10	1	174.94	0.15	ORD-100830
820	53377	8	2	750.47	0.00	ORD-100831
821	54676	17	1	412.79	0.20	ORD-100832
822	51577	3	1	123.53	0.15	ORD-100833
823	52695	7	2	62.43	0.10	ORD-100834
824	54612	16	1	639.85	0.05	ORD-100835
825	55736	20	2	336.31	0.00	ORD-100836
826	53514	12	2	24.45	0.05	ORD-100837
827	55075	20	2	317.47	0.00	ORD-100838
828	53795	1	2	115.34	0.15	ORD-100839
829	53944	6	1	94.46	0.10	ORD-100840
830	55207	19	1	22.21	0.15	ORD-100841
831	54205	20	1	341.74	0.00	ORD-100842
832	52059	17	2	417.84	0.00	ORD-100843
833	54767	2	1	70.98	0.00	ORD-100844
834	52966	17	1	399.49	0.00	ORD-100845
835	53007	7	2	57.54	0.15	ORD-100846
836	50678	4	1	154.99	0.10	ORD-100847
837	53945	15	3	77.25	0.00	ORD-100848
838	55578	16	1	620.63	0.15	ORD-100849
839	53304	16	1	623.16	0.00	ORD-100850
840	53305	1	1	107.73	0.00	ORD-100851
841	50127	10	1	187.79	0.00	ORD-100852
842	55154	13	1	497.55	0.00	ORD-100853
843	54677	12	3	25.03	0.20	ORD-100854
844	53143	6	1	92.75	0.00	ORD-100855
845	55076	20	1	336.77	0.00	ORD-100856
846	52906	13	1	538.73	0.10	ORD-100857
847	54428	14	2	205.20	0.15	ORD-100858
848	53084	12	3	26.00	0.15	ORD-100859
849	52428	19	2	21.10	0.00	ORD-100860
850	51233	20	1	319.07	0.00	ORD-100861
851	50963	18	4	15.15	0.05	ORD-100862
852	51745	8	2	764.79	0.00	ORD-100863
853	51635	11	2	9.36	0.00	ORD-100864
854	50837	10	1	188.71	0.00	ORD-100866
855	51328	3	1	134.40	0.10	ORD-100867
856	52827	9	1	11.98	0.00	ORD-100868
857	54613	4	2	157.17	0.00	ORD-100869
858	51961	18	4	15.64	0.00	ORD-100870
859	54244	1	2	107.15	0.00	ORD-100871
860	55208	12	6	24.90	0.10	ORD-100872
861	50964	13	2	541.53	0.00	ORD-100873
862	50010	17	1	400.40	0.15	ORD-100874
863	51390	13	1	496.61	0.10	ORD-100875
864	54768	13	1	529.44	0.05	ORD-100876
865	52967	20	2	325.71	0.05	ORD-100877
866	52213	11	3	9.17	0.10	ORD-100878
867	55209	17	1	420.12	0.00	ORD-100879
868	53144	11	2	9.13	0.10	ORD-100880
869	54850	18	2	15.35	0.05	ORD-100881
870	53238	17	1	417.91	0.20	ORD-100882
871	51495	13	2	499.95	0.00	ORD-100883
872	51847	11	3	9.26	0.20	ORD-100884
873	53008	19	1	22.04	0.05	ORD-100885
874	51187	9	4	12.48	0.00	ORD-100886
875	50895	9	3	11.59	0.15	ORD-100887
876	55210	4	2	142.83	0.10	ORD-100888
877	50574	20	1	313.66	0.00	ORD-100889
878	52968	15	1	81.41	0.15	ORD-100890
879	52859	11	2	8.73	0.00	ORD-100891
880	53306	18	3	15.34	0.00	ORD-100892
881	55725	6	2	91.47	0.05	ORD-100893
882	54614	8	2	741.23	0.10	ORD-100894
883	53422	9	4	11.59	0.00	ORD-100895
884	52907	17	2	437.98	0.00	ORD-100896
885	54245	15	2	79.22	0.10	ORD-100897
886	51848	15	4	76.83	0.05	ORD-100898
887	52969	1	2	113.17	0.10	ORD-100899
888	54982	13	1	502.36	0.00	ORD-100900
889	50603	6	1	93.11	0.15	ORD-100901
890	55056	7	2	59.09	0.05	ORD-100902
891	54896	12	5	24.84	0.05	ORD-100903
892	51746	15	2	81.23	0.00	ORD-100904
893	55704	14	1	213.58	0.10	ORD-100905
894	55776	19	1	21.87	0.00	ORD-100906
895	53113	12	1	26.16	0.15	ORD-100907
896	53009	18	5	14.73	0.15	ORD-100908
897	55211	11	4	9.17	0.00	ORD-100909
898	50896	8	1	753.47	0.00	ORD-100910
899	51234	13	1	517.59	0.00	ORD-100911
900	51713	15	1	78.19	0.00	ORD-100912
901	52764	13	1	525.38	0.00	ORD-100913
902	54555	4	2	150.97	0.00	ORD-100914
903	54897	4	1	146.89	0.05	ORD-100915
904	50701	8	2	737.36	0.00	ORD-100916
905	54190	16	1	638.78	0.05	ORD-100917
906	50701	12	3	25.09	0.15	ORD-100918
907	54146	19	2	22.63	0.10	ORD-100919
908	50233	13	1	494.92	0.00	ORD-100920
909	53348	9	4	11.49	0.10	ORD-100921
910	50476	15	2	80.74	0.00	ORD-100922
911	54172	11	5	9.44	0.00	ORD-100923
912	51849	16	1	664.27	0.10	ORD-100924
913	54147	18	4	14.55	0.05	ORD-100925
914	50011	18	7	15.41	0.10	ORD-100926
915	53863	9	2	12.58	0.15	ORD-100927
916	50404	19	2	21.13	0.15	ORD-100928
917	51511	13	1	512.18	0.15	ORD-100929
918	53591	4	2	150.39	0.00	ORD-100930
919	53145	5	1	85.99	0.00	ORD-100931
920	54098	2	1	71.49	0.10	ORD-100932
921	53492	9	5	11.98	0.00	ORD-100933
922	51702	5	2	93.07	0.10	ORD-100934
923	52060	18	1	15.47	0.05	ORD-100935
924	55557	12	1	24.14	0.00	ORD-100936
925	53463	10	1	182.55	0.10	ORD-100937
926	50965	4	2	154.08	0.15	ORD-100938
927	53864	18	6	15.46	0.15	ORD-100939
928	52735	11	3	8.68	0.10	ORD-100940
929	54319	9	6	12.59	0.15	ORD-100941
930	55212	1	1	113.04	0.05	ORD-100942
931	52158	9	4	11.71	0.20	ORD-100943
932	54898	2	2	70.83	0.00	ORD-100944
933	54246	1	1	109.84	0.00	ORD-100945
934	50405	4	1	157.32	0.15	ORD-100946
935	54983	1	1	105.78	0.00	ORD-100947
936	53651	13	1	508.25	0.00	ORD-100948
937	53913	5	1	88.13	0.00	ORD-100949
938	55814	2	2	69.09	0.05	ORD-100950
939	51422	19	4	22.29	0.00	ORD-100951
940	55213	18	5	15.02	0.10	ORD-100952
941	55777	3	1	127.64	0.10	ORD-100953
942	54206	13	1	504.46	0.10	ORD-100954
943	50966	15	3	80.19	0.00	ORD-100955
944	53720	18	3	14.76	0.00	ORD-100956
945	55213	10	1	184.91	0.00	ORD-100957
946	50754	19	2	21.60	0.05	ORD-100958
947	51636	4	1	154.59	0.00	ORD-100959
948	50598	6	2	92.85	0.00	ORD-100960
949	54899	11	9	8.98	0.00	ORD-100961
950	51131	2	3	72.89	0.05	ORD-100962
951	52460	14	1	203.02	0.15	ORD-100963
952	55614	11	8	8.87	0.00	ORD-100964
953	53652	10	1	187.59	0.00	ORD-100965
954	55077	19	2	22.90	0.00	ORD-100966
955	53592	20	1	338.79	0.00	ORD-100967
956	52130	17	1	432.35	0.10	ORD-100968
957	51235	2	1	70.89	0.00	ORD-100969
958	50406	13	4	540.36	0.00	ORD-100970
959	50967	6	3	98.36	0.20	ORD-100971
960	50897	14	1	217.11	0.00	ORD-100972
961	51790	11	4	9.43	0.20	ORD-100973
962	50898	15	2	80.46	0.00	ORD-100974
963	53593	4	1	144.97	0.20	ORD-100975
964	53796	7	2	60.13	0.05	ORD-100977
965	50128	18	6	15.57	0.00	ORD-100978
966	55430	15	1	83.15	0.15	ORD-100979
967	50785	13	2	531.73	0.00	ORD-100980
968	51512	11	2	8.68	0.00	ORD-100981
969	51423	4	2	146.35	0.00	ORD-100982
970	52382	7	2	62.37	0.10	ORD-100983
971	54829	1	1	113.67	0.15	ORD-100984
972	53307	20	1	333.24	0.10	ORD-100985
973	52446	18	7	15.52	0.00	ORD-100987
974	53914	19	5	21.80	0.15	ORD-100988
975	50968	12	5	24.53	0.10	ORD-100989
976	52595	9	1	12.51	0.15	ORD-100990
977	50012	16	2	658.96	0.10	ORD-100991
978	53515	17	1	436.08	0.00	ORD-100992
979	50565	16	2	666.20	0.00	ORD-100993
980	53653	12	3	23.93	0.15	ORD-100994
981	54247	5	2	85.97	0.10	ORD-100995
982	52159	3	1	130.00	0.00	ORD-100996
983	53797	5	1	86.70	0.10	ORD-100997
984	52461	7	2	62.34	0.00	ORD-100998
985	53464	19	2	22.26	0.00	ORD-100999
986	55636	17	1	403.72	0.10	ORD-101000
987	53568	10	1	187.83	0.00	ORD-101001
988	50702	19	1	21.17	0.00	ORD-101002
989	51513	12	3	23.85	0.05	ORD-101003
990	52828	1	1	105.38	0.00	ORD-101004
991	50645	14	1	204.35	0.00	ORD-101005
992	50969	13	1	494.84	0.10	ORD-101006
993	52908	5	2	90.20	0.00	ORD-101007
994	51424	3	1	127.89	0.20	ORD-101008
995	52225	7	2	59.38	0.00	ORD-101009
996	51425	9	4	11.43	0.05	ORD-101010
997	54716	4	2	156.03	0.00	ORD-101011
998	51714	19	2	22.84	0.00	ORD-101012
999	55155	20	1	315.32	0.00	ORD-101013
1000	51850	2	3	69.89	0.15	ORD-101014
1001	54984	5	1	90.68	0.00	ORD-101015
1002	52808	19	2	21.01	0.05	ORD-101016
1003	50447	5	2	92.63	0.10	ORD-101017
1004	55637	2	1	72.45	0.00	ORD-101019
1005	52549	16	1	659.91	0.05	ORD-101020
1006	50440	15	2	76.07	0.10	ORD-101021
1007	50064	3	2	135.88	0.05	ORD-101022
1008	54700	5	3	92.75	0.10	ORD-101023
1009	52909	13	2	515.65	0.00	ORD-101024
1010	53721	11	8	8.69	0.00	ORD-101025
1011	50599	6	1	94.34	0.00	ORD-101026
1012	54207	6	1	99.44	0.05	ORD-101027
1013	52013	1	1	110.15	0.05	ORD-101028
1014	53423	8	3	780.77	0.00	ORD-101029
1015	54491	5	1	91.69	0.20	ORD-101030
1016	55462	18	2	15.48	0.00	ORD-101031
1017	52788	12	3	24.70	0.15	ORD-101032
1018	52383	2	1	73.32	0.00	ORD-101033
1019	52014	11	7	8.63	0.05	ORD-101034
1020	50646	20	1	321.73	0.00	ORD-101035
1021	50204	18	4	15.53	0.00	ORD-101036
1022	55638	13	2	527.66	0.00	ORD-101037
1023	51851	9	7	12.50	0.15	ORD-101038
1024	53880	9	5	12.37	0.15	ORD-101039
1025	55214	20	2	320.78	0.00	ORD-101040
1026	50899	9	3	11.77	0.00	ORD-101041
1027	52560	9	5	11.43	0.05	ORD-101042
1028	54556	6	3	95.99	0.10	ORD-101043
1029	54474	10	1	174.18	0.05	ORD-101044
1030	50129	9	2	12.35	0.00	ORD-101045
1031	52970	9	6	11.74	0.00	ORD-101046
1032	55545	20	1	341.16	0.00	ORD-101047
1033	52226	18	1	14.93	0.05	ORD-101048
1034	51426	13	3	507.39	0.05	ORD-101049
1035	55463	1	2	110.39	0.10	ORD-101050
1036	50679	20	1	327.48	0.00	ORD-101051
1037	53798	12	2	25.44	0.05	ORD-101052
1038	53146	5	1	85.59	0.05	ORD-101053
1039	52061	12	3	25.92	0.00	ORD-101054
1040	52910	12	3	25.05	0.00	ORD-101055
1041	55078	12	4	24.37	0.00	ORD-101056
1042	53239	12	4	25.75	0.05	ORD-101057
1043	52944	7	3	58.37	0.05	ORD-101058
1044	55728	12	4	26.02	0.00	ORD-101059
1045	53799	6	1	92.73	0.00	ORD-101060
1046	50970	18	3	14.27	0.00	ORD-101061
1047	53800	7	2	60.86	0.00	ORD-101062
1048	51329	8	1	771.69	0.10	ORD-101063
1049	55215	12	4	26.13	0.00	ORD-101064
1050	54717	10	1	173.32	0.05	ORD-101065
1051	53594	14	1	204.98	0.00	ORD-101066
1052	50389	9	3	12.38	0.15	ORD-101067
1053	53357	10	1	182.55	0.00	ORD-101068
1054	50971	15	1	82.03	0.00	ORD-101069
1055	51637	20	1	331.65	0.00	ORD-101070
1056	50477	13	1	515.73	0.00	ORD-101071
1057	51427	16	1	643.55	0.05	ORD-101072
1058	54117	15	3	80.77	0.05	ORD-101073
1059	54574	20	1	343.39	0.00	ORD-101074
1060	50407	2	1	68.19	0.00	ORD-101075
1061	55678	17	1	403.09	0.15	ORD-101076
1062	52765	20	2	345.21	0.00	ORD-101077
1063	50623	18	3	15.35	0.00	ORD-101078
1064	52950	13	2	539.95	0.00	ORD-101079
1065	52062	8	1	744.85	0.00	ORD-101080
1066	53147	13	1	533.73	0.10	ORD-101081
1067	50214	1	1	114.25	0.20	ORD-101082
1068	55079	2	1	69.47	0.00	ORD-101083
1069	50552	14	1	208.00	0.20	ORD-101084
1070	55743	9	6	11.88	0.10	ORD-101085
1071	51236	14	3	200.83	0.05	ORD-101086
1072	53801	7	1	57.82	0.00	ORD-101087
1073	51798	14	1	213.47	0.00	ORD-101088
1074	52370	17	1	400.47	0.00	ORD-101089
1075	55639	14	1	220.08	0.00	ORD-101090
1076	54290	4	1	152.36	0.05	ORD-101091
1077	55490	18	4	15.02	0.05	ORD-101092
1078	54429	1	2	113.76	0.00	ORD-101093
1079	50794	20	2	330.71	0.00	ORD-101094
1080	52829	17	1	436.98	0.00	ORD-101095
1081	54015	15	1	83.55	0.20	ORD-101096
1082	51237	7	3	61.54	0.05	ORD-101097
1083	52327	11	9	9.43	0.00	ORD-101098
1084	53148	9	7	12.40	0.05	ORD-101099
1085	52951	7	3	59.98	0.05	ORD-101100
1086	51514	2	1	72.72	0.05	ORD-101101
1087	50311	12	2	25.14	0.00	ORD-101102
1088	54016	7	3	59.83	0.05	ORD-101103
1089	52749	9	2	11.95	0.05	ORD-101104
1090	50972	6	2	95.55	0.00	ORD-101105
1091	53308	16	1	642.41	0.00	ORD-101106
1092	53149	9	5	12.00	0.00	ORD-101107
1093	50575	8	2	720.71	0.00	ORD-101108
1094	53099	6	1	99.39	0.15	ORD-101110
1095	54718	5	1	89.52	0.00	ORD-101111
1096	52717	20	1	338.56	0.10	ORD-101112
1097	53424	6	1	90.65	0.05	ORD-101113
1098	51673	1	2	105.40	0.00	ORD-101114
1099	54900	7	1	62.07	0.00	ORD-101115
1100	50624	4	1	152.13	0.05	ORD-101116
1101	55216	9	5	12.45	0.00	ORD-101117
1102	53085	4	2	145.30	0.00	ORD-101118
1103	50234	16	1	620.88	0.00	ORD-101119
1104	51515	14	2	199.57	0.05	ORD-101120
1105	50215	11	6	9.40	0.00	ORD-101121
1106	54851	11	5	9.04	0.00	ORD-101122
1107	50900	1	2	104.70	0.00	ORD-101123
1108	53595	1	2	109.48	0.10	ORD-101124
1109	50973	11	6	8.86	0.00	ORD-101125
1110	52063	3	1	123.87	0.00	ORD-101126
1111	50795	20	4	346.23	0.15	ORD-101127
1112	52561	15	3	77.04	0.15	ORD-101128
1113	50065	1	2	111.01	0.15	ORD-101129
1114	54050	8	2	747.10	0.15	ORD-101130
1115	55217	20	1	316.23	0.15	ORD-101131
1116	51330	11	5	8.90	0.05	ORD-101132
1117	53240	19	2	21.89	0.05	ORD-101133
1118	52696	12	4	24.85	0.00	ORD-101134
1119	53425	7	3	59.74	0.00	ORD-101135
1120	50974	12	4	25.90	0.10	ORD-101136
1121	54769	12	3	25.94	0.20	ORD-101137
1122	50625	17	1	413.77	0.00	ORD-101138
1123	51428	17	1	406.30	0.00	ORD-101139
1124	53654	14	2	216.28	0.00	ORD-101140
1125	54129	6	3	94.82	0.00	ORD-101141
1126	55218	11	5	9.15	0.15	ORD-101142
1127	54985	18	3	14.60	0.00	ORD-101143
1128	50478	20	3	338.11	0.15	ORD-101144
1129	55513	2	2	70.74	0.20	ORD-101145
1130	51238	1	2	104.69	0.00	ORD-101146
1131	51852	20	3	327.25	0.00	ORD-101147
1132	54770	15	4	80.43	0.00	ORD-101148
1133	53426	8	1	776.66	0.05	ORD-101149
1134	53150	20	1	332.50	0.00	ORD-101150
1135	53722	20	3	341.05	0.00	ORD-101151
1136	55219	15	1	79.60	0.00	ORD-101152
1137	50703	11	3	9.39	0.05	ORD-101153
1138	55219	5	1	91.76	0.00	ORD-101154
1139	52227	11	7	9.24	0.00	ORD-101155
1140	53123	8	1	759.06	0.00	ORD-101156
1141	52228	12	1	26.10	0.00	ORD-101157
1142	55220	17	2	417.45	0.00	ORD-101158
1143	53086	19	3	21.72	0.05	ORD-101159
1144	54450	14	2	208.96	0.00	ORD-101160
1145	53851	10	1	173.77	0.00	ORD-101161
1146	55815	9	4	12.51	0.15	ORD-101162
1147	52697	16	2	662.35	0.15	ORD-101163
1148	50235	3	4	129.86	0.00	ORD-101164
1149	52945	1	1	104.61	0.05	ORD-101165
1150	54615	8	1	741.02	0.00	ORD-101166
1151	54901	8	1	739.29	0.00	ORD-101167
1152	54430	1	1	111.03	0.00	ORD-101168
1153	52644	13	1	532.62	0.05	ORD-101169
1154	53946	16	1	611.02	0.00	ORD-101170
1155	54148	19	1	21.14	0.00	ORD-101171
1156	52789	8	3	738.41	0.15	ORD-101172
1157	55221	1	1	110.17	0.05	ORD-101173
1158	54986	9	4	12.43	0.20	ORD-101174
1159	52131	2	1	69.18	0.20	ORD-101175
1160	55223	15	3	80.56	0.15	ORD-101176
1161	55222	9	3	12.48	0.05	ORD-101177
1162	52412	11	4	9.31	0.05	ORD-101178
1163	55558	9	3	12.59	0.00	ORD-101179
1164	52462	18	8	15.02	0.00	ORD-101180
1165	51733	3	1	132.41	0.15	ORD-101181
1166	55222	4	3	152.15	0.00	ORD-101182
1167	52596	19	1	22.10	0.10	ORD-101183
1168	52253	9	4	11.64	0.00	ORD-101184
1169	51638	15	2	80.40	0.00	ORD-101185
1170	53925	2	1	69.39	0.00	ORD-101186
1171	55579	12	3	25.54	0.10	ORD-101187
1172	50838	13	1	517.21	0.05	ORD-101188
1173	51119	18	4	15.44	0.15	ORD-101189
1174	52509	13	1	501.24	0.00	ORD-101190
1175	52562	13	1	523.62	0.05	ORD-101191
1176	55431	20	1	321.05	0.05	ORD-101192
1177	50013	9	5	12.37	0.05	ORD-101193
1178	51578	19	1	21.62	0.00	ORD-101194
1179	51715	14	1	210.68	0.00	ORD-101195
1180	51239	15	1	80.11	0.05	ORD-101196
1181	50236	1	1	114.77	0.00	ORD-101197
1182	50479	5	1	89.97	0.00	ORD-101198
1183	50216	10	1	177.72	0.10	ORD-101199
1184	51429	16	2	627.94	0.00	ORD-101200
1185	50236	12	6	23.86	0.10	ORD-101201
1186	51571	20	1	320.87	0.10	ORD-101202
1187	54557	15	2	82.49	0.05	ORD-101203
1188	52132	5	1	92.53	0.00	ORD-101204
1189	54987	14	2	216.89	0.00	ORD-101205
1190	53010	10	1	182.11	0.00	ORD-101206
1191	55744	17	2	399.84	0.05	ORD-101207
1192	52645	20	1	343.04	0.15	ORD-101208
1193	51132	6	1	93.61	0.00	ORD-101209
1194	50975	9	4	11.83	0.15	ORD-101210
1195	51853	11	3	8.99	0.00	ORD-101211
1196	51799	8	1	743.44	0.00	ORD-101212
1197	55679	6	2	93.91	0.10	ORD-101213
1198	53241	8	1	753.80	0.20	ORD-101214
1199	52463	12	3	24.98	0.05	ORD-101215
1200	50130	11	1	9.08	0.15	ORD-101216
1201	52202	11	4	9.11	0.05	ORD-101217
1202	54902	18	2	15.49	0.00	ORD-101218
1203	54248	2	1	72.58	0.00	ORD-101219
1204	53242	3	1	124.75	0.00	ORD-101220
1205	55224	6	1	93.19	0.00	ORD-101221
1206	55080	7	1	61.04	0.00	ORD-101222
1207	53151	3	1	125.73	0.00	ORD-101223
1208	50089	4	1	151.94	0.05	ORD-101224
1209	50095	6	2	96.16	0.00	ORD-101225
1210	55705	8	1	779.72	0.00	ORD-101226
1211	53596	9	7	11.85	0.00	ORD-101227
1212	53560	13	2	513.38	0.10	ORD-101228
1213	55057	1	2	105.52	0.00	ORD-101229
1214	54130	14	2	209.14	0.00	ORD-101230
1215	50745	16	1	637.53	0.00	ORD-101231
1216	52015	10	1	184.05	0.05	ORD-101232
1217	51639	5	1	93.14	0.00	ORD-101233
1218	53309	19	2	22.67	0.00	ORD-101234
1219	54431	6	1	92.44	0.05	ORD-101235
1220	53947	6	2	99.53	0.00	ORD-101236
1221	51240	8	1	774.94	0.00	ORD-101237
1222	54064	11	5	8.82	0.00	ORD-101238
1223	52809	5	3	91.19	0.10	ORD-101239
1224	52597	6	1	98.23	0.00	ORD-101240
1225	51516	11	5	8.71	0.05	ORD-101241
1226	55225	6	2	93.23	0.05	ORD-101242
1227	51854	13	1	513.21	0.10	ORD-101243
1228	55706	18	4	14.33	0.15	ORD-101244
1229	52750	8	1	731.16	0.10	ORD-101245
1230	51365	13	3	522.14	0.00	ORD-101246
1231	53769	2	2	68.53	0.05	ORD-101247
1232	52486	13	3	526.01	0.00	ORD-101248
1233	50618	18	8	15.27	0.00	ORD-101249
1234	50237	2	1	71.96	0.05	ORD-101250
1235	52810	5	2	89.68	0.05	ORD-101251
1236	50796	9	3	12.54	0.15	ORD-101252
1237	52064	5	2	93.59	0.00	ORD-101253
1238	53465	15	2	77.95	0.00	ORD-101254
1239	51747	14	1	217.71	0.00	ORD-101255
1240	53915	3	1	129.36	0.00	ORD-101256
1241	50014	15	1	76.44	0.05	ORD-101257
1242	55640	13	1	496.02	0.20	ORD-101258
1243	54819	2	1	70.14	0.00	ORD-101259
1244	50976	19	2	23.07	0.10	ORD-101260
1245	53900	4	1	151.55	0.00	ORD-101261
1246	50977	12	3	23.93	0.00	ORD-101262
1247	50576	11	2	9.43	0.10	ORD-101263
1248	51391	11	4	9.03	0.00	ORD-101264
1249	53770	5	2	93.89	0.00	ORD-101265
1250	50882	15	1	79.86	0.00	ORD-101266
1251	50704	20	2	338.24	0.05	ORD-101267
1252	51241	18	2	15.30	0.05	ORD-101268
1253	54051	16	1	633.31	0.10	ORD-101269
1254	51855	7	4	57.68	0.00	ORD-101270
1255	51517	5	2	86.67	0.20	ORD-101271
1256	51133	5	1	93.81	0.00	ORD-101272
1257	50066	6	1	91.31	0.05	ORD-101273
1258	52109	20	1	325.84	0.05	ORD-101274
1259	53516	9	4	11.74	0.00	ORD-101275
1260	54149	3	1	132.35	0.00	ORD-101276
1261	54382	2	1	67.91	0.15	ORD-101277
1262	50536	12	6	23.84	0.00	ORD-101278
1263	50467	9	2	12.43	0.00	ORD-101279
1264	54667	18	4	15.69	0.15	ORD-101281
1265	51640	14	2	213.70	0.20	ORD-101282
1266	51242	7	2	60.91	0.20	ORD-101283
1267	53243	16	1	624.82	0.15	ORD-101284
1268	51856	4	1	143.40	0.00	ORD-101285
1269	50839	7	1	58.10	0.00	ORD-101286
1270	52254	18	2	15.60	0.00	ORD-101287
1271	51430	12	3	24.11	0.05	ORD-101288
1272	54084	16	2	643.86	0.00	ORD-101289
1273	54813	14	2	211.07	0.00	ORD-101290
1274	55559	16	1	635.92	0.00	ORD-101291
1275	54575	13	1	500.72	0.00	ORD-101292
1276	51188	18	4	14.95	0.15	ORD-101293
1277	55464	6	2	98.69	0.05	ORD-101294
1278	54719	15	3	78.93	0.00	ORD-101295
1279	50577	18	2	15.74	0.00	ORD-101296
1280	52646	14	2	212.77	0.15	ORD-101297
1281	55465	3	1	131.34	0.00	ORD-101298
1282	55432	11	2	8.93	0.10	ORD-101299
1283	54249	20	3	338.68	0.15	ORD-101300
1284	50647	13	2	527.96	0.00	ORD-101301
1285	55226	13	1	512.88	0.05	ORD-101302
1286	55615	7	2	62.97	0.00	ORD-101303
1287	52911	9	4	12.39	0.00	ORD-101304
1288	52971	8	1	735.40	0.00	ORD-101305
1289	54720	18	3	15.13	0.05	ORD-101306
1290	51431	10	2	185.37	0.15	ORD-101307
1291	53427	9	2	12.13	0.10	ORD-101308
1292	50978	10	1	181.16	0.00	ORD-101309
1293	52065	4	2	150.17	0.00	ORD-101310
1294	54771	14	1	201.71	0.20	ORD-101311
1295	51144	7	6	57.23	0.00	ORD-101312
1296	53493	15	2	83.26	0.00	ORD-101313
1297	51243	19	3	21.20	0.00	ORD-101314
1298	55767	12	2	25.82	0.00	ORD-101315
1299	54721	11	4	9.29	0.00	ORD-101316
1300	50979	11	4	9.25	0.00	ORD-101317
1301	53597	16	1	613.75	0.15	ORD-101318
1302	50131	4	3	145.50	0.10	ORD-101319
1303	51748	18	5	14.86	0.00	ORD-101320
1304	54772	10	1	187.79	0.15	ORD-101321
1305	52647	18	2	14.35	0.05	ORD-101323
1306	52775	7	3	58.40	0.00	ORD-101324
1307	52579	4	2	143.28	0.00	ORD-101325
1308	54616	8	1	723.86	0.15	ORD-101326
1309	54383	5	1	87.71	0.05	ORD-101327
1310	54745	14	1	213.95	0.00	ORD-101328
1311	52563	10	1	171.49	0.00	ORD-101329
1312	53152	2	1	73.13	0.10	ORD-101330
1313	55227	19	2	22.22	0.00	ORD-101331
1314	55228	12	3	25.17	0.00	ORD-101332
1315	52972	7	3	57.60	0.05	ORD-101333
1316	54291	5	1	90.02	0.00	ORD-101334
1317	53428	15	3	82.92	0.10	ORD-101335
1318	50980	16	1	632.72	0.15	ORD-101336
1319	51773	19	1	22.41	0.15	ORD-101337
1320	51189	13	1	524.27	0.00	ORD-101338
1321	53494	7	2	60.19	0.05	ORD-101339
1322	53244	15	5	82.36	0.00	ORD-101341
1323	55433	3	1	127.48	0.05	ORD-101342
1324	54358	11	6	9.24	0.00	ORD-101343
1325	54722	9	4	12.27	0.00	ORD-101344
1326	50507	17	2	410.61	0.05	ORD-101345
1327	52751	8	1	776.55	0.10	ORD-101346
1328	51392	5	1	90.70	0.00	ORD-101347
1329	50519	4	1	145.74	0.00	ORD-101348
1330	55081	4	1	149.68	0.05	ORD-101349
1331	52952	13	2	515.57	0.10	ORD-101350
1332	55058	8	1	771.88	0.00	ORD-101351
1333	55229	20	2	336.97	0.00	ORD-101352
1334	54852	7	2	61.28	0.05	ORD-101353
1335	50981	1	1	109.69	0.00	ORD-101354
1336	55560	20	1	330.67	0.05	ORD-101355
1337	53723	4	1	154.71	0.00	ORD-101356
1338	55230	15	2	77.39	0.10	ORD-101357
1339	54250	4	1	150.75	0.00	ORD-101358
1340	52255	20	1	333.12	0.10	ORD-101359
1341	51800	12	5	25.02	0.10	ORD-101360
1342	50982	1	1	111.22	0.05	ORD-101361
1343	51734	19	4	21.49	0.05	ORD-101362
1344	55231	6	2	97.79	0.00	ORD-101363
1345	51393	1	1	106.97	0.00	ORD-101364
1346	50705	1	1	106.83	0.00	ORD-101365
1347	53802	6	1	97.14	0.00	ORD-101366
1348	50312	11	1	8.89	0.00	ORD-101367
1349	50840	7	2	58.88	0.20	ORD-101368
1350	52685	10	1	183.00	0.00	ORD-101369
1351	52487	1	2	105.62	0.05	ORD-101370
1352	50648	4	3	154.25	0.10	ORD-101371
1353	50983	13	1	544.17	0.00	ORD-101372
1354	51366	6	1	94.27	0.00	ORD-101373
1355	50746	14	2	208.57	0.05	ORD-101374
1356	51352	6	1	98.33	0.00	ORD-101375
1357	50984	15	2	79.22	0.10	ORD-101376
1358	53466	3	1	127.84	0.05	ORD-101377
1359	54853	5	2	85.56	0.00	ORD-101378
1360	54854	3	1	133.56	0.00	ORD-101379
1361	51824	18	3	15.48	0.00	ORD-101380
1362	50649	1	1	114.85	0.00	ORD-101381
1363	51244	15	2	81.54	0.00	ORD-101382
1364	51134	2	1	69.33	0.15	ORD-101383
1365	54903	15	3	79.15	0.05	ORD-101384
1366	54678	1	2	112.12	0.00	ORD-101385
1367	51579	20	1	315.76	0.00	ORD-101386
1368	52564	20	1	345.50	0.10	ORD-101387
1369	52464	14	1	211.21	0.10	ORD-101388
1370	54251	14	1	201.08	0.10	ORD-101389
1371	55707	15	2	81.80	0.00	ORD-101390
1372	50132	15	3	77.78	0.10	ORD-101391
1373	50428	6	2	90.70	0.10	ORD-101392
1374	52120	12	5	25.97	0.15	ORD-101393
1375	51688	5	2	91.86	0.00	ORD-101394
1376	54292	5	1	90.42	0.00	ORD-101395
1377	53011	12	4	24.06	0.00	ORD-101396
1378	54746	10	1	184.47	0.00	ORD-101397
1379	54617	12	3	24.94	0.00	ORD-101398
1380	50747	11	9	9.23	0.15	ORD-101399
1381	52752	7	1	59.43	0.00	ORD-101400
1382	50820	19	1	22.67	0.00	ORD-101401
1383	51245	8	1	785.32	0.05	ORD-101402
1384	55616	11	3	8.74	0.10	ORD-101403
1385	52953	1	4	109.21	0.00	ORD-101404
1386	50133	14	2	217.99	0.10	ORD-101405
1387	52066	8	1	718.56	0.20	ORD-101406
1388	50901	13	2	502.90	0.00	ORD-101407
1389	55232	11	5	8.81	0.00	ORD-101408
1390	50985	5	1	89.20	0.05	ORD-101409
1391	52214	1	3	108.44	0.00	ORD-101410
1392	54191	8	1	785.83	0.00	ORD-101411
1393	54988	11	4	8.65	0.00	ORD-101412
1394	52133	2	2	72.88	0.10	ORD-101413
1395	51135	2	3	67.29	0.05	ORD-101414
1396	52753	18	4	15.51	0.00	ORD-101415
1397	53087	1	2	106.76	0.00	ORD-101416
1398	54511	20	2	316.60	0.00	ORD-101417
1399	51518	12	7	26.17	0.00	ORD-101418
1400	50986	7	1	62.29	0.10	ORD-101419
1401	51496	19	2	23.01	0.00	ORD-101420
1402	50217	16	1	624.08	0.00	ORD-101421
1403	55233	20	2	315.04	0.00	ORD-101422
1404	55233	20	1	316.92	0.00	ORD-101423
1405	52648	18	1	14.95	0.05	ORD-101424
1406	52649	1	1	111.79	0.00	ORD-101425
1407	54384	11	4	9.38	0.00	ORD-101427
1408	54773	13	2	538.46	0.00	ORD-101428
1409	52291	9	2	11.79	0.10	ORD-101429
1410	53245	5	1	87.62	0.00	ORD-101430
1411	50218	9	4	12.12	0.10	ORD-101431
1412	53429	8	1	730.14	0.00	ORD-101432
1413	53088	11	6	9.09	0.05	ORD-101433
1414	55514	8	2	748.86	0.00	ORD-101434
1415	54774	16	1	624.33	0.00	ORD-101435
1416	53246	20	1	341.91	0.10	ORD-101436
1417	51497	3	1	136.04	0.00	ORD-101437
1418	54747	9	5	12.17	0.00	ORD-101438
1419	50604	20	2	328.06	0.05	ORD-101439
1420	50313	2	1	71.62	0.20	ORD-101440
1421	50987	6	1	96.95	0.00	ORD-101441
1422	55234	20	4	322.92	0.05	ORD-101442
1423	55235	2	1	70.89	0.00	ORD-101443
1424	53100	12	2	24.57	0.15	ORD-101444
1425	55466	7	2	58.86	0.05	ORD-101445
1426	55737	18	5	15.58	0.05	ORD-101446
1427	53948	2	1	69.31	0.00	ORD-101447
1428	55137	15	1	79.79	0.00	ORD-101448
1429	54385	19	1	22.78	0.00	ORD-101449
1430	55641	20	2	321.33	0.15	ORD-101450
1431	54385	1	2	112.63	0.00	ORD-101451
1432	52530	18	2	15.19	0.00	ORD-101453
1433	52103	2	1	68.07	0.00	ORD-101454
1434	50134	6	3	98.45	0.00	ORD-101455
1435	53247	9	2	12.25	0.15	ORD-101456
1436	52067	18	6	14.61	0.00	ORD-101457
1437	50286	11	7	9.17	0.10	ORD-101458
1438	51857	8	1	783.08	0.00	ORD-101459
1439	52465	5	2	87.72	0.05	ORD-101460
1440	51432	19	3	21.55	0.10	ORD-101461
1441	54598	14	1	217.89	0.00	ORD-101462
1442	55236	12	10	24.69	0.00	ORD-101463
1443	54904	20	1	319.04	0.05	ORD-101464
1444	55237	8	2	738.58	0.00	ORD-101465
1445	54252	10	1	177.37	0.00	ORD-101466
1446	52754	16	2	615.14	0.15	ORD-101467
1447	52160	3	1	126.69	0.15	ORD-101468
1448	51749	14	1	200.80	0.05	ORD-101469
1449	53724	20	1	338.68	0.10	ORD-101470
1450	53012	4	3	147.47	0.05	ORD-101471
1451	50219	20	2	319.65	0.05	ORD-101472
1452	53655	11	1	8.96	0.15	ORD-101473
1453	50841	2	2	67.09	0.00	ORD-101474
1454	55617	9	4	12.52	0.00	ORD-101475
1455	54386	6	1	96.59	0.00	ORD-101476
1456	52215	4	1	157.29	0.20	ORD-101477
1457	55131	3	1	135.86	0.00	ORD-101478
1458	55082	11	6	9.09	0.00	ORD-101479
1459	50429	20	3	335.75	0.00	ORD-101480
1460	50605	6	1	94.12	0.00	ORD-101481
1461	53541	12	4	25.81	0.00	ORD-101482
1462	52973	17	1	410.27	0.00	ORD-101483
1463	51962	12	8	23.75	0.00	ORD-101484
1464	55665	7	2	61.09	0.00	ORD-101485
1465	54839	8	2	730.87	0.00	ORD-101486
1466	53089	19	1	21.99	0.00	ORD-101487
1467	50639	4	1	155.14	0.00	ORD-101488
1468	54017	4	1	156.32	0.05	ORD-101489
1469	53656	9	6	11.92	0.00	ORD-101490
1470	53153	11	2	8.83	0.10	ORD-101491
1471	52328	14	2	213.44	0.00	ORD-101492
1472	54542	9	3	12.09	0.00	ORD-101493
1473	51750	17	1	406.06	0.00	ORD-101494
1474	54475	7	3	62.62	0.10	ORD-101495
1475	55515	6	2	92.08	0.00	ORD-101496
1476	55561	20	2	324.25	0.05	ORD-101497
1477	51611	18	4	15.52	0.10	ORD-101498
1478	54775	18	2	15.42	0.00	ORD-101499
1479	52545	15	5	77.45	0.00	ORD-101500
1480	54543	7	2	59.47	0.05	ORD-101501
1481	53154	6	1	96.18	0.05	ORD-101502
1482	50842	19	1	21.77	0.00	ORD-101503
1483	53467	12	4	25.37	0.00	ORD-101504
1484	52736	9	3	12.27	0.00	ORD-101505
1485	50650	20	1	313.62	0.15	ORD-101506
1486	52912	19	1	21.78	0.00	ORD-101507
1487	52811	3	2	130.43	0.05	ORD-101508
1488	52913	18	2	15.01	0.00	ORD-101509
1489	55238	18	3	15.01	0.00	ORD-101510
1490	52534	9	3	11.44	0.15	ORD-101511
1491	51246	15	1	77.91	0.00	ORD-101512
1492	53542	6	1	95.20	0.10	ORD-101513
1493	53310	6	1	97.59	0.15	ORD-101514
1494	53013	18	5	15.04	0.00	ORD-101515
1495	52161	7	2	60.98	0.00	ORD-101516
1496	50706	18	1	15.63	0.00	ORD-101517
1497	52974	8	1	784.38	0.05	ORD-101518
1498	52384	5	1	93.24	0.05	ORD-101519
1499	55618	6	1	97.45	0.05	ORD-101520
1500	52510	10	1	173.83	0.05	ORD-101521
1501	52830	1	1	115.29	0.10	ORD-101522
1502	51689	13	2	535.60	0.05	ORD-101523
1503	52374	14	1	215.35	0.00	ORD-101524
1504	53430	11	3	8.95	0.00	ORD-101525
1505	51156	12	5	25.13	0.05	ORD-101526
1506	53155	15	2	82.47	0.15	ORD-101527
1507	54855	1	2	108.71	0.10	ORD-101528
1508	55546	14	1	218.43	0.10	ORD-101529
1509	55642	14	3	219.30	0.00	ORD-101530
1510	50015	1	2	108.26	0.05	ORD-101531
1511	52256	2	3	68.34	0.00	ORD-101532
1512	51690	12	4	25.92	0.00	ORD-101533
1513	50988	18	3	14.65	0.15	ORD-101534
1514	51433	6	3	94.93	0.15	ORD-101535
1515	52385	16	1	613.27	0.00	ORD-101536
1516	52628	7	4	62.77	0.00	ORD-101537
1517	53657	1	2	107.32	0.15	ORD-101538
1518	51674	17	2	425.53	0.15	ORD-101539
1519	54544	18	5	14.64	0.05	ORD-101540
1520	54618	1	1	114.14	0.00	ORD-101541
1521	53248	17	2	430.59	0.00	ORD-101542
1522	55680	2	1	68.86	0.00	ORD-101543
1523	50314	11	4	8.56	0.00	ORD-101544
1524	53865	11	3	8.94	0.05	ORD-101545
1525	52737	5	2	90.52	0.10	ORD-101546
1526	53378	13	1	508.93	0.20	ORD-101547
1527	52104	16	1	639.40	0.05	ORD-101548
1528	55239	5	2	87.45	0.00	ORD-101549
1529	54905	11	5	8.98	0.00	ORD-101550
1530	53658	20	1	345.81	0.05	ORD-101551
1531	52329	13	1	513.70	0.00	ORD-101552
1532	52914	18	2	15.43	0.00	ORD-101553
1533	54512	15	4	79.92	0.00	ORD-101554
1534	50707	20	3	323.73	0.00	ORD-101555
1535	52292	9	6	11.42	0.00	ORD-101556
1536	53014	7	1	61.86	0.10	ORD-101557
1537	50772	1	2	105.00	0.00	ORD-101558
1538	54513	2	1	66.65	0.00	ORD-101559
1539	50989	14	1	203.01	0.00	ORD-101560
1540	52313	13	2	495.17	0.00	ORD-101561
1541	54545	13	3	515.38	0.10	ORD-101562
1542	52110	10	1	185.45	0.05	ORD-101563
1543	53015	8	2	749.14	0.20	ORD-101564
1544	55240	14	2	214.95	0.00	ORD-101565
1545	53659	16	1	635.25	0.10	ORD-101566
1546	50990	4	2	150.17	0.00	ORD-101567
1547	52111	13	1	500.89	0.00	ORD-101568
1548	52293	13	3	515.41	0.10	ORD-101569
1549	50135	3	3	125.59	0.00	ORD-101570
1550	55240	5	1	88.97	0.00	ORD-101571
1551	51150	17	1	419.26	0.15	ORD-101572
1552	51594	9	5	12.56	0.20	ORD-101573
1553	50136	6	1	92.10	0.10	ORD-101574
1554	52068	2	2	68.89	0.00	ORD-101576
1555	51434	6	3	91.47	0.00	ORD-101577
1556	51858	16	1	611.59	0.00	ORD-101578
1557	54326	2	2	67.15	0.15	ORD-101579
1558	52134	12	4	23.97	0.00	ORD-101580
1559	51801	11	5	8.70	0.00	ORD-101581
1560	54018	10	1	184.84	0.00	ORD-101582
1561	53114	11	4	9.43	0.05	ORD-101583
1562	50238	6	1	96.99	0.00	ORD-101585
1563	51120	7	2	57.74	0.05	ORD-101586
1564	53949	5	1	94.26	0.10	ORD-101587
1565	51407	15	1	80.24	0.15	ORD-101588
1566	54619	13	1	507.32	0.00	ORD-101589
1567	53156	12	1	25.10	0.10	ORD-101590
1568	52738	1	1	113.59	0.10	ORD-101591
1569	54326	15	2	80.65	0.00	ORD-101592
1570	54108	10	1	171.69	0.00	ORD-101593
1571	53157	15	1	78.78	0.00	ORD-101594
1572	53311	2	1	68.96	0.20	ORD-101595
1573	54514	7	1	57.81	0.20	ORD-101596
1574	52511	6	1	91.49	0.00	ORD-101597
1575	51394	2	1	67.38	0.00	ORD-101598
1576	50708	18	7	15.63	0.10	ORD-101599
1577	55467	14	1	217.98	0.00	ORD-101600
1578	52598	2	2	67.95	0.00	ORD-101601
1579	52698	12	5	25.72	0.00	ORD-101602
1580	53543	8	2	728.81	0.05	ORD-101603
1581	55083	1	1	105.99	0.05	ORD-101604
1582	52915	15	1	83.31	0.00	ORD-101605
1583	55708	15	1	83.15	0.00	ORD-101606
1584	53725	18	8	15.24	0.05	ORD-101607
1585	50016	3	1	128.66	0.05	ORD-101608
1586	50991	18	5	15.15	0.10	ORD-101609
1587	54320	15	4	80.07	0.00	ORD-101610
1588	54327	17	1	399.90	0.00	ORD-101611
1589	50992	11	4	8.64	0.00	ORD-101612
1590	54527	5	1	91.84	0.10	ORD-101613
1591	50883	11	6	8.97	0.05	ORD-101614
1592	54387	16	1	646.50	0.00	ORD-101615
1593	54342	6	1	94.77	0.00	ORD-101616
1594	50651	1	2	108.17	0.10	ORD-101617
1595	54253	3	2	127.79	0.00	ORD-101618
1596	54359	2	1	70.85	0.00	ORD-101619
1597	51691	8	2	772.32	0.00	ORD-101620
1598	54723	3	2	124.54	0.10	ORD-101621
1599	54776	17	1	407.73	0.10	ORD-101622
1600	54620	3	1	125.44	0.10	ORD-101623
1601	53598	7	3	60.39	0.10	ORD-101624
1602	55084	9	2	11.98	0.05	ORD-101625
1603	53881	6	2	90.86	0.00	ORD-101626
1604	53358	19	1	21.17	0.00	ORD-101627
1605	55745	1	2	110.75	0.10	ORD-101628
1606	53249	17	1	413.73	0.00	ORD-101629
1607	54150	6	3	96.53	0.15	ORD-101630
1608	53660	15	1	79.92	0.15	ORD-101631
1609	50315	4	1	147.58	0.20	ORD-101632
1610	53468	18	3	15.63	0.10	ORD-101633
1611	55745	12	5	26.09	0.05	ORD-101634
1612	53517	13	1	538.77	0.00	ORD-101636
1613	53158	18	3	15.47	0.10	ORD-101637
1614	51353	13	1	545.55	0.00	ORD-101638
1615	53115	12	6	26.00	0.20	ORD-101639
1616	54820	6	4	99.47	0.00	ORD-101640
1617	52488	3	2	136.34	0.05	ORD-101641
1618	51859	5	1	87.88	0.10	ORD-101642
1619	50448	12	8	24.66	0.00	ORD-101643
1620	54465	20	1	339.79	0.00	ORD-101644
1621	50137	10	1	174.38	0.15	ORD-101645
1622	55729	6	3	95.24	0.00	ORD-101646
1623	52447	16	1	626.18	0.15	ORD-101647
1624	55241	5	1	91.11	0.00	ORD-101648
1625	52535	18	6	14.29	0.15	ORD-101649
1626	54621	9	7	12.10	0.05	ORD-101650
1627	55516	16	1	615.49	0.00	ORD-101651
1628	52650	13	1	524.10	0.10	ORD-101652
1629	50080	20	1	327.29	0.00	ORD-101653
1630	50902	7	3	57.54	0.10	ORD-101654
1631	53726	13	2	544.72	0.00	ORD-101655
1632	54906	20	2	323.41	0.00	ORD-101656
1633	53916	3	2	133.43	0.00	ORD-101657
1634	51615	14	1	200.99	0.05	ORD-101658
1635	50709	7	4	60.29	0.00	ORD-101659
1636	54131	1	1	107.21	0.05	ORD-101660
1637	55242	18	5	15.49	0.05	ORD-101661
1638	50640	19	2	22.90	0.15	ORD-101662
1639	54777	15	2	77.27	0.00	ORD-101663
1640	54293	17	2	407.86	0.20	ORD-101664
1641	53661	7	1	57.35	0.00	ORD-101665
1642	51331	12	4	24.53	0.00	ORD-101666
1643	53661	13	2	500.83	0.05	ORD-101667
1644	50138	18	4	15.19	0.00	ORD-101668
1645	53599	9	2	12.21	0.00	ORD-101669
1646	55243	5	1	87.99	0.00	ORD-101670
1647	51709	4	2	145.86	0.00	ORD-101671
1648	51580	1	1	114.38	0.00	ORD-101672
1649	51751	8	2	764.54	0.05	ORD-101673
1650	52954	19	3	22.76	0.15	ORD-101674
1651	55243	5	4	90.09	0.05	ORD-101675
1652	54476	15	3	81.60	0.00	ORD-101676
1653	51247	17	1	411.57	0.00	ORD-101678
1654	52162	9	4	12.09	0.00	ORD-101679
1655	54151	15	2	82.74	0.10	ORD-101681
1656	54989	12	4	25.92	0.00	ORD-101683
1657	55695	2	1	72.54	0.00	ORD-101684
1658	52330	4	3	152.06	0.10	ORD-101685
1659	54576	19	4	23.10	0.15	ORD-101686
1660	53379	11	8	8.58	0.00	ORD-101687
1661	50993	9	5	12.28	0.00	ORD-101688
1662	53803	11	2	8.69	0.00	ORD-101689
1663	50017	17	1	422.71	0.00	ORD-101690
1664	51248	3	2	129.96	0.15	ORD-101691
1665	53016	9	2	12.26	0.00	ORD-101692
1666	54343	20	1	336.99	0.00	ORD-101693
1667	55138	4	1	154.10	0.00	ORD-101694
1668	53866	8	2	775.05	0.00	ORD-101695
1669	54778	14	2	218.57	0.10	ORD-101696
1670	50578	1	1	113.07	0.00	ORD-101697
1671	50994	1	2	110.99	0.00	ORD-101698
1672	54907	9	2	11.47	0.00	ORD-101699
1673	50239	6	2	96.87	0.00	ORD-101700
1674	51435	17	2	431.24	0.00	ORD-101701
1675	51249	7	2	60.48	0.15	ORD-101702
1676	50408	17	1	419.01	0.00	ORD-101703
1677	52135	14	2	217.57	0.00	ORD-101704
1678	55709	8	1	787.30	0.00	ORD-101705
1679	52739	2	1	67.92	0.00	ORD-101706
1680	55746	18	7	15.43	0.10	ORD-101707
1681	54990	11	7	8.80	0.00	ORD-101708
1682	52429	14	2	200.15	0.05	ORD-101709
1683	54254	8	1	717.34	0.05	ORD-101710
1684	54208	19	3	21.95	0.00	ORD-101711
1685	51250	19	2	21.64	0.00	ORD-101712
1686	50995	1	1	108.39	0.00	ORD-101713
1687	54388	12	3	24.30	0.10	ORD-101714
1688	54085	17	1	422.57	0.05	ORD-101715
1689	51251	5	1	90.43	0.00	ORD-101716
1690	54019	13	1	525.39	0.05	ORD-101717
1691	53950	9	2	11.63	0.00	ORD-101718
1692	54321	9	5	11.77	0.00	ORD-101719
1693	52331	6	2	91.04	0.10	ORD-101720
1694	51157	7	2	61.19	0.10	ORD-101721
1695	52812	15	2	79.37	0.00	ORD-101722
1696	50409	17	1	427.51	0.00	ORD-101723
1697	53250	7	2	62.33	0.00	ORD-101724
1698	55681	9	5	11.53	0.15	ORD-101725
1699	55244	6	2	92.93	0.00	ORD-101726
1700	53312	7	3	59.96	0.20	ORD-101727
1701	53017	20	1	341.60	0.15	ORD-101728
1702	51252	18	2	14.57	0.05	ORD-101729
1703	50019	9	3	11.87	0.05	ORD-101730
1704	54477	17	1	423.61	0.00	ORD-101731
1705	53662	1	1	106.34	0.00	ORD-101732
1706	54173	9	4	11.91	0.00	ORD-101733
1707	53251	13	1	542.12	0.15	ORD-101734
1708	54748	6	2	97.75	0.15	ORD-101735
1709	52257	15	1	81.98	0.00	ORD-101736
1710	50018	18	4	14.62	0.00	ORD-101737
1711	55245	1	1	113.81	0.10	ORD-101738
1712	54360	18	6	15.18	0.00	ORD-101739
1713	53600	18	3	14.33	0.10	ORD-101740
1714	54622	5	2	87.41	0.00	ORD-101741
1715	52302	5	1	86.29	0.00	ORD-101742
1716	54451	10	3	184.45	0.00	ORD-101743
1717	51253	4	1	155.17	0.10	ORD-101744
1718	51436	10	1	177.41	0.00	ORD-101745
1719	55619	7	1	58.91	0.00	ORD-101746
1720	53018	17	1	430.24	0.00	ORD-101747
1721	55059	15	3	83.40	0.05	ORD-101748
1722	54623	19	1	21.19	0.00	ORD-101749
1723	54724	7	3	61.98	0.00	ORD-101750
1724	50205	2	2	71.05	0.00	ORD-101751
1725	51367	16	1	671.49	0.10	ORD-101752
1726	53882	13	1	502.05	0.10	ORD-101753
1727	50996	14	1	208.65	0.10	ORD-101754
1728	51860	3	2	133.06	0.00	ORD-101755
1729	50385	1	1	111.42	0.00	ORD-101756
1730	53090	9	3	12.36	0.00	ORD-101757
1731	50710	3	1	123.88	0.05	ORD-101758
1732	51437	16	1	610.45	0.15	ORD-101759
1733	54908	4	2	147.78	0.00	ORD-101760
1734	54856	2	1	69.65	0.05	ORD-101761
1735	50997	12	4	24.71	0.15	ORD-101762
1736	50755	16	1	620.13	0.00	ORD-101763
1737	53019	12	5	25.19	0.00	ORD-101764
1738	55517	19	2	22.03	0.00	ORD-101765
1739	54665	9	7	11.65	0.10	ORD-101766
1740	53951	12	3	25.82	0.10	ORD-101767
1741	53020	16	1	612.72	0.00	ORD-101768
1742	51342	8	1	752.72	0.10	ORD-101769
1743	51716	12	2	25.69	0.20	ORD-101770
1744	53867	7	2	58.75	0.00	ORD-101771
1745	52069	14	1	210.70	0.10	ORD-101772
1746	54209	9	2	12.56	0.15	ORD-101773
1747	51438	16	1	639.68	0.05	ORD-101774
1748	54779	12	2	26.22	0.10	ORD-101775
1749	52686	3	2	135.12	0.05	ORD-101776
1750	50081	12	3	26.00	0.00	ORD-101777
1751	52163	6	2	93.09	0.10	ORD-101778
1752	52975	12	3	23.90	0.00	ORD-101779
1753	52599	8	2	783.69	0.10	ORD-101780
1754	53159	13	1	525.07	0.10	ORD-101781
1755	52229	5	1	87.23	0.10	ORD-101782
1756	52038	17	1	439.60	0.05	ORD-101783
1757	50903	14	1	220.23	0.05	ORD-101784
1758	50748	3	1	133.75	0.00	ORD-101785
1759	54991	19	2	21.34	0.15	ORD-101786
1760	50240	15	1	77.30	0.00	ORD-101787
1761	51254	13	1	526.20	0.05	ORD-101788
1762	55778	9	1	12.03	0.00	ORD-101789
1763	53804	8	1	755.81	0.05	ORD-101790
1764	53518	2	1	70.52	0.15	ORD-101791
1765	50480	2	2	66.61	0.10	ORD-101792
1766	50316	11	4	9.07	0.05	ORD-101793
1767	52386	15	3	80.66	0.05	ORD-101794
1768	54132	14	2	219.96	0.00	ORD-101795
1769	51802	8	1	785.87	0.00	ORD-101796
1770	54909	9	3	11.89	0.10	ORD-101797
1771	55085	10	1	182.13	0.00	ORD-101798
1772	51861	4	1	146.40	0.10	ORD-101799
1773	53400	15	1	80.37	0.10	ORD-101800
1774	54992	14	2	207.90	0.15	ORD-101801
1775	54065	13	2	532.49	0.15	ORD-101802
1776	54910	2	2	67.75	0.15	ORD-101803
1777	51862	13	2	502.32	0.10	ORD-101804
1778	53252	5	1	88.98	0.20	ORD-101805
1779	50998	9	3	11.50	0.15	ORD-101806
1780	50317	18	3	15.41	0.10	ORD-101807
1781	54577	1	1	107.28	0.05	ORD-101808
1782	50139	17	1	422.35	0.15	ORD-101809
1783	52600	5	2	89.97	0.15	ORD-101810
1784	50449	11	3	9.40	0.15	ORD-101811
1785	52565	16	1	654.31	0.05	ORD-101812
1786	52332	6	5	93.70	0.15	ORD-101813
1787	53021	20	1	337.61	0.05	ORD-101814
1788	50843	19	1	21.06	0.00	ORD-101815
1789	50773	6	1	90.27	0.10	ORD-101816
1790	50082	1	1	112.86	0.00	ORD-101817
1791	53349	2	1	67.80	0.05	ORD-101818
1792	51439	10	2	183.67	0.00	ORD-101819
1793	55086	2	2	71.24	0.10	ORD-101820
1794	55620	2	2	72.97	0.15	ORD-101821
1795	50520	9	6	11.66	0.05	ORD-101822
1796	52136	8	1	718.54	0.10	ORD-101823
1797	53852	13	3	543.62	0.00	ORD-101824
1798	51255	20	3	339.92	0.10	ORD-101825
1799	51408	11	3	8.55	0.00	ORD-101826
1800	50999	14	2	214.29	0.15	ORD-101827
1801	50450	7	1	62.24	0.05	ORD-101828
1802	55682	15	2	83.48	0.05	ORD-101829
1803	54328	12	2	24.19	0.10	ORD-101830
1804	50441	14	1	218.36	0.10	ORD-101831
1805	51616	20	1	345.91	0.00	ORD-101832
1806	53160	7	3	62.11	0.20	ORD-101833
1807	50318	13	2	533.65	0.15	ORD-101834
1808	55246	18	1	15.75	0.15	ORD-101835
1809	55246	18	4	15.15	0.10	ORD-101836
1810	53253	9	3	11.80	0.00	ORD-101837
1811	54174	9	8	11.69	0.00	ORD-101838
1812	54993	12	7	24.86	0.10	ORD-101839
1813	53576	12	2	24.39	0.05	ORD-101840
1814	51208	14	1	204.17	0.05	ORD-101841
1815	53805	12	2	23.76	0.10	ORD-101842
1816	54066	20	4	315.46	0.15	ORD-101843
1817	52860	7	3	57.88	0.10	ORD-101844
1818	51000	18	3	15.30	0.00	ORD-101845
1819	51409	4	1	146.94	0.15	ORD-101846
1820	52687	2	1	69.93	0.00	ORD-101847
1821	54020	11	5	8.61	0.10	ORD-101848
1822	53022	20	2	335.88	0.20	ORD-101849
1823	50241	15	2	81.70	0.00	ORD-101851
1824	54994	13	4	505.45	0.05	ORD-101852
1825	53727	11	5	8.90	0.00	ORD-101853
1826	51001	12	1	25.79	0.00	ORD-101854
1827	51595	12	4	24.43	0.00	ORD-101855
1828	52294	11	3	8.98	0.00	ORD-101856
1829	53601	5	1	90.47	0.10	ORD-101857
1830	50711	15	1	76.56	0.10	ORD-101858
1831	54432	9	6	12.31	0.05	ORD-101859
1832	55738	5	1	86.84	0.00	ORD-101860
1833	53023	13	4	502.05	0.05	ORD-101861
1834	52430	10	2	175.64	0.20	ORD-101862
1835	51519	18	5	15.57	0.05	ORD-101863
1836	51332	19	1	21.08	0.10	ORD-101864
1837	55710	18	2	14.32	0.10	ORD-101865
1838	55247	13	2	543.00	0.05	ORD-101866
1839	54192	13	1	523.45	0.00	ORD-101867
1840	53495	1	1	111.49	0.05	ORD-101868
1841	50481	1	1	113.32	0.20	ORD-101869
1842	51735	5	2	90.39	0.15	ORD-101870
1843	51121	16	2	616.81	0.10	ORD-101872
1844	53910	6	2	94.92	0.10	ORD-101873
1845	53663	13	1	508.99	0.15	ORD-101874
1846	53313	15	1	81.11	0.15	ORD-101875
1847	51190	2	1	68.48	0.15	ORD-101876
1848	53254	9	5	11.59	0.00	ORD-101877
1849	51158	17	1	413.32	0.20	ORD-101878
1850	52536	12	3	24.79	0.10	ORD-101879
1851	51641	16	1	628.23	0.00	ORD-101880
1852	51774	14	1	213.74	0.10	ORD-101881
1853	51002	1	3	106.53	0.15	ORD-101882
1854	51191	1	3	112.27	0.00	ORD-101883
1855	50430	4	2	148.35	0.05	ORD-101884
1856	55754	15	3	76.69	0.15	ORD-101885
1857	55779	4	2	147.31	0.05	ORD-101886
1858	54687	4	4	152.10	0.00	ORD-101887
1859	54749	3	2	127.01	0.10	ORD-101888
1860	52861	14	1	201.01	0.05	ORD-101889
1861	50051	1	1	114.41	0.05	ORD-101890
1862	54175	9	2	11.93	0.00	ORD-101891
1863	52431	10	2	173.02	0.00	ORD-101892
1864	53161	3	1	135.32	0.00	ORD-101893
1865	53664	13	3	544.61	0.00	ORD-101894
1866	52537	17	1	412.07	0.05	ORD-101895
1867	52862	2	2	67.44	0.00	ORD-101896
1868	50626	19	1	21.52	0.00	ORD-101897
1869	53496	18	8	15.18	0.00	ORD-101898
1870	52688	11	3	8.59	0.00	ORD-101899
1871	50904	6	1	91.28	0.00	ORD-101900
1872	55248	20	1	339.68	0.00	ORD-101901
1873	50020	6	1	90.92	0.00	ORD-101902
1874	51209	11	2	9.06	0.00	ORD-101903
1875	55562	1	1	111.65	0.00	ORD-101904
1876	51440	1	1	108.96	0.05	ORD-101905
1877	50786	8	1	756.87	0.15	ORD-101906
1878	52976	19	4	22.43	0.00	ORD-101907
1879	50844	8	2	769.32	0.05	ORD-101908
1880	53162	13	1	512.99	0.00	ORD-101909
1881	51520	7	2	59.75	0.00	ORD-101910
1882	50797	13	2	540.44	0.00	ORD-101911
1883	54911	12	3	24.96	0.00	ORD-101912
1884	53806	5	1	92.32	0.00	ORD-101913
1885	51999	14	1	217.95	0.10	ORD-101914
1886	52371	13	4	494.79	0.00	ORD-101915
1887	52916	3	1	124.01	0.10	ORD-101916
1888	50537	8	1	739.87	0.05	ORD-101917
1889	52489	14	1	216.80	0.05	ORD-101918
1890	53431	12	3	25.72	0.00	ORD-101919
1891	53807	5	1	93.06	0.00	ORD-101920
1892	54912	20	1	323.05	0.00	ORD-101921
1893	54021	12	3	24.92	0.00	ORD-101922
1894	50579	19	2	21.98	0.05	ORD-101923
1895	53665	7	2	57.99	0.00	ORD-101924
1896	55249	5	2	91.55	0.20	ORD-101925
1897	54022	2	1	71.55	0.00	ORD-101926
1898	54478	19	4	22.29	0.10	ORD-101927
1899	50627	17	1	411.38	0.05	ORD-101928
1900	53163	9	1	12.07	0.00	ORD-101929
1901	54780	13	2	509.33	0.00	ORD-101930
1902	54255	7	1	61.16	0.00	ORD-101931
1903	50096	4	2	154.21	0.15	ORD-101932
1904	54963	16	1	640.35	0.00	ORD-101933
1905	51803	4	2	150.18	0.00	ORD-101934
1906	53808	17	2	430.50	0.05	ORD-101935
1907	52203	1	3	106.12	0.00	ORD-101936
1908	54344	8	1	767.70	0.05	ORD-101937
1909	53872	14	2	206.06	0.00	ORD-101938
1910	50845	15	3	83.47	0.00	ORD-101939
1911	52651	15	1	76.98	0.05	ORD-101940
1912	54781	3	1	125.16	0.10	ORD-101941
1913	52977	20	1	332.17	0.00	ORD-101942
1914	50521	15	3	79.96	0.00	ORD-101943
1915	52216	20	1	333.30	0.05	ORD-101944
1916	54996	10	1	175.13	0.10	ORD-101945
1917	50319	20	1	320.54	0.00	ORD-101946
1918	54814	12	5	25.49	0.00	ORD-101947
1919	54995	20	3	344.36	0.00	ORD-101948
1920	55547	19	2	21.30	0.05	ORD-101949
1921	55250	4	2	150.27	0.05	ORD-101950
1922	52652	18	3	14.30	0.00	ORD-101951
1923	54345	3	1	133.31	0.00	ORD-101952
1924	53952	4	1	156.82	0.10	ORD-101953
1925	55468	10	1	187.19	0.00	ORD-101954
1926	52137	20	2	345.13	0.00	ORD-101955
1927	51642	6	2	91.74	0.00	ORD-101956
1928	54210	9	3	11.56	0.00	ORD-101957
1929	54479	14	1	202.06	0.05	ORD-101958
1930	50320	11	1	8.56	0.00	ORD-101959
1931	52601	2	3	69.48	0.00	ORD-101960
1932	54389	8	1	754.11	0.00	ORD-101961
1933	53561	17	2	436.24	0.05	ORD-101962
1934	52164	10	1	180.02	0.10	ORD-101963
1935	55251	10	3	179.72	0.05	ORD-101964
1936	55252	7	1	61.17	0.00	ORD-101965
1937	53432	8	2	750.94	0.00	ORD-101966
1938	50815	20	2	339.86	0.00	ORD-101967
1939	51682	17	2	427.67	0.05	ORD-101968
1940	52978	11	2	9.20	0.05	ORD-101969
1941	52917	6	2	93.46	0.00	ORD-101970
1942	54452	1	1	112.76	0.05	ORD-101971
1943	54256	20	1	313.88	0.00	ORD-101972
1944	54857	18	2	14.60	0.20	ORD-101973
1945	54599	13	1	518.22	0.00	ORD-101974
1946	50652	14	1	213.46	0.00	ORD-101975
1947	53401	6	2	98.26	0.00	ORD-101976
1948	52653	4	1	142.61	0.00	ORD-101977
1949	52165	19	2	21.60	0.00	ORD-101978
1950	54857	16	1	637.35	0.00	ORD-101979
1951	51256	18	4	14.89	0.00	ORD-101980
1952	53255	5	1	86.92	0.15	ORD-101981
1953	55595	17	1	428.51	0.00	ORD-101982
1954	53433	17	2	418.82	0.10	ORD-101983
1955	54558	10	1	173.33	0.05	ORD-101984
1956	51752	4	1	143.42	0.00	ORD-101985
1957	50287	11	3	9.22	0.00	ORD-101986
1958	54023	2	2	66.54	0.05	ORD-101987
1959	53380	16	1	660.42	0.15	ORD-101988
1960	50798	12	6	25.04	0.20	ORD-101989
1961	51003	14	1	201.06	0.05	ORD-101990
1962	53853	17	3	423.62	0.20	ORD-101991
1963	54433	11	3	8.96	0.00	ORD-101992
1964	53728	1	1	109.98	0.15	ORD-101993
1965	50905	15	2	76.51	0.15	ORD-101994
1966	51863	9	3	12.30	0.05	ORD-101995
1967	50653	11	2	8.69	0.20	ORD-101996
1968	52466	5	2	92.80	0.15	ORD-101997
1969	55253	7	1	59.74	0.05	ORD-101998
1970	50321	20	2	314.57	0.05	ORD-101999
1971	51825	2	2	68.94	0.10	ORD-102000
1972	55253	11	2	9.43	0.00	ORD-102001
1973	53164	20	1	337.37	0.00	ORD-102002
1974	50680	4	1	155.15	0.20	ORD-102003
1975	55434	16	1	626.61	0.00	ORD-102004
1976	55755	8	2	773.32	0.00	ORD-102005
1977	54211	15	2	77.72	0.00	ORD-102006
1978	54528	15	3	83.93	0.00	ORD-102007
1979	55596	6	2	98.32	0.15	ORD-102008
1980	52918	7	1	59.49	0.15	ORD-102009
1981	54176	5	1	93.60	0.00	ORD-102010
1982	54750	12	3	26.23	0.15	ORD-102011
1983	52831	4	2	154.76	0.05	ORD-102012
1984	54086	12	3	25.63	0.00	ORD-102013
1985	54052	9	4	11.79	0.05	ORD-102014
1986	50220	2	1	73.05	0.00	ORD-102015
1987	50686	10	1	182.39	0.05	ORD-102016
1988	50846	1	2	105.83	0.05	ORD-102017
1989	50451	15	1	79.64	0.05	ORD-102018
1990	51159	9	1	12.47	0.05	ORD-102019
1991	53256	13	1	524.74	0.00	ORD-102020
1992	53165	17	1	403.84	0.00	ORD-102021
1993	50141	11	4	8.66	0.15	ORD-102023
1994	51643	17	1	421.02	0.05	ORD-102024
1995	50538	14	1	204.62	0.05	ORD-102025
1996	51441	2	1	67.23	0.10	ORD-102026
1997	51441	1	1	112.30	0.00	ORD-102027
1998	54294	7	1	60.40	0.05	ORD-102028
1999	50140	5	1	88.41	0.05	ORD-102029
2000	50654	1	2	114.70	0.00	ORD-102030
2001	55435	20	2	346.18	0.10	ORD-102032
2002	51004	8	1	735.65	0.00	ORD-102033
2003	50452	2	1	73.31	0.00	ORD-102034
2004	54295	12	5	24.71	0.15	ORD-102035
2005	51521	4	1	149.57	0.20	ORD-102036
2006	54024	9	3	12.49	0.00	ORD-102037
2007	53434	7	1	57.11	0.00	ORD-102038
2008	55139	17	1	434.11	0.15	ORD-102039
2009	52070	9	1	12.00	0.05	ORD-102040
2010	50906	11	4	9.29	0.00	ORD-102041
2011	54624	5	2	93.91	0.00	ORD-102042
2012	54913	18	2	14.45	0.00	ORD-102043
2013	55254	6	2	97.45	0.00	ORD-102044
2014	55087	8	1	767.92	0.00	ORD-102045
2015	54821	14	1	212.55	0.05	ORD-102046
2016	50322	9	5	12.40	0.00	ORD-102047
2017	50410	15	2	76.50	0.05	ORD-102048
2018	54212	13	1	510.38	0.05	ORD-102049
2019	51160	18	7	14.63	0.10	ORD-102050
2020	52016	18	4	14.42	0.05	ORD-102051
2021	51864	4	1	142.83	0.00	ORD-102052
2022	54434	9	4	11.73	0.10	ORD-102053
2023	53359	11	4	9.29	0.00	ORD-102054
2024	50799	19	2	22.83	0.15	ORD-102055
2025	55548	12	4	25.23	0.15	ORD-102056
2026	54997	11	3	8.78	0.00	ORD-102057
2027	55597	1	1	110.31	0.00	ORD-102058
2028	51257	12	1	26.07	0.00	ORD-102059
2029	50323	18	5	14.28	0.15	ORD-102060
2030	53360	18	6	15.46	0.00	ORD-102061
2031	55580	12	2	24.66	0.20	ORD-102062
2032	51865	7	2	58.02	0.00	ORD-102063
2033	52755	7	5	57.86	0.05	ORD-102064
2034	52756	9	3	12.03	0.00	ORD-102065
2035	50800	15	3	82.91	0.00	ORD-102066
2036	55563	1	3	110.65	0.10	ORD-102067
2037	55469	14	1	203.10	0.05	ORD-102068
2038	54578	6	2	97.36	0.05	ORD-102069
2039	53868	12	5	25.25	0.00	ORD-102070
2040	54025	13	2	542.20	0.00	ORD-102071
2041	54998	9	4	11.48	0.00	ORD-102072
2042	55816	9	4	12.43	0.00	ORD-102073
2043	51136	7	2	61.54	0.00	ORD-102074
2044	51498	20	1	329.67	0.00	ORD-102075
2045	51644	17	2	428.96	0.00	ORD-102076
2046	52166	17	1	435.66	0.00	ORD-102077
2047	50206	4	1	155.58	0.00	ORD-102078
2048	53116	12	4	25.46	0.00	ORD-102079
2049	53771	19	2	21.52	0.00	ORD-102080
2050	54782	9	5	12.40	0.05	ORD-102081
2051	52979	6	4	97.98	0.00	ORD-102082
2052	53666	11	5	8.97	0.00	ORD-102083
2053	52071	2	1	72.23	0.00	ORD-102084
2054	53166	16	1	651.79	0.05	ORD-102085
2055	51258	8	2	765.86	0.00	ORD-102086
2056	52432	16	1	661.54	0.15	ORD-102087
2057	51343	2	2	69.45	0.05	ORD-102088
2058	52258	15	1	78.88	0.00	ORD-102089
2059	55255	15	3	79.01	0.00	ORD-102090
2060	50847	13	1	520.96	0.00	ORD-102091
2061	51645	3	2	131.80	0.00	ORD-102092
2062	54999	17	2	436.97	0.00	ORD-102093
2063	50522	9	4	11.89	0.00	ORD-102094
2064	50324	5	2	91.85	0.00	ORD-102095
2065	53544	11	3	9.01	0.00	ORD-102096
2066	51826	12	4	24.74	0.00	ORD-102097
2067	52167	6	1	99.41	0.00	ORD-102098
2068	54625	5	3	93.29	0.00	ORD-102099
2069	50142	12	7	25.23	0.00	ORD-102100
2070	55643	4	1	144.23	0.00	ORD-102101
2071	53469	17	1	410.54	0.05	ORD-102102
2072	53435	4	1	156.56	0.10	ORD-102103
2073	51005	2	1	68.81	0.05	ORD-102104
2074	51005	1	1	114.73	0.15	ORD-102105
2075	50143	20	1	321.06	0.00	ORD-102106
2076	51717	2	1	73.39	0.00	ORD-102107
2077	53883	9	6	11.73	0.00	ORD-102108
2078	55499	14	1	203.06	0.05	ORD-102109
2079	50553	1	1	109.82	0.05	ORD-102110
2080	54053	12	1	24.11	0.00	ORD-102111
2081	50021	12	6	24.09	0.00	ORD-102112
2082	50801	5	1	88.19	0.05	ORD-102113
2083	53953	6	1	99.74	0.10	ORD-102114
2084	51442	13	3	539.88	0.00	ORD-102115
2085	55257	12	2	24.27	0.05	ORD-102116
2086	52555	3	1	132.30	0.15	ORD-102117
2087	54026	10	1	173.59	0.00	ORD-102118
2088	50655	14	2	212.13	0.00	ORD-102119
2089	55256	1	2	113.19	0.00	ORD-102120
2090	54152	12	4	25.11	0.00	ORD-102121
2091	55598	13	1	533.08	0.00	ORD-102122
2092	53314	19	3	21.28	0.10	ORD-102123
2093	51646	1	1	104.71	0.15	ORD-102124
2094	55000	3	2	125.22	0.05	ORD-102125
2095	50821	18	3	15.35	0.00	ORD-102126
2096	50580	9	3	11.48	0.00	ORD-102127
2097	55258	18	4	15.67	0.00	ORD-102128
2098	52919	12	4	26.13	0.00	ORD-102129
2099	50097	3	1	124.49	0.05	ORD-102130
2100	53602	18	7	14.76	0.00	ORD-102131
2101	53257	5	2	94.02	0.05	ORD-102132
2102	51006	8	2	740.72	0.00	ORD-102133
2103	52699	4	1	143.46	0.00	ORD-102134
2104	50687	11	3	8.81	0.00	ORD-102135
2105	51617	15	3	81.21	0.10	ORD-102136
2106	53436	8	1	781.44	0.05	ORD-102137
2107	53954	11	5	8.68	0.00	ORD-102138
2108	52700	15	3	80.15	0.00	ORD-102139
2109	52586	9	9	11.67	0.00	ORD-102140
2110	53729	5	1	87.52	0.05	ORD-102141
2111	51161	13	2	543.21	0.00	ORD-102142
2112	53091	11	6	9.05	0.05	ORD-102143
2113	50288	18	7	15.50	0.10	ORD-102144
2114	54296	13	1	538.69	0.10	ORD-102145
2115	55002	4	1	148.86	0.10	ORD-102146
2116	53258	8	1	755.62	0.10	ORD-102147
2117	55001	2	1	69.01	0.15	ORD-102148
2118	53024	7	3	61.55	0.15	ORD-102149
2119	50289	18	4	15.49	0.00	ORD-102150
2120	55564	5	4	92.64	0.15	ORD-102151
2121	53854	20	1	334.09	0.05	ORD-102152
2122	52718	14	1	204.68	0.00	ORD-102153
2123	50411	11	4	8.63	0.00	ORD-102155
2124	52467	10	2	179.46	0.00	ORD-102156
2125	50656	18	3	15.10	0.10	ORD-102157
2126	51007	14	1	211.59	0.15	ORD-102158
2127	51259	11	8	9.14	0.00	ORD-102159
2128	53809	18	6	15.34	0.05	ORD-102160
2129	54390	13	2	494.99	0.00	ORD-102161
2130	54559	11	3	8.91	0.05	ORD-102162
2131	52490	18	5	15.56	0.05	ORD-102163
2132	50712	14	1	219.59	0.10	ORD-102164
2133	53315	17	1	437.98	0.00	ORD-102165
2134	53167	12	1	25.52	0.00	ORD-102166
2135	51260	19	3	22.87	0.05	ORD-102167
2136	50242	12	4	25.05	0.05	ORD-102168
2137	55259	18	8	15.66	0.15	ORD-102169
2138	51443	15	2	82.45	0.00	ORD-102170
2139	50431	14	1	209.99	0.05	ORD-102171
2140	54858	20	2	320.96	0.10	ORD-102172
2141	51499	10	1	187.73	0.10	ORD-102173
2142	53168	14	2	215.04	0.15	ORD-102174
2143	55491	7	4	59.74	0.20	ORD-102175
2144	50067	16	1	646.87	0.00	ORD-102176
2145	51192	2	1	68.49	0.05	ORD-102177
2146	50907	2	2	70.73	0.00	ORD-102178
2147	51008	10	1	187.65	0.00	ORD-102179
2148	53169	20	1	329.64	0.00	ORD-102180
2149	55470	18	4	15.10	0.00	ORD-102181
2150	53025	6	3	93.85	0.00	ORD-102182
2151	52654	13	1	519.47	0.10	ORD-102183
2152	51963	6	3	90.34	0.15	ORD-102184
2153	52333	15	2	83.04	0.00	ORD-102185
2154	53470	8	2	783.89	0.05	ORD-102186
2155	52448	19	1	22.56	0.20	ORD-102187
2156	54435	19	2	22.26	0.00	ORD-102188
2157	55711	18	2	15.69	0.00	ORD-102189
2158	53955	8	3	781.50	0.05	ORD-102190
2159	55456	5	1	93.19	0.00	ORD-102191
2160	51805	18	5	15.21	0.00	ORD-102192
2161	54297	15	2	76.02	0.10	ORD-102193
2162	52701	14	1	211.74	0.00	ORD-102194
2163	51009	15	2	81.45	0.00	ORD-102195
2164	51804	9	4	12.11	0.00	ORD-102196
2165	55156	13	1	537.55	0.00	ORD-102197
2166	51010	20	2	326.92	0.00	ORD-102198
2167	54914	19	1	22.61	0.05	ORD-102199
2168	54626	6	2	90.64	0.00	ORD-102200
2169	51444	4	1	145.62	0.00	ORD-102201
2170	52689	10	1	179.95	0.00	ORD-102202
2171	55088	14	1	200.45	0.00	ORD-102203
2172	55768	11	5	9.39	0.15	ORD-102204
2173	54177	17	1	419.76	0.05	ORD-102205
2174	50581	5	1	88.13	0.00	ORD-102206
2175	54592	6	2	99.10	0.05	ORD-102207
2176	50144	8	1	725.21	0.00	ORD-102208
2177	52512	3	3	131.02	0.20	ORD-102209
2178	50713	5	1	93.20	0.10	ORD-102210
2179	52418	11	2	8.96	0.00	ORD-102211
2180	53730	8	1	770.99	0.00	ORD-102212
2181	53316	2	2	67.27	0.15	ORD-102213
2182	51445	19	3	21.77	0.00	ORD-102214
2183	52602	12	7	25.80	0.10	ORD-102215
2184	55260	18	3	15.24	0.00	ORD-102216
2185	55260	3	1	128.87	0.00	ORD-102217
2186	54822	14	1	201.41	0.00	ORD-102218
2187	54213	17	2	407.48	0.00	ORD-102219
2188	53402	17	1	406.63	0.05	ORD-102220
2189	51647	19	3	21.11	0.10	ORD-102221
2190	52724	16	2	608.98	0.15	ORD-102222
2191	53731	8	1	737.67	0.10	ORD-102223
2192	53259	7	2	59.31	0.10	ORD-102224
2193	52813	7	2	59.62	0.00	ORD-102225
2194	54391	18	6	14.66	0.15	ORD-102226
2195	51964	11	2	9.45	0.00	ORD-102227
2196	54118	1	1	112.74	0.00	ORD-102228
2197	53260	2	1	66.72	0.00	ORD-102229
2198	53170	15	3	79.65	0.00	ORD-102230
2199	51753	12	3	25.08	0.05	ORD-102231
2200	51162	12	3	25.84	0.10	ORD-102232
2201	54579	18	5	14.66	0.05	ORD-102233
2202	51011	13	1	509.29	0.15	ORD-102234
2203	54627	7	2	59.74	0.00	ORD-102235
2204	52334	5	1	91.06	0.00	ORD-102236
2205	53667	13	1	538.09	0.15	ORD-102237
2206	52832	20	1	341.03	0.00	ORD-102238
2207	52168	9	5	11.98	0.10	ORD-102239
2208	50068	1	1	113.47	0.10	ORD-102240
2209	53956	16	1	612.87	0.05	ORD-102241
2210	52168	20	1	326.30	0.05	ORD-102242
2211	51736	3	1	134.99	0.05	ORD-102244
2212	51775	12	7	25.22	0.00	ORD-102245
2213	51866	1	1	114.93	0.20	ORD-102246
2214	55599	2	2	73.36	0.00	ORD-102247
2215	54067	9	2	11.53	0.05	ORD-102248
2216	55565	8	1	725.90	0.05	ORD-102249
2217	51596	4	2	149.33	0.05	ORD-102250
2218	51754	16	1	652.78	0.20	ORD-102252
2219	51446	9	4	12.44	0.00	ORD-102253
2220	50069	5	1	93.63	0.10	ORD-102254
2221	54087	18	3	14.74	0.00	ORD-102255
2222	52072	7	1	62.47	0.05	ORD-102256
2223	53884	12	6	24.74	0.10	ORD-102257
2224	51261	2	2	66.90	0.05	ORD-102258
2225	54628	12	8	26.05	0.05	ORD-102259
2226	55644	5	2	86.07	0.00	ORD-102260
2227	51122	3	2	124.95	0.00	ORD-102261
2228	55666	10	2	184.56	0.00	ORD-102262
2229	50325	19	2	22.17	0.05	ORD-102263
2230	51648	9	4	11.85	0.10	ORD-102264
2231	50083	9	4	11.83	0.05	ORD-102265
2232	53026	14	3	217.07	0.00	ORD-102266
2233	52980	20	1	317.74	0.00	ORD-102267
2234	55780	7	1	62.96	0.00	ORD-102268
2235	50606	7	2	59.68	0.00	ORD-102269
2236	54257	18	3	15.01	0.15	ORD-102270
2237	52112	18	5	15.68	0.00	ORD-102271
2238	52920	14	3	210.95	0.00	ORD-102272
2239	51012	12	5	26.10	0.00	ORD-102273
2240	50243	13	1	528.73	0.05	ORD-102274
2241	55660	12	2	23.80	0.10	ORD-102275
2242	52740	19	2	21.88	0.00	ORD-102277
2243	51867	6	3	92.50	0.00	ORD-102278
2244	55645	4	1	144.95	0.00	ORD-102279
2245	52833	1	1	107.47	0.05	ORD-102280
2246	51013	18	4	14.94	0.15	ORD-102281
2247	53519	10	1	173.99	0.00	ORD-102282
2248	52603	9	3	12.59	0.00	ORD-102283
2249	55500	19	2	21.70	0.05	ORD-102284
2250	51649	14	1	215.66	0.00	ORD-102285
2251	51344	2	2	72.67	0.00	ORD-102286
2252	53603	6	2	96.13	0.10	ORD-102287
2253	53471	6	3	95.35	0.15	ORD-102288
2254	51123	11	2	9.20	0.10	ORD-102289
2255	53810	12	7	24.65	0.00	ORD-102290
2256	55262	10	1	172.65	0.00	ORD-102291
2257	52863	18	4	15.01	0.00	ORD-102292
2258	53901	11	3	8.67	0.00	ORD-102293
2259	55261	8	1	775.56	0.20	ORD-102294
2260	52259	5	1	90.07	0.00	ORD-102295
2261	52719	12	5	24.27	0.00	ORD-102296
2262	55263	20	1	318.12	0.15	ORD-102297
2263	53917	10	1	174.11	0.00	ORD-102298
2264	54725	8	1	722.24	0.10	ORD-102299
2265	53520	2	2	69.66	0.10	ORD-102300
2266	53668	9	2	11.77	0.10	ORD-102301
2267	50822	9	3	11.63	0.00	ORD-102302
2268	55696	5	2	87.59	0.00	ORD-102303
2269	54521	20	1	318.71	0.00	ORD-102304
2270	53811	11	5	8.63	0.05	ORD-102305
2271	50454	18	2	15.40	0.15	ORD-102306
2272	55518	2	1	70.85	0.00	ORD-102307
2273	54298	7	2	61.56	0.00	ORD-102308
2274	55471	9	3	12.26	0.15	ORD-102309
2275	55264	16	1	610.88	0.00	ORD-102310
2276	52387	9	3	11.82	0.00	ORD-102311
2277	52814	9	4	12.53	0.15	ORD-102312
2278	54299	7	3	57.66	0.15	ORD-102313
2279	50539	6	2	92.32	0.05	ORD-102314
2280	50453	13	1	542.47	0.00	ORD-102315
2281	55730	13	2	499.66	0.00	ORD-102316
2282	53027	18	5	15.63	0.00	ORD-102317
2283	51014	10	1	176.73	0.00	ORD-102318
2284	52433	16	1	649.67	0.00	ORD-102319
2285	52388	6	1	91.69	0.05	ORD-102320
2286	52921	13	1	521.25	0.00	ORD-102321
2287	50848	16	1	657.08	0.05	ORD-102322
2288	52260	12	3	24.20	0.00	ORD-102323
2289	52375	7	4	58.61	0.00	ORD-102324
2290	54193	12	8	24.98	0.00	ORD-102325
2291	55266	5	2	91.67	0.00	ORD-102326
2292	55501	10	1	179.32	0.05	ORD-102327
2293	50554	9	5	12.44	0.15	ORD-102328
2294	52776	13	1	497.06	0.00	ORD-102329
2295	55265	18	2	15.34	0.05	ORD-102330
2296	50628	9	5	11.87	0.00	ORD-102331
2297	51868	8	1	752.10	0.00	ORD-102332
2298	50326	5	2	88.77	0.10	ORD-102333
2299	54580	9	4	12.17	0.00	ORD-102334
2300	55003	12	5	24.08	0.15	ORD-102335
2301	50638	16	1	628.87	0.00	ORD-102336
2302	52513	1	1	111.13	0.00	ORD-102337
2303	53926	13	1	499.83	0.10	ORD-102338
2304	50849	4	1	152.62	0.00	ORD-102339
2305	54915	19	1	21.69	0.15	ORD-102340
2306	54480	4	1	152.63	0.20	ORD-102341
2307	50145	19	2	23.03	0.05	ORD-102342
2308	54329	1	1	106.48	0.00	ORD-102343
2309	50908	18	3	15.32	0.15	ORD-102344
2310	54823	15	2	81.93	0.00	ORD-102345
2311	50774	4	1	153.15	0.00	ORD-102346
2312	51015	6	2	94.95	0.05	ORD-102347
2313	54783	12	3	24.81	0.05	ORD-102348
2314	50290	18	2	15.00	0.10	ORD-102349
2315	51447	12	4	25.15	0.05	ORD-102350
2316	55472	10	1	185.49	0.00	ORD-102351
2317	54258	18	2	15.68	0.20	ORD-102352
2318	50098	3	1	130.84	0.00	ORD-102353
2319	50714	5	1	93.09	0.15	ORD-102354
2320	54546	19	1	21.20	0.00	ORD-102355
2321	52834	18	4	15.01	0.00	ORD-102356
2322	52073	4	2	146.78	0.10	ORD-102357
2323	52815	2	2	67.04	0.15	ORD-102358
2324	53472	17	1	412.82	0.20	ORD-102359
2325	53812	18	3	14.58	0.10	ORD-102360
2326	52261	8	2	779.15	0.10	ORD-102361
2327	50850	15	3	76.90	0.00	ORD-102362
2328	51869	16	1	656.27	0.00	ORD-102363
2329	52864	11	7	8.82	0.15	ORD-102364
2330	53171	10	2	174.83	0.05	ORD-102365
2331	54109	20	3	331.65	0.00	ORD-102366
2332	51210	9	4	12.07	0.00	ORD-102367
2333	52629	3	1	123.95	0.05	ORD-102368
2334	52204	10	1	184.59	0.00	ORD-102369
2335	53261	10	2	184.77	0.05	ORD-102370
2336	55739	11	6	9.32	0.10	ORD-102371
2337	52865	19	4	21.64	0.00	ORD-102372
2338	53732	12	2	24.98	0.10	ORD-102373
2339	55566	4	1	152.14	0.00	ORD-102374
2340	52236	12	4	25.05	0.05	ORD-102375
2341	50715	7	4	59.97	0.05	ORD-102376
2342	51016	6	1	91.33	0.00	ORD-102377
2343	53028	13	1	496.12	0.00	ORD-102378
2344	51870	5	1	91.17	0.00	ORD-102379
2345	55697	16	1	627.35	0.00	ORD-102380
2346	54300	19	1	22.33	0.15	ORD-102381
2347	50909	12	3	25.41	0.00	ORD-102382
2348	51017	17	1	419.77	0.05	ORD-102383
2349	51211	9	3	12.31	0.00	ORD-102384
2350	54701	4	1	143.50	0.00	ORD-102385
2351	50756	4	2	155.83	0.10	ORD-102386
2352	50052	12	3	25.01	0.05	ORD-102387
2353	51776	15	2	78.49	0.00	ORD-102388
2354	51675	4	3	146.71	0.00	ORD-102389
2355	50910	12	2	25.73	0.00	ORD-102390
2356	55473	15	2	76.21	0.00	ORD-102391
2357	53497	20	2	332.29	0.20	ORD-102392
2358	52169	5	3	90.12	0.00	ORD-102393
2359	51755	7	1	59.77	0.00	ORD-102394
2360	53029	5	1	86.11	0.00	ORD-102395
2361	50716	1	1	105.94	0.10	ORD-102396
2362	51718	4	3	157.37	0.05	ORD-102397
2363	55781	15	2	79.34	0.10	ORD-102398
2364	55817	12	5	23.93	0.05	ORD-102399
2365	50146	17	1	407.87	0.05	ORD-102400
2366	52262	16	1	611.91	0.00	ORD-102401
2367	51354	19	3	22.77	0.00	ORD-102402
2368	52790	3	1	128.63	0.10	ORD-102403
2369	52237	18	4	14.83	0.00	ORD-102404
2370	51581	4	2	157.45	0.15	ORD-102405
2371	52630	11	3	9.41	0.15	ORD-102406
2372	51871	20	2	324.57	0.00	ORD-102407
2373	51683	19	3	21.63	0.10	ORD-102408
2374	51018	1	2	112.67	0.10	ORD-102409
2375	52138	17	1	417.43	0.05	ORD-102410
2376	51263	4	3	152.81	0.10	ORD-102411
2377	52419	14	1	207.84	0.10	ORD-102412
2378	51872	4	2	147.89	0.15	ORD-102413
2379	51873	20	1	339.73	0.00	ORD-102414
2380	51262	7	1	61.43	0.05	ORD-102415
2381	55267	2	1	72.28	0.10	ORD-102416
2382	52866	1	1	114.00	0.10	ORD-102417
2383	54334	7	2	57.36	0.10	ORD-102418
2384	52389	6	2	92.61	0.20	ORD-102419
2385	52138	12	4	23.86	0.15	ORD-102420
2386	51756	4	1	149.80	0.05	ORD-102421
2387	50851	4	1	153.44	0.00	ORD-102422
2388	51650	13	1	540.23	0.05	ORD-102423
2389	51618	18	8	15.67	0.00	ORD-102424
2390	55268	15	1	79.37	0.00	ORD-102425
2391	50147	1	1	110.41	0.00	ORD-102426
2392	54515	5	3	88.08	0.00	ORD-102427
2393	54436	6	2	91.32	0.05	ORD-102428
2394	52420	10	1	186.50	0.20	ORD-102429
2395	53117	20	1	340.49	0.00	ORD-102430
2396	51874	10	1	175.60	0.00	ORD-102431
2397	54214	7	2	62.97	0.00	ORD-102432
2398	50802	18	5	14.85	0.00	ORD-102433
2399	51522	14	2	217.82	0.10	ORD-102434
2400	54560	1	4	113.51	0.10	ORD-102435
2401	55747	9	4	11.41	0.00	ORD-102436
2402	52702	20	1	343.15	0.00	ORD-102437
2403	54153	12	4	24.50	0.00	ORD-102438
2404	51264	6	2	98.42	0.05	ORD-102439
2405	54859	5	1	86.12	0.00	ORD-102440
2406	54322	12	7	25.75	0.15	ORD-102441
2407	54679	3	1	135.07	0.00	ORD-102442
2408	51582	8	1	777.32	0.05	ORD-102443
2409	54688	5	1	85.51	0.00	ORD-102444
2410	51137	9	3	12.04	0.00	ORD-102445
2411	50022	20	2	319.54	0.00	ORD-102446
2412	50911	11	8	8.59	0.20	ORD-102447
2413	54027	9	6	11.66	0.00	ORD-102448
2414	54466	20	1	319.75	0.05	ORD-102449
2415	52835	8	1	734.98	0.05	ORD-102450
2416	53885	12	3	24.33	0.05	ORD-102451
2417	55270	7	2	58.46	0.05	ORD-102452
2418	53669	12	3	26.17	0.00	ORD-102453
2419	54346	14	1	203.77	0.00	ORD-102454
2420	51163	8	1	762.41	0.05	ORD-102455
2421	53733	9	3	11.85	0.05	ORD-102456
2422	54784	8	3	770.49	0.10	ORD-102457
2423	51265	10	2	172.22	0.00	ORD-102458
2424	55269	3	1	132.78	0.10	ORD-102459
2425	55270	17	1	433.21	0.10	ORD-102460
2426	50327	1	2	114.26	0.00	ORD-102461
2427	54392	20	3	344.84	0.05	ORD-102462
2428	53101	20	1	331.17	0.00	ORD-102463
2429	53317	12	6	25.26	0.00	ORD-102464
2430	54861	7	2	61.58	0.05	ORD-102465
2431	50912	5	1	86.88	0.05	ORD-102466
2432	54860	15	3	78.28	0.00	ORD-102467
2433	53957	6	2	94.49	0.15	ORD-102468
2434	54028	16	1	621.73	0.10	ORD-102469
2435	54393	11	3	8.71	0.00	ORD-102470
2436	53030	10	1	182.63	0.00	ORD-102471
2437	53772	10	1	185.52	0.00	ORD-102472
2438	55271	8	1	741.22	0.00	ORD-102473
2439	53734	16	1	610.39	0.05	ORD-102474
2440	50328	15	2	77.57	0.15	ORD-102475
2441	55474	9	3	12.39	0.15	ORD-102476
2442	54347	18	2	15.21	0.10	ORD-102477
2443	50482	13	1	503.56	0.05	ORD-102478
2444	50023	20	1	338.28	0.00	ORD-102479
2445	53604	14	1	211.23	0.05	ORD-102480
2446	50483	1	1	108.90	0.00	ORD-102481
2447	51692	9	6	12.05	0.10	ORD-102482
2448	51448	15	2	76.88	0.20	ORD-102483
2449	51875	12	1	25.80	0.05	ORD-102484
2450	54437	12	1	25.13	0.00	ORD-102485
2451	51523	12	4	24.94	0.05	ORD-102486
2452	51651	20	1	331.33	0.05	ORD-102487
2453	50508	9	9	11.54	0.15	ORD-102488
2454	51523	12	3	26.25	0.00	ORD-102489
2455	52604	10	1	171.40	0.15	ORD-102490
2456	52074	6	2	94.77	0.00	ORD-102491
2457	55272	19	1	21.30	0.00	ORD-102492
2458	54916	18	3	14.31	0.00	ORD-102493
2459	53102	7	1	57.20	0.05	ORD-102494
2460	53437	7	3	60.54	0.00	ORD-102495
2461	52075	9	4	11.59	0.00	ORD-102496
2462	53605	12	5	23.77	0.10	ORD-102497
2463	51266	4	1	145.86	0.00	ORD-102498
2464	53172	13	2	544.84	0.00	ORD-102499
2465	52655	11	3	9.39	0.15	ORD-102501
2466	50395	16	1	644.95	0.00	ORD-102502
2467	50024	5	2	86.68	0.00	ORD-102503
2468	53172	8	3	748.40	0.15	ORD-102504
2469	51355	9	6	11.94	0.10	ORD-102505
2470	53670	14	2	200.07	0.00	ORD-102506
2471	53958	2	1	72.80	0.05	ORD-102507
2472	53361	10	2	182.23	0.20	ORD-102508
2473	54917	8	1	774.10	0.10	ORD-102509
2474	55273	5	1	87.16	0.00	ORD-102510
2475	50823	9	3	12.54	0.15	ORD-102511
2476	50329	13	1	512.41	0.05	ORD-102512
2477	52205	13	2	522.39	0.20	ORD-102513
2478	55818	10	1	172.88	0.00	ORD-102514
2479	51267	8	1	742.75	0.00	ORD-102515
2480	50390	5	2	90.42	0.00	ORD-102516
2481	50025	7	1	62.44	0.00	ORD-102517
2482	52725	2	2	70.88	0.00	ORD-102518
2483	53855	2	1	70.78	0.10	ORD-102519
2484	54481	18	4	15.00	0.10	ORD-102520
2485	53959	19	3	21.67	0.00	ORD-102521
2486	54029	12	3	25.42	0.15	ORD-102522
2487	51410	7	1	60.39	0.00	ORD-102523
2488	53031	14	1	204.42	0.00	ORD-102524
2489	54178	2	1	71.00	0.05	ORD-102525
2490	54394	8	1	774.67	0.10	ORD-102526
2491	52468	9	1	12.49	0.10	ORD-102527
2492	55004	12	5	25.17	0.15	ORD-102528
2493	55274	12	7	25.85	0.10	ORD-102529
2494	50244	15	3	81.32	0.05	ORD-102530
2495	51876	7	1	61.78	0.15	ORD-102531
2496	51877	13	2	541.43	0.10	ORD-102532
2497	54918	7	2	58.76	0.00	ORD-102533
2498	51524	12	1	25.04	0.00	ORD-102534
2499	53671	5	3	88.53	0.00	ORD-102535
2500	53960	13	2	538.36	0.00	ORD-102536
2501	53403	3	1	135.98	0.05	ORD-102537
2502	51109	11	4	9.31	0.05	ORD-102538
2503	51525	8	1	773.61	0.00	ORD-102539
2504	51877	1	1	110.95	0.15	ORD-102540
2505	54702	2	2	73.10	0.10	ORD-102541
2506	55621	6	3	94.11	0.05	ORD-102542
2507	52039	6	2	94.25	0.00	ORD-102543
2508	53606	1	1	113.96	0.00	ORD-102544
2509	54453	2	2	70.42	0.10	ORD-102545
2510	54068	12	10	24.23	0.20	ORD-102546
2511	50148	15	1	79.28	0.00	ORD-102547
2512	54529	17	1	429.06	0.05	ORD-102548
2513	51806	11	3	8.90	0.05	ORD-102549
2514	51019	13	2	540.46	0.00	ORD-102550
2515	53262	5	2	87.89	0.20	ORD-102551
2516	54919	9	4	12.08	0.00	ORD-102552
2517	54361	7	3	59.44	0.00	ORD-102553
2518	53962	18	6	14.85	0.00	ORD-102554
2519	51878	9	3	11.60	0.15	ORD-102555
2520	55519	14	1	204.08	0.00	ORD-102556
2521	52113	16	1	616.27	0.00	ORD-102557
2522	51020	18	6	14.64	0.05	ORD-102558
2523	52720	12	1	24.27	0.10	ORD-102559
2524	53961	11	3	8.94	0.05	ORD-102560
2525	55667	20	2	332.51	0.00	ORD-102562
2526	53032	1	2	106.54	0.15	ORD-102563
2527	53263	9	6	12.02	0.00	ORD-102564
2528	50245	8	1	743.63	0.00	ORD-102565
2529	52000	1	1	112.90	0.00	ORD-102566
2530	55457	18	3	14.64	0.15	ORD-102567
2531	54140	11	3	9.34	0.05	ORD-102568
2532	51693	1	2	109.39	0.00	ORD-102569
2533	52726	15	3	78.29	0.00	ORD-102570
2534	52040	16	1	616.58	0.05	ORD-102571
2535	53607	15	2	77.20	0.00	ORD-102572
2536	52217	7	3	57.08	0.00	ORD-102573
2537	52867	3	1	130.41	0.10	ORD-102574
2538	53381	5	1	93.38	0.05	ORD-102575
2539	51268	11	3	9.22	0.00	ORD-102576
2540	50540	20	1	326.97	0.00	ORD-102577
2541	51269	17	1	433.25	0.15	ORD-102578
2542	51879	18	4	14.45	0.05	ORD-102579
2543	54920	19	1	22.62	0.10	ORD-102580
2544	55520	7	1	61.09	0.00	ORD-102581
2545	51449	16	1	654.92	0.00	ORD-102582
2546	51356	14	1	202.04	0.00	ORD-102583
2547	51965	7	1	59.33	0.10	ORD-102584
2548	52580	13	1	516.40	0.20	ORD-102585
2549	50026	12	3	25.88	0.10	ORD-102587
2550	52335	6	2	90.83	0.10	ORD-102588
2551	53672	12	5	25.12	0.05	ORD-102589
2552	55567	8	3	718.49	0.00	ORD-102590
2553	55520	3	1	128.07	0.10	ORD-102591
2554	50523	15	2	78.16	0.05	ORD-102592
2555	50523	17	1	426.59	0.20	ORD-102593
2556	50149	18	2	15.46	0.10	ORD-102594
2557	53318	18	6	15.42	0.00	ORD-102595
2558	54964	10	1	180.07	0.00	ORD-102596
2559	55683	6	2	92.88	0.20	ORD-102597
2560	52766	17	1	419.81	0.10	ORD-102598
2561	52449	7	1	61.50	0.00	ORD-102599
2562	52791	17	1	431.04	0.10	ORD-102600
2563	51021	1	1	111.58	0.05	ORD-102601
2564	53033	1	1	107.62	0.15	ORD-102602
2565	53264	7	2	57.15	0.05	ORD-102603
2566	54726	12	5	25.75	0.05	ORD-102604
2567	52757	9	2	11.92	0.20	ORD-102605
2568	54467	9	4	11.63	0.00	ORD-102606
2569	55275	18	4	15.68	0.00	ORD-102607
2570	50555	4	2	153.44	0.00	ORD-102608
2571	53173	18	1	14.49	0.00	ORD-102609
2572	53382	12	4	24.40	0.10	ORD-102610
2573	53521	5	1	86.13	0.00	ORD-102611
2574	52017	2	1	71.81	0.00	ORD-102612
2575	51270	20	1	328.11	0.10	ORD-102613
2576	53173	2	2	68.44	0.10	ORD-102614
2577	50524	7	1	61.97	0.05	ORD-102615
2578	55005	12	5	25.04	0.10	ORD-102616
2579	52139	19	1	22.35	0.00	ORD-102617
2580	50330	11	2	9.01	0.00	ORD-102618
2581	51271	5	3	87.43	0.00	ORD-102619
2582	55276	15	3	76.34	0.05	ORD-102620
2583	54921	4	2	144.21	0.00	ORD-102621
2584	55568	8	1	736.83	0.00	ORD-102622
2585	55646	8	2	759.84	0.00	ORD-102623
2586	50852	7	2	62.76	0.00	ORD-102624
2587	50913	2	1	72.36	0.15	ORD-102625
2588	53963	11	4	9.18	0.10	ORD-102626
2589	52868	4	1	156.28	0.20	ORD-102627
2590	53886	2	2	66.79	0.05	ORD-102628
2591	52170	15	2	82.83	0.10	ORD-102629
2592	51880	17	1	414.83	0.15	ORD-102630
2593	52076	14	1	199.98	0.00	ORD-102631
2594	55276	1	2	104.88	0.05	ORD-102632
2595	55756	17	1	432.67	0.00	ORD-102633
2596	55277	1	1	110.00	0.10	ORD-102634
2597	53319	7	1	61.58	0.15	ORD-102636
2598	55278	17	1	429.45	0.00	ORD-102637
2599	53608	12	3	26.11	0.00	ORD-102638
2600	53522	6	1	92.27	0.05	ORD-102639
2601	52631	1	2	114.10	0.10	ORD-102640
2602	55089	12	4	25.78	0.15	ORD-102642
2603	55684	11	4	9.40	0.00	ORD-102643
2604	51022	13	3	544.81	0.00	ORD-102644
2605	50775	11	4	9.05	0.10	ORD-102645
2606	54215	3	1	134.01	0.10	ORD-102646
2607	51023	9	2	12.15	0.10	ORD-102647
2608	54629	9	5	11.97	0.15	ORD-102648
2609	50525	18	4	14.35	0.00	ORD-102649
2610	53523	12	6	26.21	0.15	ORD-102650
2611	51881	12	4	23.77	0.05	ORD-102651
2612	51272	5	1	90.03	0.00	ORD-102652
2613	51526	5	1	85.71	0.15	ORD-102653
2614	54561	12	2	25.95	0.05	ORD-102654
2615	55279	1	1	110.06	0.00	ORD-102655
2616	51652	9	4	12.26	0.05	ORD-102656
2617	51272	17	2	409.95	0.00	ORD-102657
2618	52421	8	1	747.77	0.05	ORD-102658
2619	50150	4	2	154.67	0.05	ORD-102659
2620	54751	6	1	91.25	0.00	ORD-102660
2621	54030	5	1	88.49	0.05	ORD-102661
2622	50053	1	2	107.89	0.00	ORD-102662
2623	50151	19	3	22.59	0.20	ORD-102663
2624	54362	3	1	127.07	0.05	ORD-102664
2625	54922	3	1	124.86	0.00	ORD-102665
2626	55436	3	2	126.99	0.00	ORD-102666
2627	53964	16	1	668.11	0.00	ORD-102667
2628	54438	4	3	145.93	0.00	ORD-102668
2629	50246	16	1	669.02	0.05	ORD-102669
2630	54862	8	1	786.56	0.00	ORD-102670
2631	52758	12	3	25.70	0.00	ORD-102671
2632	51583	8	1	730.66	0.15	ORD-102672
2633	53545	13	3	522.72	0.15	ORD-102673
2634	50556	18	3	14.43	0.00	ORD-102674
2635	51110	1	1	106.64	0.00	ORD-102675
2636	51333	9	5	11.60	0.00	ORD-102676
2637	52041	10	1	177.64	0.00	ORD-102677
2638	51395	18	5	14.39	0.00	ORD-102678
2639	55280	13	1	537.75	0.00	ORD-102679
2640	50853	10	1	178.62	0.00	ORD-102680
2641	54031	18	5	14.59	0.05	ORD-102681
2642	55280	14	1	217.40	0.10	ORD-102682
2643	50247	12	4	23.79	0.15	ORD-102683
2644	50384	12	5	24.90	0.00	ORD-102684
2645	53902	8	2	732.09	0.20	ORD-102685
2646	50681	14	2	209.57	0.00	ORD-102686
2647	52566	10	2	179.34	0.00	ORD-102687
2648	50054	7	1	57.15	0.10	ORD-102688
2649	53124	19	3	22.43	0.15	ORD-102689
2650	53673	1	1	104.69	0.10	ORD-102690
2651	54630	10	2	182.57	0.00	ORD-102691
2652	53911	19	3	21.18	0.15	ORD-102692
2653	52018	9	4	12.41	0.15	ORD-102693
2654	55281	4	2	156.61	0.10	ORD-102694
2655	55006	11	4	8.88	0.00	ORD-102695
2656	55090	10	1	185.15	0.00	ORD-102696
2657	54530	17	1	402.05	0.05	ORD-102697
2658	55623	14	2	200.92	0.05	ORD-102698
2659	53404	6	1	98.56	0.05	ORD-102699
2660	52077	1	2	107.22	0.00	ORD-102700
2661	50070	5	1	91.37	0.00	ORD-102701
2662	52656	13	1	518.85	0.10	ORD-102702
2663	51882	1	2	114.41	0.10	ORD-102703
2664	55622	17	1	428.84	0.00	ORD-102704
2665	53813	12	2	26.16	0.15	ORD-102705
2666	53609	18	2	15.46	0.00	ORD-102706
2667	51757	18	6	15.12	0.00	ORD-102707
2668	52836	20	2	340.44	0.00	ORD-102708
2669	51450	10	1	175.20	0.00	ORD-102709
2670	50090	1	1	107.40	0.05	ORD-102710
2671	54054	8	1	762.48	0.00	ORD-102711
2672	54631	5	1	86.88	0.00	ORD-102712
2673	51883	4	1	154.93	0.00	ORD-102713
2674	52450	9	2	12.17	0.00	ORD-102714
2675	50099	18	5	15.37	0.10	ORD-102715
2676	52336	11	3	8.80	0.05	ORD-102716
2677	50199	5	2	91.79	0.05	ORD-102717
2678	52372	8	1	725.94	0.00	ORD-102718
2679	54703	8	1	777.92	0.00	ORD-102719
2680	53174	17	2	406.90	0.05	ORD-102720
2681	54492	3	1	125.83	0.00	ORD-102721
2682	51024	4	1	153.21	0.00	ORD-102722
2683	54363	8	1	773.71	0.00	ORD-102723
2684	53034	19	2	21.73	0.00	ORD-102724
2685	53498	12	5	24.79	0.20	ORD-102725
2686	54217	2	2	66.50	0.20	ORD-102726
2687	54216	6	1	91.37	0.00	ORD-102727
2688	54259	15	1	78.12	0.00	ORD-102728
2689	52078	17	1	412.02	0.00	ORD-102729
2690	53103	5	2	91.40	0.05	ORD-102730
2691	55282	2	1	71.17	0.00	ORD-102731
2692	52605	3	1	130.62	0.00	ORD-102732
2693	51966	17	2	408.13	0.00	ORD-102733
2694	53092	7	2	61.09	0.00	ORD-102734
2695	55283	6	1	97.90	0.00	ORD-102735
2696	53524	18	3	14.74	0.00	ORD-102736
2697	53383	5	2	92.77	0.00	ORD-102737
2698	51719	14	2	206.52	0.10	ORD-102738
2699	50541	11	3	8.77	0.00	ORD-102739
2700	53814	13	1	507.13	0.15	ORD-102740
2701	55091	6	3	96.33	0.00	ORD-102741
2702	52263	11	2	9.11	0.15	ORD-102742
2703	51025	13	1	545.99	0.00	ORD-102743
2704	51572	4	1	155.20	0.20	ORD-102744
2705	52019	14	1	209.00	0.10	ORD-102745
2706	55581	12	4	24.11	0.15	ORD-102746
2707	51807	3	1	133.46	0.15	ORD-102747
2708	52218	9	5	12.26	0.15	ORD-102748
2709	53175	5	2	87.87	0.00	ORD-102749
2710	52390	6	2	96.12	0.00	ORD-102750
2711	55284	10	1	180.06	0.00	ORD-102751
2712	50027	13	4	499.49	0.20	ORD-102752
2713	51527	9	6	12.55	0.15	ORD-102753
2714	53176	5	1	86.93	0.05	ORD-102754
2715	53035	10	1	172.76	0.00	ORD-102755
2716	51357	14	2	217.69	0.10	ORD-102756
2717	52079	20	2	322.32	0.10	ORD-102757
2718	50526	9	3	11.93	0.05	ORD-102758
2719	54785	9	3	11.95	0.10	ORD-102759
2720	52001	12	4	25.80	0.05	ORD-102760
2721	53320	12	6	26.11	0.00	ORD-102761
2722	54923	15	1	78.50	0.05	ORD-102762
2723	52777	18	5	14.80	0.20	ORD-102763
2724	55521	10	2	178.81	0.00	ORD-102764
2725	52531	14	2	220.29	0.05	ORD-102765
2726	51026	9	5	12.51	0.00	ORD-102766
2727	55007	11	4	9.25	0.05	ORD-102767
2728	55132	19	2	22.11	0.00	ORD-102768
2729	53562	19	3	20.98	0.05	ORD-102769
2730	55140	11	4	9.15	0.05	ORD-102770
2731	50509	9	6	11.73	0.15	ORD-102771
2732	51884	2	1	67.64	0.00	ORD-102772
2733	55092	5	2	94.20	0.00	ORD-102773
2734	53177	18	4	14.74	0.00	ORD-102774
2735	51758	17	1	403.58	0.10	ORD-102775
2736	54194	5	1	89.69	0.05	ORD-102776
2737	51885	18	7	15.07	0.10	ORD-102777
2738	52020	19	3	22.32	0.00	ORD-102778
2739	51584	18	2	15.23	0.10	ORD-102779
2740	50412	14	1	205.50	0.00	ORD-102780
2741	50914	10	1	182.14	0.20	ORD-102781
2742	55285	4	2	144.48	0.00	ORD-102782
2743	54179	15	2	77.48	0.05	ORD-102783
2744	54824	15	2	81.03	0.05	ORD-102784
2745	55093	3	1	136.39	0.15	ORD-102785
2746	54260	11	5	8.95	0.00	ORD-102786
2747	54669	15	3	81.79	0.15	ORD-102787
2748	51979	14	1	213.68	0.00	ORD-102788
2749	54632	3	2	124.54	0.00	ORD-102789
2750	55094	5	1	87.75	0.00	ORD-102790
2751	52581	6	6	95.92	0.00	ORD-102791
2752	51653	4	4	151.32	0.00	ORD-102792
2753	52981	5	1	94.18	0.00	ORD-102793
2754	52080	16	2	630.43	0.00	ORD-102794
2755	55668	11	3	8.56	0.00	ORD-102795
2756	53610	1	1	109.79	0.00	ORD-102796
2757	55782	14	1	203.62	0.00	ORD-102797
2758	51027	2	1	66.53	0.00	ORD-102798
2759	51886	16	1	625.22	0.10	ORD-102799
2760	52365	13	1	519.40	0.00	ORD-102800
2761	53815	14	2	204.82	0.00	ORD-102801
2762	52514	13	1	510.76	0.05	ORD-102802
2763	51886	6	5	98.47	0.00	ORD-102803
2764	50291	20	1	316.09	0.00	ORD-102804
2765	51027	18	9	14.57	0.00	ORD-102805
2766	52955	11	4	9.07	0.10	ORD-102806
2767	51202	9	2	11.55	0.00	ORD-102807
2768	55286	15	2	76.87	0.05	ORD-102808
2769	55095	1	2	109.48	0.00	ORD-102809
2770	52206	5	2	86.91	0.00	ORD-102810
2771	51737	18	3	15.22	0.20	ORD-102811
2772	50484	20	2	321.97	0.20	ORD-102812
2773	54863	20	2	334.78	0.00	ORD-102813
2774	53321	11	3	9.09	0.00	ORD-102814
2775	50207	11	3	8.68	0.05	ORD-102815
2776	51451	12	6	24.70	0.00	ORD-102816
2777	53569	15	2	76.48	0.15	ORD-102817
2778	55685	7	2	57.49	0.20	ORD-102818
2779	55783	15	3	82.46	0.00	ORD-102819
2780	51597	10	1	188.63	0.05	ORD-102820
2781	53104	15	2	77.39	0.00	ORD-102821
2782	55008	15	2	83.32	0.20	ORD-102822
2783	51028	13	1	514.40	0.00	ORD-102823
2784	50854	1	1	109.14	0.10	ORD-102824
2785	51029	10	2	180.80	0.00	ORD-102825
2786	55096	14	2	201.73	0.05	ORD-102826
2787	52451	18	1	15.43	0.15	ORD-102827
2788	55287	15	4	77.61	0.10	ORD-102828
2789	53036	3	2	129.47	0.05	ORD-102829
2790	50757	5	1	88.03	0.00	ORD-102830
2791	54830	6	2	95.23	0.00	ORD-102831
2792	52606	6	4	94.13	0.15	ORD-102833
2793	51676	1	1	113.15	0.00	ORD-102834
2794	52140	6	1	90.56	0.00	ORD-102835
2795	52002	6	2	90.72	0.15	ORD-102836
2796	50510	2	2	72.33	0.15	ORD-102837
2797	52491	13	1	494.44	0.15	ORD-102838
2798	53499	12	5	24.25	0.00	ORD-102839
2799	54924	10	1	185.17	0.05	ORD-102840
2800	51528	19	1	22.96	0.05	ORD-102841
2801	51345	4	2	153.59	0.10	ORD-102842
2802	51452	15	1	77.40	0.10	ORD-102843
2803	50331	19	1	22.84	0.10	ORD-102844
2804	50803	14	2	209.57	0.05	ORD-102845
2805	51759	5	1	91.70	0.00	ORD-102846
2806	51030	20	2	340.63	0.00	ORD-102847
2807	51452	4	1	156.99	0.00	ORD-102848
2808	53674	20	2	330.33	0.00	ORD-102849
2809	51273	18	3	15.41	0.20	ORD-102850
2810	50221	13	2	506.41	0.05	ORD-102851
2811	54261	19	1	21.87	0.00	ORD-102852
2812	52391	20	1	342.17	0.00	ORD-102853
2813	53322	3	1	125.58	0.00	ORD-102854
2814	53438	16	1	634.60	0.00	ORD-102855
2815	54069	20	2	330.97	0.00	ORD-102856
2816	55808	11	5	9.03	0.05	ORD-102857
2817	51619	19	1	22.33	0.05	ORD-102858
2818	53735	3	1	127.74	0.05	ORD-102859
2819	50557	8	1	742.59	0.05	ORD-102860
2820	54825	15	2	81.37	0.00	ORD-102861
2821	52607	13	1	521.48	0.00	ORD-102862
2822	50641	12	3	24.52	0.00	ORD-102863
2823	54364	13	3	513.92	0.10	ORD-102864
2824	51212	12	2	25.57	0.00	ORD-102865
2825	53384	11	4	8.96	0.10	ORD-102866
2826	54786	12	4	25.85	0.05	ORD-102867
2827	55289	4	1	153.22	0.05	ORD-102868
2828	52434	8	1	713.20	0.20	ORD-102869
2829	53500	14	1	202.29	0.00	ORD-102870
2830	55647	20	1	342.80	0.15	ORD-102871
2831	53178	13	1	519.66	0.10	ORD-102873
2832	50804	15	3	77.21	0.00	ORD-102874
2833	55288	13	2	522.31	0.00	ORD-102875
2834	54154	12	3	23.83	0.20	ORD-102876
2835	54497	18	4	14.58	0.15	ORD-102877
2836	51887	12	2	25.87	0.00	ORD-102878
2837	54180	9	4	11.59	0.00	ORD-102879
2838	51760	4	2	143.14	0.00	ORD-102880
2839	50855	3	1	132.39	0.00	ORD-102881
2840	50152	14	1	218.20	0.00	ORD-102882
2841	55437	13	1	545.37	0.00	ORD-102883
2842	50152	9	3	11.79	0.00	ORD-102884
2843	54395	7	1	60.83	0.15	ORD-102885
2844	55097	6	1	91.58	0.10	ORD-102886
2845	54482	19	1	22.45	0.05	ORD-102887
2846	54562	18	3	14.48	0.15	ORD-102888
2847	55098	14	2	210.59	0.05	ORD-102889
2848	51274	12	3	25.72	0.05	ORD-102890
2849	51274	19	1	23.03	0.00	ORD-102891
2850	50485	20	1	317.11	0.00	ORD-102892
2851	53816	15	1	81.48	0.00	ORD-102893
2852	54864	20	2	335.46	0.00	ORD-102894
2853	54787	14	1	201.47	0.00	ORD-102895
2854	51598	14	1	211.41	0.10	ORD-102896
2855	51031	9	4	11.72	0.00	ORD-102897
2856	55784	8	2	768.61	0.00	ORD-102898
2857	50028	2	1	67.61	0.00	ORD-102899
2858	52264	12	3	25.88	0.05	ORD-102900
2859	51453	20	1	324.40	0.00	ORD-102901
2860	55582	14	1	204.51	0.05	ORD-102902
2861	53675	9	7	11.43	0.00	ORD-102903
2862	55290	2	1	69.56	0.00	ORD-102904
2863	55600	20	1	316.08	0.05	ORD-102905
2864	54633	12	3	24.75	0.00	ORD-102906
2865	51334	12	3	25.00	0.10	ORD-102907
2866	51777	3	1	134.51	0.05	ORD-102908
2867	50055	19	1	23.05	0.20	ORD-102909
2868	55291	19	1	21.16	0.00	ORD-102910
2869	53676	12	8	23.90	0.05	ORD-102911
2870	51967	11	2	8.71	0.10	ORD-102912
2871	52982	6	2	95.17	0.00	ORD-102913
2872	52492	13	2	517.94	0.00	ORD-102914
2873	51720	19	4	21.60	0.00	ORD-102915
2874	54670	11	3	8.87	0.05	ORD-102916
2875	51888	4	1	155.80	0.00	ORD-102917
2876	50056	6	2	98.54	0.10	ORD-102918
2877	51275	15	2	81.78	0.00	ORD-102919
2878	50153	4	2	144.22	0.00	ORD-102920
2879	50332	10	2	171.40	0.00	ORD-102921
2880	50511	11	2	8.60	0.00	ORD-102922
2881	54680	15	1	83.53	0.05	ORD-102923
2882	53677	8	2	765.25	0.00	ORD-102924
2883	51677	8	3	731.28	0.00	ORD-102925
2884	51368	1	1	113.45	0.00	ORD-102926
2885	51889	11	2	8.59	0.05	ORD-102927
2886	55293	3	2	123.86	0.00	ORD-102928
2887	52778	1	2	111.79	0.00	ORD-102929
2888	52171	8	1	725.05	0.20	ORD-102930
2889	54070	1	2	108.22	0.00	ORD-102931
2890	54788	12	5	24.99	0.00	ORD-102932
2891	55292	2	1	67.57	0.00	ORD-102933
2892	50856	16	2	652.24	0.00	ORD-102934
2893	55686	13	2	538.10	0.20	ORD-102935
2894	55009	17	1	420.85	0.00	ORD-102936
2895	53678	18	4	14.64	0.00	ORD-102937
2896	55010	4	2	152.77	0.10	ORD-102939
2897	53501	8	1	742.11	0.00	ORD-102940
2898	54531	5	1	91.81	0.10	ORD-102941
2899	55141	18	3	15.62	0.00	ORD-102942
2900	52922	20	1	328.47	0.10	ORD-102943
2901	55522	16	1	655.44	0.05	ORD-102944
2902	53817	13	1	508.66	0.15	ORD-102945
2903	52657	11	6	8.99	0.00	ORD-102946
2904	51778	18	4	14.70	0.00	ORD-102947
2905	53405	14	1	201.04	0.00	ORD-102948
2906	55601	6	1	99.53	0.00	ORD-102949
2907	53736	3	1	124.82	0.00	ORD-102950
2908	51032	1	1	115.48	0.00	ORD-102951
2909	51890	7	2	57.71	0.05	ORD-102952
2910	53927	18	2	14.93	0.05	ORD-102953
2911	50542	7	4	57.94	0.00	ORD-102954
2912	50857	11	5	9.35	0.05	ORD-102955
2913	55602	18	3	15.00	0.00	ORD-102956
2914	55060	9	4	11.55	0.10	ORD-102957
2915	54218	4	2	156.91	0.05	ORD-102958
2916	53265	7	1	61.07	0.00	ORD-102959
2917	55133	5	1	86.86	0.05	ORD-102960
2918	54789	12	4	23.92	0.00	ORD-102961
2919	51145	15	1	77.41	0.00	ORD-102962
2920	51808	3	2	126.72	0.05	ORD-102963
2921	53525	17	1	440.83	0.00	ORD-102964
2922	51033	6	2	99.15	0.00	ORD-102965
2923	50248	17	1	425.49	0.00	ORD-102966
2924	51809	15	1	76.02	0.00	ORD-102967
2925	52265	15	3	77.06	0.00	ORD-102968
2926	53887	4	1	152.25	0.00	ORD-102969
2927	55011	13	2	543.28	0.00	ORD-102970
2928	53037	17	1	421.68	0.15	ORD-102971
2929	55294	3	1	130.83	0.00	ORD-102972
2930	51529	10	1	186.44	0.10	ORD-102973
2931	50249	14	1	212.43	0.15	ORD-102974
2932	52219	10	1	186.11	0.05	ORD-102975
2933	53928	12	4	25.24	0.00	ORD-102976
2934	50084	8	2	776.09	0.00	ORD-102977
2935	50250	2	1	66.79	0.00	ORD-102978
2936	52658	10	1	174.29	0.10	ORD-102979
2937	55624	17	1	409.88	0.05	ORD-102980
2938	52337	9	4	11.65	0.00	ORD-102981
2939	50486	20	1	342.73	0.15	ORD-102982
2940	51034	5	1	93.91	0.00	ORD-102983
2941	51684	15	1	82.15	0.00	ORD-102984
2942	52469	15	2	82.17	0.05	ORD-102985
2943	50915	1	1	110.46	0.00	ORD-102986
2944	50487	20	2	331.84	0.05	ORD-102987
2945	53179	1	1	113.09	0.15	ORD-102988
2946	52703	10	2	185.99	0.05	ORD-102989
2947	51530	11	4	9.34	0.05	ORD-102990
2948	53929	14	2	210.47	0.10	ORD-102991
2949	54581	13	2	519.45	0.20	ORD-102992
2950	50488	5	1	91.13	0.00	ORD-102993
2951	50582	11	4	9.04	0.10	ORD-102994
2952	55785	7	2	61.83	0.00	ORD-102995
2953	50333	6	1	97.70	0.15	ORD-102996
2954	55295	17	2	412.01	0.15	ORD-102997
2955	50629	9	3	11.97	0.00	ORD-102998
2956	50607	6	1	92.62	0.05	ORD-103000
2957	55438	11	4	8.59	0.00	ORD-103001
2958	51035	19	2	22.94	0.00	ORD-103002
2959	54032	18	4	15.18	0.15	ORD-103003
2960	54301	11	2	8.82	0.05	ORD-103004
2961	53611	14	1	217.42	0.00	ORD-103005
2962	53323	1	1	110.44	0.05	ORD-103006
2963	52338	19	2	22.10	0.00	ORD-103007
2964	50489	12	6	25.18	0.00	ORD-103008
2965	50432	5	1	91.26	0.05	ORD-103009
2966	51654	6	1	96.53	0.10	ORD-103010
2967	53737	17	2	435.09	0.05	ORD-103011
2968	52003	4	1	155.94	0.00	ORD-103012
2969	54532	1	2	114.43	0.10	ORD-103013
2970	50566	8	1	744.90	0.10	ORD-103014
2971	51276	8	1	752.31	0.15	ORD-103015
2972	51827	17	1	415.86	0.05	ORD-103016
2973	54865	11	4	8.97	0.10	ORD-103017
2974	55698	1	1	105.32	0.15	ORD-103018
2975	52081	15	3	83.96	0.20	ORD-103019
2976	52172	1	2	107.45	0.00	ORD-103020
2977	53679	14	2	204.60	0.00	ORD-103021
2978	50583	5	1	93.33	0.00	ORD-103022
2979	53773	15	3	81.34	0.15	ORD-103023
2980	54071	6	3	97.34	0.15	ORD-103024
2981	51036	13	1	497.59	0.00	ORD-103025
2982	53965	8	2	779.67	0.05	ORD-103026
2983	55296	2	1	72.10	0.00	ORD-103027
2984	53038	10	2	171.20	0.00	ORD-103028
2985	54925	2	1	68.13	0.05	ORD-103029
2986	55297	20	1	325.74	0.00	ORD-103030
2987	52299	7	1	58.57	0.00	ORD-103031
2988	52314	18	1	15.48	0.05	ORD-103032
2989	51779	12	2	24.29	0.00	ORD-103033
2990	50251	5	2	93.88	0.00	ORD-103034
2991	55012	6	2	91.81	0.15	ORD-103035
2992	53266	1	1	106.61	0.00	ORD-103036
2993	52983	14	1	212.93	0.00	ORD-103037
2994	54752	6	2	92.15	0.10	ORD-103038
2995	54439	3	1	123.99	0.00	ORD-103039
2996	55439	8	5	760.03	0.05	ORD-103040
2997	55298	12	2	26.13	0.00	ORD-103041
2998	55134	17	1	412.40	0.05	ORD-103042
2999	54582	1	1	112.84	0.05	ORD-103043
3000	52727	14	1	212.90	0.00	ORD-103044
3001	52173	12	2	25.71	0.15	ORD-103045
3002	51891	2	4	68.78	0.00	ORD-103046
3003	54498	7	3	59.72	0.00	ORD-103047
3004	52105	1	1	109.56	0.00	ORD-103048
3005	55299	2	1	67.11	0.10	ORD-103049
3006	52659	8	1	776.34	0.10	ORD-103050
3007	55299	18	5	14.42	0.00	ORD-103051
3008	54440	10	3	188.97	0.15	ORD-103052
3009	50029	2	1	72.85	0.05	ORD-103053
3010	51500	7	3	60.22	0.00	ORD-103054
3011	50916	8	1	719.16	0.10	ORD-103055
3012	55669	16	2	647.89	0.20	ORD-103056
3013	53774	14	2	217.44	0.05	ORD-103057
3014	52626	14	1	219.35	0.00	ORD-103058
3015	55013	2	2	69.56	0.05	ORD-103059
3016	50642	4	2	143.47	0.15	ORD-103061
3017	52303	9	4	12.37	0.00	ORD-103062
3018	52493	13	1	519.10	0.10	ORD-103063
3019	53362	17	2	399.62	0.05	ORD-103064
3020	54302	5	1	88.40	0.10	ORD-103065
3021	51893	12	3	25.60	0.15	ORD-103066
3022	51037	1	1	113.71	0.00	ORD-103068
3023	52042	16	1	655.71	0.15	ORD-103069
3024	51892	11	1	9.15	0.00	ORD-103070
3025	52984	4	2	149.25	0.00	ORD-103071
3026	54033	6	1	90.52	0.15	ORD-103072
3027	51193	9	5	11.83	0.05	ORD-103073
3028	50717	2	1	72.27	0.15	ORD-103074
3029	52266	15	1	78.60	0.00	ORD-103075
3030	53439	12	3	25.51	0.05	ORD-103076
3031	54119	18	4	14.79	0.05	ORD-103077
3032	54335	4	2	145.02	0.00	ORD-103078
3033	52837	11	2	8.68	0.10	ORD-103079
3034	51124	11	1	9.31	0.10	ORD-103080
3035	53680	18	3	14.35	0.00	ORD-103081
3036	50917	10	1	178.37	0.10	ORD-103082
3037	53966	6	2	97.65	0.05	ORD-103083
3038	52238	14	1	205.18	0.00	ORD-103084
3039	55300	2	2	71.49	0.00	ORD-103085
3040	50805	2	2	72.19	0.05	ORD-103086
3041	52082	8	1	735.26	0.10	ORD-103087
3042	51531	19	2	21.24	0.00	ORD-103088
3043	55712	15	2	76.90	0.00	ORD-103089
3044	53180	11	3	9.16	0.00	ORD-103090
3045	53181	15	2	76.98	0.10	ORD-103091
3046	54336	19	1	22.93	0.05	ORD-103092
3047	51894	17	3	434.10	0.15	ORD-103093
3048	51599	15	1	79.00	0.00	ORD-103094
3049	53526	15	3	81.79	0.05	ORD-103095
3050	52267	19	1	22.27	0.05	ORD-103096
3051	51721	14	2	199.98	0.05	ORD-103097
3052	52141	15	2	81.80	0.10	ORD-103098
3053	50100	19	1	21.45	0.05	ORD-103099
3054	53918	10	1	183.95	0.05	ORD-103100
3055	51895	14	1	216.43	0.05	ORD-103101
3056	55014	6	1	98.96	0.00	ORD-103102
3057	50543	14	1	215.34	0.00	ORD-103103
3058	53903	7	3	58.92	0.00	ORD-103104
3059	55015	19	3	22.71	0.00	ORD-103105
3060	50490	12	4	24.81	0.00	ORD-103106
3061	54099	16	3	657.45	0.05	ORD-103107
3062	50101	11	4	8.68	0.00	ORD-103108
3063	54468	1	1	109.87	0.05	ORD-103109
3064	50292	9	3	11.60	0.10	ORD-103110
3065	52985	7	2	57.09	0.05	ORD-103111
3066	52985	2	1	66.90	0.00	ORD-103112
3067	55301	5	1	86.75	0.05	ORD-103113
3068	50208	20	1	346.30	0.00	ORD-103114
3069	51125	7	1	62.17	0.00	ORD-103115
3070	54840	14	2	205.85	0.00	ORD-103116
3071	51761	6	1	91.06	0.05	ORD-103117
3072	51038	19	2	22.88	0.00	ORD-103118
3073	53324	7	1	61.29	0.10	ORD-103119
3074	51213	13	2	538.12	0.10	ORD-103120
3075	51896	8	2	766.93	0.00	ORD-103121
3076	53039	9	6	12.30	0.00	ORD-103122
3077	53182	3	1	124.54	0.00	ORD-103123
3078	53930	5	1	86.99	0.15	ORD-103124
3079	50806	17	1	402.41	0.05	ORD-103125
3080	50252	7	1	57.83	0.10	ORD-103126
3081	51532	15	3	80.08	0.00	ORD-103127
3082	52494	11	4	8.56	0.00	ORD-103128
3083	53183	11	5	9.25	0.15	ORD-103129
3084	50386	11	5	8.93	0.10	ORD-103130
3085	51369	14	1	201.51	0.00	ORD-103131
3086	54034	16	1	670.77	0.00	ORD-103132
3087	50718	12	3	25.12	0.00	ORD-103133
3088	52869	13	1	532.25	0.00	ORD-103134
3089	54262	13	2	510.72	0.10	ORD-103135
3090	54689	7	1	62.84	0.10	ORD-103136
3091	54926	8	2	733.92	0.05	ORD-103137
3092	53325	2	2	69.70	0.00	ORD-103138
3093	53738	9	5	11.53	0.00	ORD-103139
3094	50630	4	2	145.21	0.00	ORD-103140
3095	51810	18	4	15.68	0.15	ORD-103141
3096	52470	10	2	179.19	0.00	ORD-103142
3097	54866	4	1	157.35	0.00	ORD-103143
3098	50608	4	1	142.54	0.15	ORD-103144
3099	55302	19	1	22.84	0.15	ORD-103145
3100	51454	19	1	22.89	0.05	ORD-103146
3101	54727	4	2	156.55	0.00	ORD-103147
3102	55303	12	7	25.40	0.05	ORD-103149
3103	51455	20	3	344.71	0.05	ORD-103150
3104	54583	7	4	62.41	0.00	ORD-103151
3105	51980	17	1	429.13	0.00	ORD-103152
3106	51277	16	1	612.43	0.00	ORD-103153
3107	53184	11	4	9.14	0.00	ORD-103154
3108	54522	5	2	86.55	0.00	ORD-103155
3109	54704	20	1	342.65	0.00	ORD-103156
3110	55625	4	3	147.31	0.10	ORD-103157
3111	52114	6	1	93.38	0.00	ORD-103158
3112	53931	4	1	145.96	0.00	ORD-103159
3113	55757	20	4	344.31	0.05	ORD-103160
3114	50030	15	2	78.91	0.20	ORD-103161
3115	54634	20	2	319.54	0.00	ORD-103162
3116	54635	16	1	617.71	0.00	ORD-103163
3117	52083	17	1	419.82	0.10	ORD-103164
3118	50071	16	2	648.58	0.00	ORD-103165
3119	52816	14	1	205.29	0.10	ORD-103166
3120	52704	9	3	11.65	0.00	ORD-103167
3121	53873	19	2	21.60	0.05	ORD-103168
3122	51456	7	1	60.01	0.00	ORD-103169
3123	53440	16	2	636.28	0.05	ORD-103170
3124	53185	12	5	24.35	0.00	ORD-103171
3125	51533	5	1	89.37	0.05	ORD-103172
3126	53185	18	2	15.52	0.10	ORD-103173
3127	53473	1	3	113.36	0.00	ORD-103174
3128	52268	4	1	144.96	0.15	ORD-103175
3129	52728	19	1	22.19	0.05	ORD-103176
3130	52084	2	1	68.36	0.10	ORD-103177
3131	53267	7	4	62.70	0.10	ORD-103178
3132	50072	4	1	154.78	0.00	ORD-103179
3133	54365	9	2	12.60	0.15	ORD-103180
3134	54790	6	2	95.56	0.00	ORD-103181
3135	53326	11	3	8.99	0.00	ORD-103182
3136	55799	6	2	95.05	0.00	ORD-103183
3137	51722	1	2	108.34	0.05	ORD-103184
3138	50334	13	1	538.00	0.05	ORD-103185
3139	52817	2	1	73.00	0.00	ORD-103186
3140	55304	9	2	11.87	0.00	ORD-103187
3141	50567	11	6	9.09	0.00	ORD-103188
3142	52085	2	1	68.09	0.00	ORD-103190
3143	51039	5	2	93.84	0.20	ORD-103191
3144	52239	12	5	24.48	0.05	ORD-103192
3145	50154	14	1	203.53	0.05	ORD-103193
3146	55523	11	4	9.31	0.10	ORD-103194
3147	55305	20	1	334.45	0.00	ORD-103195
3148	54155	14	3	211.70	0.15	ORD-103196
3149	50657	4	2	144.27	0.05	ORD-103197
3150	51534	1	1	109.51	0.00	ORD-103198
3151	50609	8	1	736.45	0.10	ORD-103199
3152	51811	11	1	9.40	0.10	ORD-103200
3153	55142	14	1	203.61	0.00	ORD-103201
3154	55740	15	2	77.36	0.00	ORD-103202
3155	50396	14	2	210.07	0.15	ORD-103203
3156	54035	10	1	186.99	0.00	ORD-103204
3157	51164	2	1	71.22	0.00	ORD-103205
3158	51411	11	6	9.27	0.10	ORD-103206
3159	52495	16	1	615.58	0.15	ORD-103207
3160	53040	12	2	25.27	0.05	ORD-103208
3161	53967	1	1	106.34	0.00	ORD-103209
3162	50514	5	1	93.77	0.15	ORD-103210
3163	55306	19	2	22.96	0.10	ORD-103212
3164	55786	7	2	57.41	0.05	ORD-103213
3165	53385	3	3	126.66	0.00	ORD-103214
3166	50858	8	2	746.51	0.00	ORD-103215
3167	52779	6	1	93.30	0.00	ORD-103216
3168	52240	15	2	81.70	0.15	ORD-103217
3169	51457	11	3	8.56	0.00	ORD-103218
3170	52304	13	1	527.99	0.00	ORD-103219
3171	52435	9	2	11.83	0.15	ORD-103220
3172	52986	18	6	15.64	0.00	ORD-103221
3173	53874	8	2	714.85	0.00	ORD-103222
3174	51111	12	4	25.29	0.00	ORD-103223
3175	55143	7	1	60.37	0.00	ORD-103224
3176	51458	18	3	14.55	0.00	ORD-103225
3177	53041	11	5	9.44	0.10	ORD-103226
3178	55307	15	3	82.42	0.00	ORD-103227
3179	51981	3	1	131.84	0.00	ORD-103228
3180	54181	14	1	209.67	0.00	ORD-103229
3181	52315	2	1	70.29	0.00	ORD-103230
3182	55016	6	2	94.44	0.10	ORD-103231
3183	51968	5	1	91.14	0.20	ORD-103232
3184	55670	20	1	338.06	0.00	ORD-103233
3185	54263	14	2	219.92	0.00	ORD-103234
3186	53186	17	1	438.40	0.00	ORD-103235
3187	52870	12	7	25.58	0.05	ORD-103236
3188	53739	5	3	91.20	0.00	ORD-103237
3189	54791	17	1	420.10	0.00	ORD-103238
3190	51897	3	1	128.86	0.00	ORD-103239
3191	53474	14	1	211.58	0.00	ORD-103240
3192	51762	8	1	752.50	0.00	ORD-103241
3193	52174	8	2	735.89	0.05	ORD-103242
3194	53406	8	1	769.84	0.10	ORD-103243
3195	54600	16	1	612.48	0.00	ORD-103244
3196	51723	14	1	202.55	0.00	ORD-103245
3197	53546	15	2	82.12	0.00	ORD-103246
3198	50682	2	2	69.13	0.00	ORD-103247
3199	55308	6	2	94.70	0.10	ORD-103248
3200	52021	7	2	62.12	0.15	ORD-103249
3201	51040	20	1	328.11	0.00	ORD-103250
3202	54867	16	1	639.98	0.15	ORD-103251
3203	55308	14	1	212.44	0.10	ORD-103252
3204	52220	19	1	21.46	0.10	ORD-103253
3205	51535	18	5	15.06	0.00	ORD-103254
3206	51898	11	4	9.41	0.15	ORD-103255
3207	52871	1	1	110.22	0.00	ORD-103257
3208	52872	1	1	111.43	0.15	ORD-103258
3209	50155	2	2	69.02	0.00	ORD-103259
3210	55603	19	1	22.03	0.00	ORD-103260
3211	52792	10	1	175.24	0.10	ORD-103261
3212	51828	13	2	525.10	0.05	ORD-103262
3213	52767	13	2	545.81	0.10	ORD-103264
3214	55440	1	2	109.04	0.10	ORD-103265
3215	54927	20	1	316.31	0.05	ORD-103266
3216	50527	2	3	70.82	0.00	ORD-103267
3217	52436	9	4	11.69	0.00	ORD-103268
3218	53740	12	2	25.87	0.00	ORD-103269
3219	50918	8	1	744.83	0.00	ORD-103270
3220	55017	9	2	11.93	0.00	ORD-103271
3221	55018	8	1	727.88	0.00	ORD-103272
3222	54636	20	1	336.54	0.00	ORD-103273
3223	55492	9	4	12.40	0.20	ORD-103274
3224	53187	9	2	12.13	0.00	ORD-103275
3225	55309	11	5	8.65	0.00	ORD-103276
3226	53681	16	1	669.24	0.05	ORD-103277
3227	52295	15	1	83.94	0.00	ORD-103278
3228	53363	14	1	217.56	0.05	ORD-103279
3229	53612	9	3	11.76	0.00	ORD-103280
3230	50253	19	2	21.21	0.20	ORD-103281
3231	54753	4	1	151.50	0.15	ORD-103282
3232	52496	15	1	77.07	0.05	ORD-103283
3233	51536	11	6	8.87	0.00	ORD-103284
3234	52269	5	3	89.17	0.00	ORD-103285
3235	53682	8	1	759.15	0.00	ORD-103286
3236	50491	1	3	108.88	0.00	ORD-103287
3237	52714	18	3	14.44	0.15	ORD-103288
3238	51165	1	2	105.42	0.05	ORD-103290
3239	55475	13	2	498.92	0.00	ORD-103291
3240	50658	7	3	62.90	0.00	ORD-103292
3241	52780	19	2	22.53	0.00	ORD-103293
3242	55476	3	1	130.88	0.15	ORD-103294
3243	55310	13	3	518.68	0.15	ORD-103295
3244	52175	20	1	332.77	0.00	ORD-103296
3245	52087	9	8	12.56	0.20	ORD-103297
3246	51710	19	2	21.45	0.05	ORD-103298
3247	52086	14	2	200.55	0.05	ORD-103299
3248	55806	14	1	206.98	0.00	ORD-103300
3249	52088	20	1	322.49	0.05	ORD-103301
3250	52142	20	2	340.00	0.05	ORD-103302
3251	54036	11	4	8.63	0.00	ORD-103304
3252	50455	14	1	209.21	0.15	ORD-103305
3253	53093	9	6	11.97	0.10	ORD-103306
3254	51763	8	2	728.93	0.00	ORD-103307
3255	50659	11	2	8.84	0.05	ORD-103308
3256	55311	5	2	92.27	0.00	ORD-103309
3257	52392	20	2	321.22	0.05	ORD-103311
3258	54072	10	1	181.48	0.10	ORD-103312
3259	51358	12	3	26.02	0.20	ORD-103313
3260	51138	3	1	125.88	0.00	ORD-103314
3261	53818	6	2	98.99	0.05	ORD-103315
3262	51537	2	1	69.63	0.00	ORD-103316
3263	53327	9	4	12.14	0.10	ORD-103317
3264	53386	12	4	25.57	0.00	ORD-103318
3265	53125	17	2	432.11	0.10	ORD-103319
3266	53527	3	1	130.62	0.15	ORD-103321
3267	50335	7	3	58.73	0.00	ORD-103322
3268	50545	4	1	149.60	0.15	ORD-103323
3269	51041	7	1	57.21	0.05	ORD-103324
3270	51780	8	1	743.37	0.00	ORD-103325
3271	50544	20	1	330.31	0.20	ORD-103326
3272	51655	11	5	9.02	0.10	ORD-103327
3273	52923	20	2	318.68	0.00	ORD-103328
3274	55135	3	1	125.60	0.00	ORD-103329
3275	55549	12	5	24.12	0.05	ORD-103330
3276	51278	12	4	26.20	0.00	ORD-103331
3277	50807	3	1	133.02	0.00	ORD-103332
3278	51166	13	2	494.51	0.15	ORD-103333
3279	52393	13	1	525.44	0.20	ORD-103334
3280	51194	4	1	143.71	0.05	ORD-103335
3281	50254	9	4	12.17	0.00	ORD-103336
3282	52690	18	2	15.00	0.10	ORD-103337
3283	55524	11	4	8.69	0.00	ORD-103338
3284	54454	19	2	22.52	0.00	ORD-103339
3285	53042	13	1	513.36	0.00	ORD-103340
3286	50619	10	2	186.76	0.05	ORD-103341
3287	51459	17	2	413.35	0.00	ORD-103342
3288	51899	1	2	109.78	0.00	ORD-103343
3289	50102	17	3	421.78	0.10	ORD-103344
3290	51042	14	1	218.93	0.05	ORD-103345
3291	51900	3	2	125.87	0.00	ORD-103346
3292	55648	7	2	57.31	0.00	ORD-103347
3293	55713	4	1	153.92	0.00	ORD-103348
3294	54037	1	2	104.93	0.00	ORD-103349
3295	55312	20	2	327.19	0.00	ORD-103350
3296	51167	5	1	85.75	0.00	ORD-103351
3297	53188	14	1	204.26	0.00	ORD-103352
3298	52115	16	2	616.46	0.05	ORD-103353
3299	51279	19	2	21.92	0.00	ORD-103354
3300	55699	3	2	125.89	0.00	ORD-103355
3301	52004	3	2	135.59	0.05	ORD-103356
3302	52873	19	4	21.95	0.05	ORD-103357
3303	50568	14	2	202.69	0.05	ORD-103358
3304	54563	16	1	647.54	0.10	ORD-103359
3305	52270	14	1	210.28	0.00	ORD-103360
3306	53683	8	1	743.15	0.15	ORD-103361
3307	52089	20	1	326.20	0.00	ORD-103362
3308	50281	8	1	779.75	0.00	ORD-103363
3309	51538	18	10	15.64	0.15	ORD-103364
3310	55099	8	2	765.60	0.05	ORD-103365
3311	53968	1	1	114.55	0.00	ORD-103366
3312	51501	4	2	156.79	0.00	ORD-103367
3313	50336	12	4	24.39	0.05	ORD-103368
3314	53043	9	5	11.81	0.00	ORD-103369
3315	52106	11	3	9.03	0.15	ORD-103370
3316	50031	12	1	23.89	0.00	ORD-103371
3317	51982	8	3	775.39	0.00	ORD-103373
3318	55550	10	1	188.32	0.05	ORD-103374
3319	50919	2	1	68.61	0.00	ORD-103375
3320	51781	1	1	105.56	0.10	ORD-103376
3321	53741	12	5	24.22	0.10	ORD-103377
3322	52043	6	2	95.66	0.10	ORD-103378
3323	53563	16	2	664.46	0.15	ORD-103379
3324	55809	8	2	750.18	0.00	ORD-103380
3325	52116	18	4	14.67	0.10	ORD-103381
3326	50156	18	3	15.19	0.05	ORD-103382
3327	50433	1	1	108.04	0.15	ORD-103383
3328	50569	2	3	69.54	0.00	ORD-103384
3329	50643	10	2	178.70	0.10	ORD-103385
3330	53441	9	6	12.39	0.10	ORD-103386
3331	53044	3	1	130.38	0.10	ORD-103387
3332	52874	10	1	187.67	0.00	ORD-103388
3333	51901	2	3	71.29	0.10	ORD-103389
3334	53131	5	1	91.37	0.05	ORD-103391
3335	51983	14	3	219.67	0.15	ORD-103392
3336	52924	9	4	12.08	0.20	ORD-103393
3337	54868	12	6	24.43	0.10	ORD-103394
3338	53570	5	1	89.68	0.05	ORD-103395
3339	50456	2	1	68.07	0.00	ORD-103396
3340	50255	20	2	318.27	0.05	ORD-103397
3341	52177	13	1	516.23	0.00	ORD-103398
3342	55313	7	2	60.84	0.10	ORD-103399
3343	53442	14	1	217.06	0.00	ORD-103400
3344	53269	2	1	69.44	0.10	ORD-103401
3345	53268	20	1	331.79	0.00	ORD-103402
3346	52176	14	2	206.07	0.00	ORD-103403
3347	51043	17	1	409.00	0.00	ORD-103404
3348	53189	1	2	109.71	0.10	ORD-103405
3349	52452	15	1	78.06	0.00	ORD-103406
3350	54928	15	3	80.46	0.05	ORD-103407
3351	53969	19	3	21.63	0.10	ORD-103408
3352	53684	4	1	143.83	0.00	ORD-103409
3353	53443	1	2	113.44	0.05	ORD-103410
3354	54690	19	2	22.33	0.10	ORD-103411
3355	54792	15	2	79.42	0.10	ORD-103412
3356	50337	5	1	86.30	0.10	ORD-103413
3357	55810	19	2	22.74	0.10	ORD-103414
3358	53118	9	6	12.06	0.00	ORD-103415
3359	50256	16	2	637.83	0.00	ORD-103416
3360	55314	15	2	82.10	0.15	ORD-103417
3361	50558	18	7	14.83	0.15	ORD-103418
3362	52366	5	2	92.38	0.15	ORD-103419
3363	50528	1	1	106.89	0.05	ORD-103420
3364	55477	3	1	134.84	0.00	ORD-103421
3365	54929	9	1	11.42	0.00	ORD-103422
3366	52532	11	2	8.96	0.00	ORD-103424
3367	51195	7	1	61.06	0.10	ORD-103425
3368	55100	19	1	21.74	0.00	ORD-103426
3369	50824	11	5	8.99	0.00	ORD-103427
3370	51460	6	1	95.80	0.00	ORD-103428
3371	55441	3	3	134.72	0.00	ORD-103429
3372	53613	10	1	176.81	0.15	ORD-103430
3373	51168	7	4	59.70	0.10	ORD-103431
3374	54100	9	3	11.93	0.15	ORD-103432
3375	51169	18	3	15.46	0.00	ORD-103433
3376	55525	16	1	631.25	0.05	ORD-103434
3377	53742	16	1	650.97	0.05	ORD-103435
3378	51764	15	5	81.91	0.00	ORD-103436
3379	55661	4	2	146.89	0.00	ORD-103437
3380	55731	14	2	207.38	0.05	ORD-103438
3381	51902	9	6	11.52	0.10	ORD-103439
3382	50032	8	1	787.20	0.15	ORD-103440
3383	53819	9	5	12.26	0.00	ORD-103441
3384	51044	4	3	153.14	0.10	ORD-103442
3385	53888	19	1	22.30	0.10	ORD-103443
3386	53614	15	2	83.28	0.05	ORD-103444
3387	53190	3	1	132.64	0.20	ORD-103445
3388	55659	4	1	152.24	0.10	ORD-103446
3389	50808	6	1	93.71	0.10	ORD-103447
3390	51046	17	1	400.34	0.00	ORD-103448
3391	53820	1	2	107.60	0.00	ORD-103449
3392	51045	13	1	525.73	0.00	ORD-103450
3393	55101	16	1	651.26	0.15	ORD-103451
3394	52839	19	2	22.10	0.00	ORD-103452
3395	52121	10	1	176.11	0.00	ORD-103453
3396	52497	7	2	62.00	0.05	ORD-103454
3397	52838	7	3	59.22	0.00	ORD-103456
3398	53685	20	1	321.45	0.05	ORD-103457
3399	55019	17	1	416.94	0.00	ORD-103458
3400	52316	6	2	95.44	0.20	ORD-103459
3401	53686	16	2	662.54	0.00	ORD-103460
3402	50033	9	2	11.85	0.10	ORD-103461
3403	54219	12	2	24.65	0.00	ORD-103462
3404	50338	14	1	209.17	0.00	ORD-103463
3405	54220	3	1	130.14	0.00	ORD-103464
3406	55020	15	3	82.79	0.00	ORD-103465
3407	54366	6	4	92.33	0.00	ORD-103466
3408	52271	5	1	93.61	0.15	ORD-103467
3409	55315	12	2	26.19	0.15	ORD-103468
3410	50776	5	1	86.81	0.05	ORD-103469
3411	52498	8	2	739.69	0.05	ORD-103470
3412	55442	9	8	12.05	0.00	ORD-103471
3413	54156	13	1	540.63	0.00	ORD-103472
3414	52818	16	1	635.72	0.00	ORD-103473
3415	54493	14	1	217.32	0.05	ORD-103474
3416	52178	19	1	22.42	0.00	ORD-103475
3417	53564	13	1	533.22	0.10	ORD-103476
3418	51370	12	6	25.01	0.00	ORD-103477
3419	53094	9	2	11.87	0.05	ORD-103478
3420	55800	6	2	91.65	0.00	ORD-103480
3421	55526	13	2	527.32	0.00	ORD-103481
3422	53615	15	3	79.85	0.00	ORD-103482
3423	50660	14	1	213.79	0.00	ORD-103483
3424	55819	12	6	23.82	0.00	ORD-103484
3425	51047	4	1	156.17	0.00	ORD-103485
3426	52339	10	1	185.60	0.00	ORD-103486
3427	54120	15	1	79.80	0.00	ORD-103487
3428	54564	19	2	22.02	0.00	ORD-103488
3429	51461	13	2	542.06	0.00	ORD-103489
3430	50103	17	1	402.28	0.05	ORD-103490
3431	50157	12	6	24.35	0.05	ORD-103491
3432	50434	2	1	67.46	0.00	ORD-103492
3433	53821	17	1	421.40	0.00	ORD-103493
3434	52515	15	4	76.85	0.00	ORD-103494
3435	51585	18	2	15.56	0.10	ORD-103495
3436	54221	15	1	77.77	0.00	ORD-103496
3437	53270	6	2	96.61	0.05	ORD-103497
3438	53687	2	2	72.78	0.05	ORD-103498
3439	55316	11	5	8.88	0.20	ORD-103499
3440	52413	1	1	108.63	0.00	ORD-103500
3441	54038	4	1	154.71	0.00	ORD-103501
3442	53970	4	2	152.20	0.15	ORD-103502
3443	51984	4	1	157.17	0.10	ORD-103503
3444	50158	10	1	186.30	0.10	ORD-103504
3445	52781	19	2	21.79	0.00	ORD-103505
3446	54101	14	1	217.78	0.10	ORD-103506
3447	50816	20	1	343.93	0.00	ORD-103507
3448	51539	4	1	154.89	0.00	ORD-103508
3449	50387	8	1	737.67	0.20	ORD-103509
3450	52044	13	1	531.68	0.05	ORD-103510
3451	51903	1	1	113.20	0.10	ORD-103511
3452	54705	9	5	11.89	0.00	ORD-103512
3453	55787	13	1	507.53	0.10	ORD-103513
3454	55714	16	1	619.44	0.10	ORD-103514
3455	55317	19	1	22.00	0.00	ORD-103515
3456	54728	2	1	69.15	0.00	ORD-103516
3457	53822	8	3	774.95	0.00	ORD-103517
3458	51048	10	2	187.56	0.00	ORD-103518
3459	52660	9	4	12.46	0.05	ORD-103519
3460	53971	2	2	67.38	0.15	ORD-103520
3461	52394	5	1	93.38	0.05	ORD-103521
3462	50339	18	2	15.44	0.00	ORD-103522
3463	55604	8	3	745.39	0.00	ORD-103523
3464	53688	19	2	21.39	0.10	ORD-103524
3465	54195	13	1	495.67	0.10	ORD-103525
3466	52437	9	4	11.50	0.15	ORD-103526
3467	53444	13	1	504.68	0.15	ORD-103527
3468	55102	3	1	127.55	0.15	ORD-103528
3469	55443	5	2	91.24	0.00	ORD-103529
3470	53271	8	2	771.50	0.00	ORD-103530
3471	51724	8	1	749.90	0.05	ORD-103531
3472	50758	4	1	155.61	0.00	ORD-103532
3473	55493	18	6	14.60	0.05	ORD-103533
3474	53743	19	1	21.72	0.10	ORD-103534
3475	54121	19	2	22.28	0.00	ORD-103535
3476	50817	9	5	11.70	0.00	ORD-103537
3477	51280	7	2	61.16	0.00	ORD-103538
3478	55444	10	1	174.48	0.00	ORD-103539
3479	51462	7	2	62.07	0.00	ORD-103540
3480	52340	5	1	94.25	0.05	ORD-103541
3481	55318	1	2	113.47	0.00	ORD-103542
3482	50293	2	1	73.33	0.00	ORD-103543
3483	53445	11	3	9.05	0.05	ORD-103544
3484	51049	8	3	766.50	0.05	ORD-103545
3485	53364	11	4	8.63	0.10	ORD-103546
3486	52567	5	1	86.13	0.00	ORD-103547
3487	52022	9	3	11.59	0.00	ORD-103548
3488	53972	10	1	182.19	0.05	ORD-103549
3489	55748	6	1	99.20	0.15	ORD-103550
3490	50340	9	4	12.42	0.10	ORD-103551
3491	50034	4	2	145.45	0.00	ORD-103552
3492	52090	16	1	629.62	0.05	ORD-103553
3493	51281	15	2	83.15	0.20	ORD-103554
3494	51139	18	3	14.72	0.00	ORD-103555
3495	51600	5	1	93.20	0.00	ORD-103556
3496	53547	18	5	14.43	0.20	ORD-103557
3497	53528	4	1	145.08	0.00	ORD-103558
3498	55103	6	1	92.87	0.00	ORD-103559
3499	50620	12	4	24.54	0.05	ORD-103560
3500	52179	10	2	171.82	0.20	ORD-103561
3501	50719	4	3	146.92	0.00	ORD-103562
3502	51586	12	5	24.30	0.05	ORD-103563
3503	51112	9	8	11.66	0.05	ORD-103564
3504	55021	2	2	70.85	0.00	ORD-103565
3505	51812	5	1	93.30	0.00	ORD-103566
3506	52395	11	4	9.21	0.00	ORD-103567
3507	51050	2	1	71.75	0.00	ORD-103568
3508	55605	1	2	107.56	0.05	ORD-103569
3509	51463	20	1	331.32	0.00	ORD-103570
3510	55319	5	2	93.04	0.15	ORD-103571
3511	51346	12	5	24.01	0.00	ORD-103572
3512	51396	5	2	89.84	0.05	ORD-103573
3513	54671	15	5	77.52	0.10	ORD-103574
3514	53689	6	2	91.60	0.00	ORD-103575
3515	55144	10	2	177.61	0.00	ORD-103576
3516	51540	1	5	111.12	0.20	ORD-103577
3517	53973	3	1	127.62	0.00	ORD-103578
3518	51283	9	4	11.46	0.00	ORD-103579
3519	55157	19	1	21.03	0.00	ORD-103580
3520	50413	17	1	413.66	0.05	ORD-103581
3521	51282	18	5	15.42	0.15	ORD-103582
3522	53974	9	4	12.36	0.00	ORD-103583
3523	52143	8	1	753.97	0.05	ORD-103584
3524	54930	14	3	211.68	0.00	ORD-103585
3525	52438	5	1	88.26	0.05	ORD-103586
3526	53126	15	1	78.42	0.15	ORD-103587
3527	55606	15	2	83.53	0.15	ORD-103588
3528	53446	14	1	210.47	0.00	ORD-103589
3529	50859	11	3	9.30	0.20	ORD-103590
3530	54367	11	2	9.23	0.10	ORD-103591
3531	53744	15	1	82.03	0.00	ORD-103592
3532	55022	12	4	25.44	0.10	ORD-103593
3533	52305	15	2	78.32	0.00	ORD-103594
3534	52471	2	1	72.88	0.20	ORD-103595
3535	53191	16	1	616.23	0.15	ORD-103597
3536	50610	7	4	60.59	0.10	ORD-103598
3537	52023	11	4	8.61	0.00	ORD-103599
3538	54499	17	1	409.05	0.10	ORD-103600
3539	52705	15	3	78.34	0.10	ORD-103601
3540	54931	18	5	15.30	0.00	ORD-103602
3541	50661	16	1	636.01	0.00	ORD-103603
3542	55478	14	1	216.04	0.00	ORD-103604
3543	54264	11	1	8.62	0.00	ORD-103605
3544	55136	1	1	112.92	0.00	ORD-103606
3545	51782	13	3	502.80	0.00	ORD-103607
3546	53272	8	2	781.61	0.00	ORD-103608
3547	53045	3	1	134.64	0.10	ORD-103609
3548	53273	20	1	318.08	0.00	ORD-103610
3549	50209	16	1	658.67	0.00	ORD-103611
3550	53571	7	2	58.25	0.00	ORD-103612
3551	54932	14	2	220.48	0.00	ORD-103613
3552	53193	1	1	111.88	0.00	ORD-103614
3553	53192	16	2	630.90	0.10	ORD-103615
3554	51371	5	1	86.43	0.05	ORD-103616
3555	52840	12	3	24.54	0.00	ORD-103617
3556	53904	15	1	81.73	0.05	ORD-103618
3557	53447	7	1	57.49	0.00	ORD-103619
3558	53529	3	2	131.36	0.00	ORD-103620
3559	52793	1	1	115.18	0.20	ORD-103621
3560	52632	5	3	93.58	0.00	ORD-103622
3561	52875	14	3	201.34	0.20	ORD-103623
3562	52741	2	2	70.06	0.00	ORD-103624
3563	51464	14	1	220.47	0.00	ORD-103625
3564	54469	3	1	134.76	0.00	ORD-103626
3565	51620	8	2	720.61	0.05	ORD-103627
3566	50200	14	1	210.71	0.00	ORD-103628
3567	52729	20	1	343.24	0.00	ORD-103629
3568	55607	4	2	151.46	0.00	ORD-103630
3569	54455	6	3	90.59	0.10	ORD-103631
3570	51703	13	1	509.60	0.10	ORD-103632
3571	54965	10	1	180.91	0.05	ORD-103633
3572	52987	18	3	15.65	0.00	ORD-103634
3573	54793	12	2	23.80	0.00	ORD-103635
3574	51170	17	1	418.30	0.20	ORD-103636
3575	50341	19	3	22.73	0.00	ORD-103637
3576	51284	20	1	317.75	0.00	ORD-103638
3577	54681	2	2	71.86	0.05	ORD-103639
3578	55023	14	1	219.53	0.00	ORD-103640
3579	55479	15	1	82.30	0.10	ORD-103642
3580	52876	20	2	338.07	0.00	ORD-103643
3581	51051	11	5	8.89	0.00	ORD-103644
3582	52309	16	1	633.70	0.15	ORD-103645
3583	50414	2	2	72.69	0.05	ORD-103646
3584	52272	13	1	515.92	0.10	ORD-103647
3585	55024	3	1	131.07	0.00	ORD-103648
3586	55320	2	1	69.94	0.00	ORD-103649
3587	52144	18	7	14.37	0.10	ORD-103650
3588	55583	12	4	24.75	0.00	ORD-103651
3589	55321	16	1	625.03	0.00	ORD-103652
3590	54196	19	3	22.36	0.15	ORD-103653
3591	52024	4	1	146.10	0.05	ORD-103654
3592	51347	8	3	782.33	0.15	ORD-103655
3593	55104	14	1	212.06	0.15	ORD-103656
3594	52499	16	2	662.10	0.00	ORD-103657
3595	55158	15	3	79.44	0.00	ORD-103658
3596	54966	16	1	610.46	0.20	ORD-103659
3597	55700	9	2	12.42	0.05	ORD-103660
3598	51985	11	5	8.71	0.00	ORD-103661
3599	51052	20	1	330.07	0.05	ORD-103662
3600	55025	13	1	530.75	0.15	ORD-103663
3601	50104	7	2	61.83	0.00	ORD-103664
3602	51171	15	1	77.13	0.10	ORD-103665
3603	55322	10	1	184.07	0.10	ORD-103666
3604	52819	12	6	26.11	0.15	ORD-103667
3605	50492	19	3	21.18	0.05	ORD-103668
3606	54637	2	1	70.68	0.05	ORD-103669
3607	50415	3	1	126.33	0.00	ORD-103670
3608	55527	1	2	104.80	0.05	ORD-103671
3609	51053	3	1	126.89	0.00	ORD-103672
3610	53194	10	1	173.54	0.05	ORD-103673
3611	51465	6	2	92.38	0.05	ORD-103674
3612	51053	15	1	77.38	0.15	ORD-103675
3613	50777	7	2	62.83	0.00	ORD-103676
3614	51053	12	4	23.80	0.05	ORD-103677
3615	55445	9	6	12.43	0.00	ORD-103678
3616	50294	9	3	11.76	0.05	ORD-103679
3617	54348	2	1	66.85	0.00	ORD-103680
3618	54500	12	6	25.61	0.00	ORD-103681
3619	53616	9	5	11.61	0.10	ORD-103682
3620	54039	7	1	60.52	0.00	ORD-103683
3621	54933	11	4	9.15	0.00	ORD-103684
3622	52691	4	2	154.63	0.00	ORD-103685
3623	50159	7	3	57.76	0.10	ORD-103686
3624	51335	9	7	12.00	0.05	ORD-103687
3625	52706	2	1	67.09	0.00	ORD-103688
3626	51765	15	1	82.16	0.15	ORD-103689
3627	50584	2	2	67.66	0.05	ORD-103690
3628	52396	15	2	76.05	0.10	ORD-103691
3629	51336	16	1	614.92	0.20	ORD-103692
3630	54565	4	1	144.88	0.10	ORD-103693
3631	50720	9	6	12.11	0.00	ORD-103694
3632	52376	7	1	61.36	0.05	ORD-103695
3633	51668	2	1	68.11	0.00	ORD-103696
3634	55528	17	2	404.84	0.10	ORD-103697
3635	55551	8	1	737.88	0.10	ORD-103698
3636	53195	18	3	15.41	0.00	ORD-103699
3637	54870	9	3	12.21	0.20	ORD-103700
3638	51986	2	3	67.47	0.00	ORD-103701
3639	50920	8	1	721.97	0.00	ORD-103702
3640	54088	2	1	68.66	0.00	ORD-103703
3641	52273	17	1	431.24	0.10	ORD-103704
3642	51466	19	3	20.91	0.00	ORD-103705
3643	54869	8	1	772.92	0.10	ORD-103706
3644	50160	8	3	722.37	0.00	ORD-103707
3645	53328	19	1	21.86	0.00	ORD-103708
3646	51766	6	1	99.58	0.15	ORD-103709
3647	51285	6	2	91.26	0.05	ORD-103710
3648	53105	19	2	23.09	0.10	ORD-103711
3649	53690	20	1	313.67	0.15	ORD-103712
3650	54682	14	2	200.86	0.05	ORD-103713
3651	55324	18	4	14.81	0.10	ORD-103714
3652	52377	9	2	12.08	0.05	ORD-103715
3653	50161	18	2	14.85	0.00	ORD-103716
3654	54157	13	1	501.96	0.15	ORD-103717
3655	54222	13	1	525.36	0.00	ORD-103718
3656	51337	11	8	8.66	0.00	ORD-103719
3657	53912	6	1	95.46	0.20	ORD-103720
3658	55323	6	2	99.08	0.00	ORD-103721
3659	50662	6	1	94.99	0.00	ORD-103722
3660	54040	6	1	95.27	0.00	ORD-103723
3661	53196	12	6	25.41	0.00	ORD-103724
3662	51286	20	1	343.74	0.00	ORD-103725
3663	55145	2	2	71.66	0.10	ORD-103726
3664	51467	7	3	61.99	0.00	ORD-103727
3665	52661	11	4	9.13	0.00	ORD-103728
3666	55649	14	1	218.36	0.15	ORD-103729
3667	51126	3	2	126.39	0.00	ORD-103730
3668	55026	11	4	9.17	0.00	ORD-103731
3669	53407	18	3	15.74	0.15	ORD-103732
3670	52241	19	2	21.65	0.05	ORD-103733
3671	50077	2	2	67.22	0.20	ORD-103734
3672	52242	6	2	94.97	0.00	ORD-103735
3673	50493	15	1	78.16	0.00	ORD-103736
3674	52841	11	4	8.81	0.00	ORD-103737
3675	52988	6	1	90.35	0.00	ORD-103738
3676	51904	7	3	62.30	0.00	ORD-103739
3677	53745	12	5	25.81	0.00	ORD-103740
3678	51054	13	1	521.13	0.15	ORD-103741
3679	51704	8	2	771.85	0.00	ORD-103742
3680	54833	20	1	328.08	0.05	ORD-103743
3681	55758	17	1	405.48	0.05	ORD-103744
3682	52472	18	3	14.67	0.00	ORD-103745
3683	50921	19	2	22.60	0.05	ORD-103746
3684	54303	14	1	210.86	0.15	ORD-103747
3685	53046	8	1	779.13	0.00	ORD-103748
3686	55480	5	2	89.62	0.00	ORD-103749
3687	50809	1	3	111.96	0.00	ORD-103750
3688	51905	17	2	423.44	0.15	ORD-103751
3689	55061	16	1	634.26	0.10	ORD-103752
3690	52794	19	2	22.18	0.05	ORD-103753
3691	50391	12	3	24.73	0.10	ORD-103754
3692	53548	1	2	107.61	0.20	ORD-103755
3693	51214	5	1	87.52	0.05	ORD-103756
3694	54934	15	1	77.40	0.00	ORD-103757
3695	53932	15	2	76.61	0.00	ORD-103758
3696	51287	8	1	723.26	0.00	ORD-103759
3697	53775	7	4	58.67	0.00	ORD-103760
3698	53047	2	4	67.08	0.10	ORD-103761
3699	52550	16	1	629.96	0.05	ORD-103762
3700	52568	12	5	25.96	0.05	ORD-103763
3701	53691	9	4	12.02	0.00	ORD-103764
3702	51705	3	1	123.92	0.15	ORD-103765
3703	55325	11	7	8.72	0.05	ORD-103766
3704	54441	18	2	15.56	0.20	ORD-103767
3705	50546	13	1	501.73	0.00	ORD-103768
3706	54442	14	1	208.95	0.10	ORD-103770
3707	53274	15	3	77.24	0.05	ORD-103771
3708	53692	19	5	22.93	0.05	ORD-103772
3709	51783	18	4	14.45	0.05	ORD-103773
3710	52439	5	2	85.60	0.05	ORD-103774
3711	53387	5	1	88.31	0.05	ORD-103775
3712	55769	19	4	21.86	0.00	ORD-103776
3713	54871	14	1	213.59	0.00	ORD-103777
3714	51829	11	2	8.92	0.00	ORD-103778
3715	55326	3	1	131.20	0.00	ORD-103779
3716	52989	15	1	82.89	0.05	ORD-103780
3717	51056	14	1	209.60	0.00	ORD-103781
3718	55327	1	3	107.29	0.00	ORD-103782
3719	51288	20	2	317.65	0.00	ORD-103783
3720	54516	1	1	110.84	0.00	ORD-103784
3721	51055	1	1	108.28	0.00	ORD-103785
3722	51057	16	1	627.89	0.05	ORD-103786
3723	52662	7	5	57.43	0.05	ORD-103787
3724	53549	20	1	332.10	0.10	ORD-103788
3725	55027	2	1	68.97	0.10	ORD-103789
3726	52341	12	3	26.18	0.05	ORD-103790
3727	53048	20	1	328.10	0.00	ORD-103791
3728	53975	5	1	89.36	0.05	ORD-103792
3729	53746	20	1	346.11	0.05	ORD-103793
3730	54396	15	2	79.91	0.00	ORD-103794
3731	54872	15	1	76.01	0.05	ORD-103795
3732	51172	1	1	112.72	0.00	ORD-103796
3733	52342	18	2	15.17	0.00	ORD-103797
3734	51906	1	1	114.81	0.00	ORD-103798
3735	51289	16	1	661.80	0.15	ORD-103799
3736	53197	11	3	8.66	0.00	ORD-103800
3737	52025	7	2	58.88	0.00	ORD-103801
3738	52990	10	1	181.71	0.00	ORD-103802
3739	54158	20	1	335.95	0.00	ORD-103803
3740	54223	15	2	78.30	0.00	ORD-103804
3741	51058	4	2	148.32	0.10	ORD-103805
3742	53049	8	2	729.21	0.05	ORD-103806
3743	53408	5	2	89.21	0.00	ORD-103807
3744	55328	16	1	632.32	0.00	ORD-103808
3745	51587	9	3	11.54	0.00	ORD-103809
3746	50721	11	6	9.29	0.00	ORD-103810
3747	55650	5	3	89.78	0.00	ORD-103811
3748	50860	18	3	15.62	0.00	ORD-103812
3749	53976	19	3	21.39	0.20	ORD-103813
3750	51907	13	1	515.69	0.00	ORD-103814
3751	54794	11	3	8.69	0.00	ORD-103815
3752	54304	16	1	649.60	0.00	ORD-103816
3753	55329	10	1	181.70	0.15	ORD-103817
3754	54729	7	4	58.98	0.00	ORD-103818
3755	52991	20	2	337.31	0.00	ORD-103819
3756	50342	1	2	107.03	0.00	ORD-103820
3757	54349	12	1	23.94	0.00	ORD-103821
3758	51146	19	1	22.53	0.05	ORD-103822
3759	54159	19	1	21.38	0.00	ORD-103823
3760	52317	20	1	339.45	0.00	ORD-103824
3761	52343	9	5	11.43	0.05	ORD-103825
3762	53448	8	1	766.18	0.10	ORD-103826
3763	50416	12	2	23.91	0.15	ORD-103827
3764	50585	4	1	147.78	0.00	ORD-103828
3765	50344	13	1	520.35	0.10	ORD-103829
3766	50861	9	2	12.11	0.00	ORD-103830
3767	52742	12	3	24.89	0.00	ORD-103831
3768	52721	2	1	71.31	0.15	ORD-103832
3769	52397	15	2	78.12	0.20	ORD-103833
3770	50343	19	2	22.93	0.00	ORD-103834
3771	52516	11	3	8.69	0.00	ORD-103835
3772	52992	14	1	215.21	0.15	ORD-103836
3773	53550	12	2	25.30	0.00	ORD-103837
3774	51621	5	1	86.69	0.00	ORD-103838
3775	53198	6	2	99.07	0.00	ORD-103839
3776	50722	2	2	70.55	0.10	ORD-103840
3777	52398	9	5	11.56	0.05	ORD-103841
3778	55028	16	1	635.94	0.00	ORD-103842
3779	55330	17	1	419.65	0.05	ORD-103843
3780	52608	7	3	57.79	0.10	ORD-103844
3781	54501	7	2	59.38	0.20	ORD-103845
3782	55105	2	1	71.69	0.00	ORD-103846
3783	52795	1	2	108.41	0.15	ORD-103847
3784	50345	5	2	89.59	0.00	ORD-103848
3785	54638	14	1	218.10	0.00	ORD-103849
3786	50494	18	5	15.56	0.05	ORD-103850
3787	50495	15	2	77.30	0.05	ORD-103851
3788	53693	6	6	97.48	0.15	ORD-103852
3789	52274	11	4	9.34	0.10	ORD-103853
3790	52956	11	7	8.89	0.00	ORD-103855
3791	55331	9	2	12.18	0.00	ORD-103856
3792	51113	3	1	123.64	0.05	ORD-103857
3793	51541	20	1	313.84	0.00	ORD-103858
3794	54935	15	1	79.82	0.00	ORD-103859
3795	52877	9	3	11.76	0.00	ORD-103860
3796	55626	10	1	176.54	0.05	ORD-103861
3797	53329	4	1	148.14	0.00	ORD-103862
3798	52180	19	2	22.52	0.00	ORD-103863
3799	50663	7	3	61.25	0.00	ORD-103864
3800	50664	13	1	509.68	0.05	ORD-103865
3801	54936	11	5	8.99	0.00	ORD-103866
3802	51601	16	1	648.44	0.10	ORD-103867
3803	52318	1	1	112.62	0.05	ORD-103868
3804	50749	8	1	764.45	0.05	ORD-103869
3805	51908	19	2	21.78	0.00	ORD-103870
3806	52473	19	1	22.63	0.05	ORD-103871
3807	55529	7	1	62.66	0.05	ORD-103872
3808	51468	13	1	526.87	0.00	ORD-103873
3809	53577	9	5	12.53	0.05	ORD-103874
3810	55671	11	6	8.71	0.00	ORD-103875
3811	50295	7	2	59.96	0.10	ORD-103876
3812	50665	19	3	22.81	0.00	ORD-103877
3813	53365	1	1	114.73	0.20	ORD-103878
3814	51678	12	3	24.47	0.00	ORD-103879
3815	50257	15	2	78.93	0.00	ORD-103880
3816	51706	3	1	129.89	0.10	ORD-103881
3817	50222	1	1	105.76	0.00	ORD-103882
3818	50162	20	2	339.21	0.05	ORD-103883
3819	50559	5	1	93.12	0.05	ORD-103884
3820	54398	8	1	784.59	0.10	ORD-103885
3821	54397	18	3	14.54	0.00	ORD-103886
3822	53977	2	1	68.14	0.00	ORD-103887
3823	54330	4	1	153.95	0.15	ORD-103888
3824	55584	12	5	24.51	0.00	ORD-103889
3825	54305	4	1	144.87	0.00	ORD-103890
3826	52181	19	3	21.06	0.05	ORD-103891
3827	53747	18	5	15.36	0.10	ORD-103892
3828	50611	5	1	91.38	0.00	ORD-103893
3829	52440	16	1	620.14	0.00	ORD-103894
3830	51059	4	2	152.03	0.10	ORD-103895
3831	55106	19	4	23.03	0.15	ORD-103896
3832	55332	7	1	59.87	0.15	ORD-103897
3833	53933	11	5	9.34	0.00	ORD-103898
3834	52474	19	1	21.81	0.10	ORD-103899
3835	50862	8	3	717.72	0.05	ORD-103900
3836	53050	9	4	12.59	0.10	ORD-103901
3837	54265	13	1	521.48	0.20	ORD-103904
3838	54224	13	2	495.10	0.05	ORD-103905
3839	51060	5	3	87.23	0.05	ORD-103906
3840	50863	14	1	203.60	0.00	ORD-103907
3841	55333	14	3	206.00	0.00	ORD-103908
3842	52842	15	1	81.81	0.00	ORD-103909
3843	54306	9	4	11.95	0.00	ORD-103910
3844	55029	12	5	26.13	0.00	ORD-103911
3845	51669	14	2	213.15	0.00	ORD-103912
3846	53823	13	2	536.25	0.05	ORD-103913
3847	55031	2	2	70.50	0.00	ORD-103915
3848	50723	18	4	14.27	0.10	ORD-103916
3849	52993	11	7	9.24	0.00	ORD-103917
3850	55334	2	1	71.94	0.00	ORD-103918
3851	55030	15	2	82.80	0.00	ORD-103919
3852	55530	15	3	76.18	0.15	ORD-103920
3853	52378	16	1	641.24	0.00	ORD-103921
3854	51290	12	6	26.21	0.00	ORD-103922
3855	51725	7	3	61.50	0.10	ORD-103923
3856	50258	3	1	124.58	0.05	ORD-103924
3857	50163	4	1	148.28	0.10	ORD-103925
3858	50787	7	3	58.87	0.05	ORD-103926
3859	53919	18	4	14.29	0.10	ORD-103927
3860	50468	16	1	655.06	0.20	ORD-103928
3861	54730	9	3	11.66	0.00	ORD-103929
3862	53617	12	6	24.63	0.05	ORD-103930
3863	53330	6	1	93.02	0.00	ORD-103931
3864	54873	4	2	144.36	0.00	ORD-103932
3865	51196	1	1	114.27	0.15	ORD-103933
3866	50346	12	2	24.57	0.05	ORD-103934
3867	52609	20	2	327.74	0.00	ORD-103935
3868	50759	5	1	91.11	0.00	ORD-103936
3869	53618	7	3	62.70	0.15	ORD-103937
3870	54937	13	1	533.54	0.00	ORD-103938
3871	54041	4	1	146.69	0.20	ORD-103939
3872	54795	12	6	24.68	0.15	ORD-103940
3873	55336	12	6	23.93	0.20	ORD-103941
3874	53889	16	3	669.98	0.15	ORD-103942
3875	54470	15	1	80.32	0.00	ORD-103943
3876	52796	11	3	9.45	0.05	ORD-103944
3877	51909	11	5	8.95	0.00	ORD-103946
3878	55335	18	4	15.23	0.00	ORD-103947
3879	54601	20	3	333.57	0.20	ORD-103948
3880	51397	11	2	8.76	0.05	ORD-103949
3881	52610	6	2	95.57	0.00	ORD-103950
3882	53694	12	7	25.22	0.00	ORD-103951
3883	52045	6	2	91.44	0.00	ORD-103952
3884	54874	6	3	94.38	0.05	ORD-103953
3885	50105	8	1	775.40	0.00	ORD-103954
3886	51602	9	8	12.12	0.00	ORD-103955
3887	53199	13	1	503.10	0.00	ORD-103956
3888	50864	8	1	760.80	0.20	ORD-103957
3889	53748	14	1	211.70	0.00	ORD-103958
3890	54122	9	4	12.51	0.00	ORD-103959
3891	53749	12	1	25.02	0.00	ORD-103960
3892	53275	11	5	9.22	0.00	ORD-103961
3893	53750	9	6	12.51	0.00	ORD-103962
3894	52275	19	1	22.04	0.00	ORD-103963
3895	50865	13	1	508.72	0.00	ORD-103964
3896	50164	8	2	774.31	0.00	ORD-103965
3897	52625	20	1	319.59	0.10	ORD-103966
3898	50347	12	5	23.91	0.00	ORD-103967
3899	50348	16	1	638.38	0.20	ORD-103968
3900	53978	18	3	14.31	0.05	ORD-103970
3901	55337	6	2	95.35	0.10	ORD-103971
3902	50724	1	5	114.28	0.20	ORD-103972
3903	54666	5	2	90.68	0.00	ORD-103973
3904	50457	14	1	201.71	0.10	ORD-103974
3905	50469	20	1	332.77	0.00	ORD-103975
3906	52611	8	1	785.90	0.05	ORD-103976
3907	51127	6	4	90.64	0.00	ORD-103977
3908	52551	2	1	71.87	0.00	ORD-103978
3909	54566	9	5	11.90	0.05	ORD-103979
3910	53276	1	1	109.08	0.15	ORD-103980
3911	55107	19	1	21.04	0.05	ORD-103981
3912	51061	18	3	15.07	0.10	ORD-103982
3913	55032	9	6	11.87	0.00	ORD-103983
3914	52663	16	2	666.42	0.00	ORD-103984
3915	53449	10	1	187.90	0.00	ORD-103985
3916	53824	17	1	421.93	0.05	ORD-103986
3917	55531	19	2	22.80	0.00	ORD-103987
3918	52569	14	2	213.70	0.00	ORD-103988
3919	54639	13	1	520.77	0.20	ORD-103989
3920	53825	6	3	91.52	0.05	ORD-103990
3921	53530	7	2	61.79	0.10	ORD-103991
3922	54055	10	1	175.77	0.05	ORD-103992
3923	51987	15	2	80.19	0.00	ORD-103993
3924	54938	18	5	14.90	0.05	ORD-103994
3925	50165	3	2	126.51	0.10	ORD-103995
3926	51573	16	1	619.55	0.05	ORD-103996
3927	50392	15	2	81.40	0.05	ORD-103997
3928	55338	19	1	22.43	0.10	ORD-103998
3929	51215	5	1	92.36	0.00	ORD-103999
3930	53277	17	1	427.81	0.10	ORD-104000
3931	52664	13	2	540.99	0.05	ORD-104001
3932	52730	2	2	69.18	0.00	ORD-104002
3933	53869	6	3	92.74	0.10	ORD-104003
3934	52344	4	1	150.94	0.10	ORD-104004
3935	50496	13	2	515.42	0.10	ORD-104005
3936	52782	13	3	543.74	0.00	ORD-104006
3937	53388	10	1	175.56	0.05	ORD-104007
3938	50349	20	1	327.71	0.00	ORD-104009
3939	55481	5	2	87.85	0.05	ORD-104010
3940	52091	16	2	637.58	0.00	ORD-104011
3941	53475	10	2	187.56	0.15	ORD-104012
3942	52957	17	1	401.55	0.15	ORD-104013
3943	52665	11	9	8.58	0.00	ORD-104014
3944	55482	15	3	76.83	0.00	ORD-104015
3945	50259	12	4	24.60	0.00	ORD-104016
3946	51542	11	6	8.89	0.05	ORD-104017
3947	52546	13	2	532.88	0.00	ORD-104018
3948	51173	4	1	146.98	0.05	ORD-104019
3949	51469	5	2	92.23	0.00	ORD-104021
3950	54533	11	4	9.17	0.00	ORD-104022
3951	51062	16	2	639.15	0.00	ORD-104023
3952	54517	9	1	11.58	0.10	ORD-104024
3953	54567	17	2	407.94	0.00	ORD-104026
3954	51291	6	3	96.93	0.00	ORD-104027
3955	51988	2	1	70.71	0.05	ORD-104028
3956	53278	9	6	11.76	0.00	ORD-104029
3957	55339	20	2	319.74	0.00	ORD-104030
3958	55715	2	1	70.28	0.10	ORD-104031
3959	51147	9	2	11.77	0.10	ORD-104032
3960	50560	13	1	531.76	0.10	ORD-104033
3961	55532	18	4	14.88	0.20	ORD-104034
3962	51063	5	3	93.95	0.10	ORD-104035
3963	50666	3	1	132.17	0.00	ORD-104036
3964	50612	5	1	90.46	0.00	ORD-104037
3965	51114	4	1	154.41	0.00	ORD-104038
3966	50417	12	5	24.34	0.10	ORD-104039
3967	53695	6	4	95.32	0.20	ORD-104040
3968	52517	6	1	90.78	0.00	ORD-104041
3969	55159	9	5	11.92	0.10	ORD-104042
3970	50750	6	2	90.92	0.00	ORD-104043
3971	50166	6	1	94.64	0.00	ORD-104044
3972	50260	14	2	216.80	0.05	ORD-104045
3973	51359	6	2	98.34	0.10	ORD-104046
3974	50922	1	2	114.76	0.00	ORD-104047
3975	54123	20	2	332.83	0.00	ORD-104048
3976	52666	20	2	317.08	0.00	ORD-104049
3977	53200	1	1	114.75	0.00	ORD-104050
3978	51174	18	3	15.29	0.15	ORD-104051
3979	54056	11	6	9.28	0.00	ORD-104052
3980	54731	15	1	79.78	0.00	ORD-104053
3981	50167	15	2	82.24	0.10	ORD-104054
3982	52667	1	1	109.70	0.10	ORD-104055
3983	52878	9	5	11.55	0.00	ORD-104056
3984	53826	5	1	94.26	0.05	ORD-104057
3985	52319	8	1	758.46	0.00	ORD-104058
3986	55340	13	2	524.28	0.00	ORD-104059
3987	52743	11	5	9.05	0.00	ORD-104060
3988	55533	15	3	83.16	0.00	ORD-104061
3989	51543	1	1	115.20	0.00	ORD-104062
3990	51064	6	1	93.25	0.00	ORD-104063
3991	53201	20	2	343.83	0.10	ORD-104064
3992	51065	9	2	12.31	0.15	ORD-104065
3993	52475	5	2	91.54	0.10	ORD-104066
3994	51544	15	1	78.55	0.10	ORD-104067
3995	54042	18	6	15.70	0.00	ORD-104068
3996	54043	7	2	58.64	0.10	ORD-104069
3997	50418	10	1	181.15	0.05	ORD-104070
3998	54796	4	1	155.44	0.00	ORD-104071
3999	54160	8	2	747.25	0.05	ORD-104072
4000	51148	9	3	11.76	0.00	ORD-104073
4001	52759	13	1	501.36	0.00	ORD-104074
4002	55716	8	1	785.66	0.00	ORD-104075
4003	52518	11	6	9.06	0.00	ORD-104076
4004	50296	4	1	154.62	0.00	ORD-104077
4005	54640	13	2	515.05	0.05	ORD-104078
4006	50631	12	3	25.68	0.15	ORD-104079
4007	53051	1	2	115.08	0.00	ORD-104080
4008	53572	13	1	501.72	0.15	ORD-104081
4009	54754	6	1	97.63	0.00	ORD-104082
4010	53202	5	2	85.74	0.10	ORD-104083
4011	54502	19	1	21.57	0.00	ORD-104084
4012	54641	14	2	212.51	0.00	ORD-104085
4013	52768	6	1	93.71	0.00	ORD-104086
4014	52925	19	3	23.03	0.10	ORD-104087
4015	50168	18	3	15.51	0.15	ORD-104088
4016	50586	6	3	98.68	0.00	ORD-104089
4017	51470	18	4	15.20	0.10	ORD-104090
4018	50725	7	1	60.20	0.15	ORD-104091
4019	54225	5	3	93.54	0.00	ORD-104092
4020	55341	4	1	147.94	0.10	ORD-104093
4021	51622	11	6	8.79	0.05	ORD-104094
4022	52092	9	5	11.91	0.00	ORD-104095
4023	52519	1	1	110.38	0.10	ORD-104096
4024	51502	18	7	15.07	0.10	ORD-104097
4025	50923	7	1	59.23	0.00	ORD-104098
4026	53979	6	3	98.53	0.00	ORD-104099
4027	53331	2	2	72.63	0.00	ORD-104100
4028	52879	6	2	92.53	0.10	ORD-104101
4029	52122	4	2	151.80	0.00	ORD-104102
4030	50106	11	4	8.78	0.00	ORD-104103
4031	53279	1	1	106.12	0.00	ORD-104104
4032	52345	9	5	12.31	0.10	ORD-104105
4033	55108	5	3	93.42	0.05	ORD-104106
4034	50035	13	1	532.97	0.00	ORD-104107
4035	52221	14	1	210.86	0.15	ORD-104108
4036	53450	17	1	411.09	0.00	ORD-104109
4037	55146	5	1	91.63	0.15	ORD-104110
4038	50726	15	2	83.74	0.00	ORD-104111
4039	51292	18	8	14.41	0.10	ORD-104112
4040	52276	5	1	90.03	0.00	ORD-104113
4041	51989	8	2	776.49	0.00	ORD-104114
4042	55741	11	4	9.45	0.00	ORD-104115
4043	55483	20	1	328.19	0.00	ORD-104116
4044	54307	9	4	12.31	0.00	ORD-104117
4045	50350	11	3	8.56	0.05	ORD-104118
4046	50169	2	1	72.12	0.00	ORD-104119
4047	53751	20	3	328.56	0.00	ORD-104120
4048	51603	12	3	25.95	0.00	ORD-104121
4049	53776	9	3	11.40	0.10	ORD-104122
4050	51293	13	3	528.01	0.00	ORD-104123
4051	54226	10	1	173.65	0.00	ORD-104124
4052	51910	5	2	91.13	0.00	ORD-104125
4053	53696	3	1	133.03	0.00	ORD-104126
4054	54568	6	3	95.07	0.00	ORD-104127
4055	53502	6	1	96.90	0.10	ORD-104128
4056	55342	5	1	89.46	0.00	ORD-104129
4057	52958	12	8	24.01	0.00	ORD-104130
4058	55801	17	1	412.33	0.05	ORD-104131
4059	51471	8	1	780.40	0.10	ORD-104132
4060	55343	18	3	15.00	0.05	ORD-104133
4061	53827	9	6	12.05	0.00	ORD-104134
4062	53132	9	4	12.14	0.00	ORD-104135
4063	52346	11	5	8.65	0.00	ORD-104136
4064	54057	19	1	21.07	0.05	ORD-104137
4065	52207	15	1	77.68	0.00	ORD-104138
4066	51472	4	1	144.12	0.10	ORD-104139
4067	54266	19	2	20.90	0.10	ORD-104140
4068	54939	9	4	11.41	0.00	ORD-104141
4069	51066	10	1	181.51	0.00	ORD-104142
4070	50442	16	1	614.75	0.05	ORD-104143
4071	52399	11	1	8.62	0.05	ORD-104144
4072	52182	18	7	14.72	0.05	ORD-104145
4073	52843	13	1	542.26	0.00	ORD-104146
4074	50760	6	2	96.51	0.05	ORD-104147
4075	53828	13	2	499.25	0.05	ORD-104148
4076	50667	9	4	11.66	0.00	ORD-104149
4077	53389	4	1	151.87	0.15	ORD-104150
4078	54267	5	2	90.74	0.05	ORD-104151
4079	55344	18	4	14.47	0.05	ORD-104152
4080	55345	9	3	12.46	0.05	ORD-104153
4081	53980	3	1	136.15	0.20	ORD-104154
4082	54642	15	1	79.43	0.00	ORD-104155
4083	52093	6	1	90.88	0.00	ORD-104156
4084	55627	6	2	90.76	0.00	ORD-104157
4085	50351	15	1	76.05	0.00	ORD-104158
4086	51791	4	1	146.88	0.10	ORD-104159
4087	54584	2	1	66.57	0.10	ORD-104160
4088	50352	18	4	15.33	0.05	ORD-104161
4089	51294	12	6	24.54	0.00	ORD-104162
4090	53981	5	1	89.14	0.10	ORD-104163
4091	51813	14	1	214.63	0.20	ORD-104164
4092	54797	9	3	11.61	0.05	ORD-104165
4093	53451	11	6	9.19	0.10	ORD-104166
4094	54089	9	4	12.25	0.05	ORD-104167
4095	54399	12	4	26.03	0.00	ORD-104168
4096	51656	19	3	21.99	0.05	ORD-104169
4097	54798	9	2	11.91	0.00	ORD-104170
4098	52277	1	1	109.77	0.00	ORD-104171
4099	51067	20	1	327.15	0.00	ORD-104172
4100	51767	2	1	71.77	0.00	ORD-104173
4101	54967	13	2	536.17	0.00	ORD-104174
4102	51068	13	1	502.85	0.10	ORD-104175
4103	50727	20	1	346.32	0.00	ORD-104176
4104	55502	15	2	81.45	0.05	ORD-104177
4105	55717	19	2	22.27	0.15	ORD-104178
4106	52347	5	2	85.66	0.15	ORD-104179
4107	52668	11	4	9.11	0.15	ORD-104180
4108	52820	6	1	93.34	0.05	ORD-104181
4109	52026	9	5	11.61	0.00	ORD-104182
4110	52959	18	2	14.87	0.05	ORD-104183
4111	50788	11	7	8.85	0.20	ORD-104184
4112	53565	2	2	69.11	0.05	ORD-104185
4113	52707	5	1	91.41	0.00	ORD-104186
4114	51151	12	3	25.64	0.00	ORD-104187
4115	51372	3	2	129.79	0.05	ORD-104188
4116	51503	8	3	718.43	0.00	ORD-104189
4117	51623	2	1	70.72	0.00	ORD-104190
4118	50866	19	2	22.63	0.05	ORD-104191
4119	53390	18	4	15.21	0.00	ORD-104192
4120	55759	9	7	11.54	0.05	ORD-104193
4121	50297	17	1	435.35	0.00	ORD-104194
4122	55346	7	2	59.35	0.05	ORD-104195
4123	53890	9	6	11.63	0.00	ORD-104196
4124	53982	8	1	762.90	0.05	ORD-104197
4125	51612	9	3	11.43	0.05	ORD-104198
4126	51657	14	1	206.21	0.15	ORD-104199
4127	52400	11	2	8.82	0.10	ORD-104200
4128	50170	19	4	22.89	0.05	ORD-104201
4129	51216	8	2	770.40	0.00	ORD-104202
4130	51069	5	1	94.31	0.05	ORD-104203
4131	50353	14	1	209.39	0.05	ORD-104204
4132	51140	9	6	12.25	0.00	ORD-104205
4133	53619	5	1	93.48	0.10	ORD-104206
4134	51128	9	4	12.06	0.05	ORD-104207
4135	52310	13	1	532.03	0.00	ORD-104208
4136	53332	8	2	782.61	0.10	ORD-104209
4137	51373	14	1	201.31	0.05	ORD-104210
4138	53984	20	2	325.19	0.00	ORD-104211
4139	51969	10	1	184.35	0.00	ORD-104212
4140	54643	2	1	68.70	0.00	ORD-104213
4141	55484	3	1	132.22	0.00	ORD-104214
4142	50825	7	1	61.66	0.00	ORD-104215
4143	53983	11	4	9.12	0.00	ORD-104216
4144	51348	11	4	9.14	0.00	ORD-104217
4145	53934	20	1	332.81	0.00	ORD-104218
4146	53119	9	4	11.73	0.05	ORD-104219
4147	52769	18	2	15.19	0.00	ORD-104220
4148	51911	11	3	9.00	0.00	ORD-104221
4149	53391	4	2	146.38	0.15	ORD-104222
4150	52476	11	5	8.59	0.05	ORD-104223
4151	55109	17	1	430.56	0.00	ORD-104224
4152	54110	7	3	58.52	0.10	ORD-104225
4153	55503	4	1	153.41	0.00	ORD-104226
4154	55033	4	1	145.72	0.10	ORD-104227
4155	51474	9	7	12.11	0.05	ORD-104228
4156	50810	18	4	15.64	0.15	ORD-104229
4157	51473	2	2	67.53	0.05	ORD-104230
4158	52552	7	4	57.66	0.00	ORD-104231
4159	55585	6	1	95.00	0.00	ORD-104232
4160	54644	6	1	95.43	0.00	ORD-104233
4161	54645	10	2	185.92	0.10	ORD-104234
4162	53829	5	1	94.18	0.10	ORD-104235
4163	54799	12	4	24.84	0.20	ORD-104236
4164	53985	11	4	8.75	0.00	ORD-104237
4165	50632	2	1	67.75	0.00	ORD-104238
4166	51990	20	2	342.81	0.00	ORD-104239
4167	50171	9	6	12.30	0.10	ORD-104240
4168	51115	9	6	12.18	0.15	ORD-104241
4169	54483	13	3	523.42	0.10	ORD-104242
4170	52027	18	5	15.63	0.00	ORD-104243
4171	52844	13	1	509.22	0.05	ORD-104244
4172	53551	7	2	59.75	0.15	ORD-104245
4173	54940	13	2	495.04	0.00	ORD-104246
4174	51738	6	3	98.02	0.05	ORD-104247
4175	51070	2	2	72.37	0.05	ORD-104248
4176	52123	11	5	8.65	0.15	ORD-104249
4177	55347	7	2	58.49	0.10	ORD-104250
4178	51295	9	1	12.58	0.05	ORD-104251
4179	55732	5	2	93.59	0.00	ORD-104252
4180	54350	15	1	83.44	0.00	ORD-104253
4181	50073	19	2	22.78	0.00	ORD-104254
4182	52520	11	6	9.39	0.00	ORD-104255
4183	54400	20	1	346.15	0.05	ORD-104256
4184	53986	7	2	58.81	0.20	ORD-104257
4185	51545	17	1	423.14	0.00	ORD-104258
4186	52183	20	1	328.63	0.15	ORD-104259
4187	52367	11	2	9.19	0.00	ORD-104260
4188	53280	7	2	59.09	0.00	ORD-104261
4189	51374	16	2	614.20	0.10	ORD-104262
4190	54646	19	3	21.77	0.15	ORD-104263
4191	51912	9	4	12.15	0.00	ORD-104264
4192	50078	18	3	15.58	0.20	ORD-104265
4193	53476	12	4	24.99	0.00	ORD-104266
4194	52880	7	2	58.12	0.00	ORD-104267
4195	52145	5	2	91.16	0.00	ORD-104268
4196	54941	20	2	345.69	0.00	ORD-104269
4197	50298	1	3	109.64	0.05	ORD-104270
4198	53281	6	1	91.99	0.05	ORD-104271
4199	52783	14	1	205.24	0.05	ORD-104272
4200	52521	4	2	156.36	0.15	ORD-104273
4201	50261	4	1	147.33	0.00	ORD-104274
4202	52278	14	2	214.11	0.05	ORD-104275
4203	51175	12	4	24.77	0.00	ORD-104276
4204	52184	14	1	217.72	0.00	ORD-104277
4205	54090	13	1	526.84	0.00	ORD-104278
4206	50668	14	2	199.57	0.15	ORD-104279
4207	54182	6	1	93.14	0.00	ORD-104280
4208	55348	19	1	22.82	0.00	ORD-104281
4209	52094	8	2	762.67	0.00	ORD-104282
4210	53531	8	1	747.20	0.00	ORD-104283
4211	50587	16	1	619.10	0.15	ORD-104284
4212	51679	13	2	513.10	0.00	ORD-104285
4213	54648	17	1	400.38	0.00	ORD-104286
4214	53203	14	2	211.91	0.00	ORD-104287
4215	52994	19	3	20.99	0.00	ORD-104288
4216	51913	14	2	210.72	0.05	ORD-104289
4217	52570	20	3	334.62	0.10	ORD-104290
4218	54647	8	2	723.30	0.00	ORD-104291
4219	53095	1	1	108.07	0.00	ORD-104292
4220	55534	18	4	15.15	0.05	ORD-104293
4221	50036	9	1	12.41	0.00	ORD-104294
4222	51217	8	4	772.59	0.00	ORD-104295
4223	51071	17	1	425.60	0.00	ORD-104296
4224	52547	18	2	14.96	0.05	ORD-104297
4225	50761	16	1	645.90	0.00	ORD-104298
4226	52744	13	1	511.81	0.00	ORD-104299
4227	54691	5	1	93.28	0.00	ORD-104300
4228	50826	12	4	25.87	0.05	ORD-104301
4229	54942	4	2	156.31	0.00	ORD-104302
4230	54401	12	5	25.38	0.00	ORD-104303
4231	52028	14	1	200.92	0.05	ORD-104304
4232	52095	14	1	200.97	0.00	ORD-104305
4233	50037	9	4	12.49	0.00	ORD-104306
4234	55726	14	1	213.91	0.05	ORD-104307
4235	53532	1	3	112.61	0.10	ORD-104308
4236	50172	16	1	610.63	0.00	ORD-104309
4237	50173	17	1	400.86	0.00	ORD-104310
4238	54268	17	1	427.94	0.00	ORD-104311
4239	54649	12	5	25.92	0.05	ORD-104312
4240	51475	3	1	131.96	0.05	ORD-104313
4241	53620	6	2	98.91	0.20	ORD-104314
4242	55349	11	5	8.95	0.00	ORD-104315
4243	52571	17	1	422.78	0.00	ORD-104316
4244	50354	7	2	58.92	0.05	ORD-104317
4245	51914	14	1	215.62	0.00	ORD-104318
4246	53621	19	1	21.31	0.00	ORD-104319
4247	53052	18	5	14.57	0.00	ORD-104320
4248	52845	1	1	113.07	0.00	ORD-104321
4249	52612	4	2	145.42	0.00	ORD-104322
4250	53935	13	1	520.16	0.00	ORD-104323
4251	54183	20	1	320.60	0.10	ORD-104324
4252	50262	20	1	313.57	0.00	ORD-104325
4253	54368	11	5	8.84	0.00	ORD-104326
4254	50751	11	3	9.41	0.00	ORD-104327
4255	53752	10	1	181.46	0.05	ORD-104328
4256	51176	9	4	11.57	0.00	ORD-104329
4257	55569	3	1	127.05	0.00	ORD-104330
4258	53622	12	2	26.04	0.05	ORD-104331
4259	55760	5	2	87.10	0.10	ORD-104332
4260	53333	19	1	22.10	0.00	ORD-104333
4261	52846	11	8	8.56	0.00	ORD-104334
4262	51546	15	2	78.57	0.10	ORD-104335
4263	50728	16	1	631.55	0.10	ORD-104336
4264	53987	9	6	11.94	0.05	ORD-104337
4265	54650	20	1	343.37	0.00	ORD-104338
4266	53350	17	1	423.43	0.05	ORD-104339
4267	52797	5	1	87.20	0.15	ORD-104340
4268	52583	18	1	15.32	0.00	ORD-104341
4269	55110	14	1	217.96	0.20	ORD-104342
4270	50443	19	1	21.28	0.00	ORD-104343
4271	55350	8	2	714.66	0.05	ORD-104344
4272	51658	12	7	25.52	0.15	ORD-104345
4273	54683	8	2	771.23	0.05	ORD-104346
4274	55820	12	6	25.93	0.00	ORD-104347
4275	50419	7	2	58.90	0.10	ORD-104348
4276	52222	17	1	410.53	0.05	ORD-104349
4277	54443	13	1	511.15	0.15	ORD-104350
4278	52669	12	3	24.52	0.00	ORD-104351
4279	54227	2	4	69.26	0.05	ORD-104352
4280	54269	15	2	82.05	0.00	ORD-104353
4281	54133	19	3	23.01	0.05	ORD-104354
4282	50174	7	1	62.97	0.00	ORD-104355
4283	53366	13	1	529.18	0.00	ORD-104356
4284	51375	13	1	499.81	0.05	ORD-104357
4285	51830	17	1	425.35	0.00	ORD-104358
4286	52320	15	1	80.67	0.15	ORD-104359
4287	54585	5	2	90.22	0.10	ORD-104360
4288	51338	17	2	400.77	0.00	ORD-104361
4289	54058	12	5	25.67	0.10	ORD-104362
4290	53367	20	1	344.65	0.00	ORD-104363
4291	50079	16	1	647.39	0.00	ORD-104364
4292	50729	3	1	132.64	0.00	ORD-104365
4293	50085	14	3	214.96	0.10	ORD-104366
4294	50633	6	2	96.12	0.00	ORD-104367
4295	50515	2	1	72.10	0.05	ORD-104368
4296	55351	8	1	774.28	0.10	ORD-104369
4297	54651	9	2	11.68	0.00	ORD-104370
4298	55111	14	1	214.13	0.20	ORD-104371
4299	50811	11	3	9.02	0.00	ORD-104372
4300	51768	6	2	93.40	0.00	ORD-104373
4301	50470	17	1	440.06	0.00	ORD-104374
4302	53334	13	2	535.56	0.00	ORD-104375
4303	54602	13	1	536.19	0.00	ORD-104376
4304	54875	8	1	757.09	0.20	ORD-104377
4305	50175	9	2	11.63	0.10	ORD-104378
4306	54534	3	1	134.25	0.05	ORD-104379
4307	54270	2	1	67.14	0.00	ORD-104380
4308	53988	9	5	12.21	0.00	ORD-104381
4309	52348	17	1	436.70	0.00	ORD-104382
4310	55352	11	4	8.58	0.05	ORD-104383
4311	53282	14	1	212.43	0.10	ORD-104384
4312	54337	18	6	14.94	0.05	ORD-104385
4313	54503	10	1	185.28	0.05	ORD-104386
4314	50669	5	1	89.35	0.00	ORD-104387
4315	53891	7	2	60.67	0.10	ORD-104388
4316	54876	3	1	125.43	0.15	ORD-104389
4317	52414	5	1	89.82	0.10	ORD-104390
4318	52230	10	1	177.53	0.05	ORD-104391
4319	55352	12	5	25.90	0.15	ORD-104392
4320	54308	9	6	12.13	0.00	ORD-104393
4321	52096	20	1	334.32	0.10	ORD-104394
4322	51072	2	1	70.35	0.05	ORD-104395
4323	54271	15	1	82.42	0.15	ORD-104396
4324	50299	9	2	12.07	0.00	ORD-104397
4325	52401	3	2	133.60	0.10	ORD-104398
4326	53573	9	6	11.49	0.00	ORD-104399
4327	55608	5	1	88.01	0.20	ORD-104400
4328	50420	12	5	25.23	0.00	ORD-104401
4329	50038	6	2	94.10	0.00	ORD-104402
4330	51915	20	3	314.47	0.00	ORD-104403
4331	51680	11	3	9.21	0.00	ORD-104404
4332	55112	4	1	148.63	0.00	ORD-104405
4333	55586	12	3	24.57	0.05	ORD-104406
4334	53205	5	3	90.08	0.05	ORD-104407
4335	53204	12	4	25.32	0.00	ORD-104408
4336	54402	13	1	518.46	0.00	ORD-104409
4337	53920	4	1	146.49	0.00	ORD-104410
4338	55504	11	3	8.86	0.10	ORD-104411
4339	50397	12	6	25.85	0.15	ORD-104412
4340	50924	19	1	21.71	0.00	ORD-104413
4341	52587	3	1	126.34	0.10	ORD-104414
4342	55749	19	1	21.20	0.10	ORD-104415
4343	52453	12	4	23.81	0.00	ORD-104416
4344	53921	11	5	8.97	0.00	ORD-104417
4345	55505	6	2	93.91	0.00	ORD-104418
4346	51547	18	8	14.94	0.00	ORD-104419
4347	53936	8	1	751.50	0.00	ORD-104420
4348	52279	5	1	87.87	0.00	ORD-104421
4349	52926	9	3	12.10	0.15	ORD-104422
4350	50730	7	1	61.63	0.00	ORD-104423
4351	53566	17	1	438.99	0.00	ORD-104424
4352	53989	16	1	657.96	0.00	ORD-104425
4353	52415	9	2	11.88	0.05	ORD-104426
4354	53566	16	1	647.64	0.10	ORD-104427
4355	51548	20	3	333.03	0.00	ORD-104428
4356	52185	13	1	516.78	0.00	ORD-104429
4357	52280	12	1	24.15	0.00	ORD-104430
4358	53392	4	1	153.52	0.05	ORD-104431
4359	51991	12	4	25.11	0.10	ORD-104432
4360	55147	5	1	86.58	0.05	ORD-104433
4361	53990	5	2	91.43	0.00	ORD-104434
4362	52441	12	3	24.78	0.00	ORD-104435
4363	54652	8	1	730.61	0.05	ORD-104436
4364	51784	20	2	320.83	0.10	ORD-104438
4365	51916	8	1	755.79	0.15	ORD-104439
4366	54943	16	2	656.61	0.00	ORD-104440
4367	51197	11	3	9.15	0.10	ORD-104441
4368	52960	3	1	131.99	0.00	ORD-104442
4369	55353	12	2	24.36	0.00	ORD-104443
4370	53127	4	1	153.71	0.00	ORD-104444
4371	53409	15	2	81.18	0.00	ORD-104445
4372	53552	13	1	540.70	0.00	ORD-104446
4373	55353	1	1	112.32	0.05	ORD-104447
4374	53053	20	1	323.35	0.05	ORD-104448
4375	51917	9	4	12.33	0.05	ORD-104449
4376	52881	7	3	58.44	0.00	ORD-104450
4377	55687	9	2	11.90	0.10	ORD-104451
4378	54044	11	1	9.15	0.00	ORD-104452
4379	54732	18	6	15.40	0.00	ORD-104453
4380	51398	2	1	68.81	0.05	ORD-104454
4381	51218	18	5	15.23	0.10	ORD-104455
4382	54800	15	3	81.37	0.15	ORD-104456
4383	55628	8	1	785.22	0.00	ORD-104457
4384	51296	5	1	87.55	0.00	ORD-104458
4385	55535	1	1	107.72	0.00	ORD-104459
4386	50670	14	1	216.47	0.00	ORD-104460
4387	50057	14	2	205.76	0.00	ORD-104461
4388	55034	11	3	8.78	0.00	ORD-104462
4389	53335	18	5	14.76	0.00	ORD-104463
4390	55354	7	1	60.63	0.10	ORD-104464
4391	55761	13	1	540.88	0.00	ORD-104465
4392	53206	8	1	755.01	0.00	ORD-104466
4393	52046	3	1	136.07	0.05	ORD-104467
4394	50925	6	2	90.99	0.00	ORD-104468
4395	53553	13	2	536.28	0.00	ORD-104469
4396	55113	15	1	77.32	0.00	ORD-104471
4397	50300	15	4	83.31	0.00	ORD-104472
4398	50731	2	4	70.49	0.05	ORD-104473
4399	53991	15	3	80.07	0.10	ORD-104474
4400	53054	18	2	15.03	0.00	ORD-104475
4401	54369	13	3	535.17	0.10	ORD-104476
4402	51685	20	1	334.97	0.10	ORD-104477
4403	55355	19	2	21.25	0.00	ORD-104478
4404	55570	10	1	174.04	0.00	ORD-104479
4405	51604	7	1	61.19	0.00	ORD-104480
4406	51116	18	2	14.28	0.05	ORD-104481
4407	55446	15	1	82.38	0.10	ORD-104482
4408	50732	19	3	22.48	0.10	ORD-104483
4409	55788	4	1	145.38	0.05	ORD-104484
4410	54161	1	1	111.29	0.00	ORD-104485
4411	54102	6	1	97.10	0.00	ORD-104487
4412	53393	12	4	25.04	0.00	ORD-104488
4413	52670	6	1	99.19	0.00	ORD-104489
4414	50762	18	2	14.64	0.00	ORD-104490
4415	50398	4	1	146.95	0.05	ORD-104491
4416	53368	15	1	80.88	0.00	ORD-104492
4417	50671	9	2	12.02	0.00	ORD-104493
4418	53128	7	1	58.95	0.10	ORD-104494
4419	55802	13	1	519.90	0.10	ORD-104495
4420	54456	7	3	57.09	0.05	ORD-104496
4421	50683	9	4	12.43	0.20	ORD-104497
4422	50458	3	1	130.84	0.00	ORD-104498
4423	54351	6	1	92.89	0.00	ORD-104499
4424	54103	11	5	9.42	0.20	ORD-104500
4425	55356	8	2	754.44	0.00	ORD-104501
4426	52927	11	3	8.72	0.00	ORD-104502
4427	52306	6	3	90.43	0.05	ORD-104503
4428	51297	12	3	24.71	0.10	ORD-104504
4429	55356	8	1	776.54	0.05	ORD-104505
4430	50176	7	3	61.83	0.10	ORD-104506
4431	52671	1	2	106.12	0.05	ORD-104507
4432	54494	5	4	93.79	0.00	ORD-104508
4433	50867	10	1	180.74	0.00	ORD-104509
4434	50497	13	2	507.20	0.15	ORD-104510
4435	54569	13	1	521.15	0.00	ORD-104511
4436	52522	17	1	404.82	0.00	ORD-104512
4437	52146	2	2	70.19	0.00	ORD-104513
4438	54309	1	3	110.50	0.00	ORD-104514
4439	55115	4	2	155.65	0.05	ORD-104515
4440	54091	9	2	11.86	0.00	ORD-104516
4441	55789	13	1	522.62	0.10	ORD-104517
4442	55114	2	1	68.54	0.00	ORD-104518
4443	51152	20	1	317.06	0.00	ORD-104519
4444	54834	1	3	110.51	0.05	ORD-104520
4445	54403	11	3	9.22	0.10	ORD-104521
4446	51476	13	2	522.70	0.00	ORD-104522
4447	50355	11	5	8.98	0.00	ORD-104523
4448	53503	13	1	542.85	0.00	ORD-104524
4449	55357	20	1	327.93	0.15	ORD-104525
4450	52477	16	1	655.13	0.10	ORD-104527
4451	54162	10	3	172.07	0.00	ORD-104528
4452	50356	11	4	9.39	0.05	ORD-104529
4453	51970	4	1	143.58	0.20	ORD-104530
4454	51785	11	4	8.57	0.10	ORD-104531
4455	51477	7	2	57.99	0.05	ORD-104532
4456	53055	20	1	330.04	0.00	ORD-104533
4457	55718	18	3	15.12	0.15	ORD-104534
4458	51918	9	1	11.59	0.15	ORD-104535
4459	50778	20	1	332.95	0.20	ORD-104536
4460	50357	6	5	95.00	0.05	ORD-104537
4461	50039	13	1	510.71	0.05	ORD-104538
4462	51792	9	7	11.66	0.05	ORD-104539
4463	54111	13	1	530.46	0.00	ORD-104540
4464	50177	11	5	9.19	0.05	ORD-104541
4465	53207	18	3	15.55	0.15	ORD-104542
4466	53208	4	1	142.83	0.00	ORD-104543
4467	53283	11	4	9.27	0.05	ORD-104544
4468	51549	11	5	9.37	0.00	ORD-104545
4469	50358	16	1	661.90	0.00	ORD-104546
4470	51549	11	4	8.84	0.00	ORD-104547
4471	55688	19	2	23.04	0.00	ORD-104548
4472	54733	8	1	736.64	0.05	ORD-104549
4473	51478	15	3	81.70	0.00	ORD-104551
4474	50178	11	4	8.71	0.05	ORD-104552
4475	55447	15	1	83.07	0.00	ORD-104553
4476	52538	11	5	8.80	0.00	ORD-104554
4477	53777	9	4	12.28	0.05	ORD-104555
4478	51073	10	2	186.57	0.10	ORD-104556
4479	55762	1	3	106.40	0.20	ORD-104557
4480	53410	4	1	147.17	0.00	ORD-104558
4481	50588	14	2	220.40	0.00	ORD-104559
4482	52882	12	3	24.33	0.00	ORD-104560
4483	53284	5	2	93.18	0.15	ORD-104561
4484	51919	11	5	8.56	0.00	ORD-104562
4485	52442	9	1	11.88	0.00	ORD-104563
4486	50179	20	2	329.58	0.05	ORD-104564
4487	52928	9	5	12.48	0.00	ORD-104565
4488	53992	19	3	21.00	0.00	ORD-104566
4489	55689	1	1	106.42	0.00	ORD-104567
4490	51971	13	3	526.35	0.15	ORD-104568
4491	54706	15	2	81.02	0.00	ORD-104569
4492	52613	11	6	8.82	0.10	ORD-104570
4493	54944	6	1	99.32	0.00	ORD-104571
4494	50561	13	1	494.51	0.00	ORD-104572
4495	51074	19	1	21.25	0.00	ORD-104573
4496	50107	18	4	15.06	0.00	ORD-104574
4497	55358	3	1	124.51	0.10	ORD-104575
4498	51075	13	1	524.63	0.20	ORD-104576
4499	50421	18	3	15.42	0.10	ORD-104577
4500	52539	12	4	24.33	0.00	ORD-104578
4501	52770	3	2	130.25	0.15	ORD-104579
4502	52847	5	2	93.50	0.15	ORD-104580
4503	55148	4	2	147.33	0.15	ORD-104581
4504	55719	5	1	86.95	0.05	ORD-104582
4505	52307	11	2	8.79	0.05	ORD-104583
4506	53452	6	1	96.39	0.00	ORD-104584
4507	51298	19	1	21.40	0.20	ORD-104585
4508	55485	1	2	109.99	0.10	ORD-104586
4509	52281	9	3	11.42	0.00	ORD-104587
4510	52047	18	3	14.57	0.00	ORD-104588
4511	55035	12	6	24.70	0.00	ORD-104589
4512	53056	12	6	24.76	0.00	ORD-104590
4513	55359	2	1	73.30	0.05	ORD-104591
4514	51550	2	1	67.63	0.15	ORD-104592
4515	52349	11	3	8.90	0.00	ORD-104593
4516	52961	7	1	60.02	0.10	ORD-104594
4517	52186	19	1	21.87	0.10	ORD-104595
4518	51376	2	2	69.52	0.05	ORD-104596
4519	54059	12	5	24.90	0.10	ORD-104597
4520	50613	3	1	132.64	0.10	ORD-104598
4521	52883	14	3	213.22	0.05	ORD-104599
4522	55116	9	5	12.12	0.10	ORD-104600
4523	53209	19	2	22.96	0.05	ORD-104601
4524	54586	4	1	156.10	0.20	ORD-104602
4525	54603	12	2	24.66	0.05	ORD-104603
4526	55448	14	1	203.95	0.00	ORD-104604
4527	54125	11	4	8.85	0.10	ORD-104605
4528	53623	4	2	149.05	0.05	ORD-104606
4529	54073	7	3	57.07	0.00	ORD-104607
4530	51920	6	3	93.10	0.00	ORD-104608
4531	55361	1	1	111.54	0.20	ORD-104609
4532	54124	14	2	202.06	0.10	ORD-104610
4533	53210	9	9	11.48	0.00	ORD-104611
4534	55763	15	1	83.28	0.05	ORD-104612
4535	55571	6	4	99.03	0.10	ORD-104613
4536	55360	2	2	72.02	0.00	ORD-104614
4537	54801	3	1	123.50	0.10	ORD-104615
4538	51076	14	2	204.66	0.05	ORD-104616
4539	52614	3	1	130.36	0.05	ORD-104617
4540	50926	5	1	85.99	0.05	ORD-104618
4541	50180	16	1	642.47	0.00	ORD-104619
4542	54074	12	4	23.92	0.00	ORD-104620
4543	54228	5	3	86.66	0.10	ORD-104621
4544	52231	11	6	9.41	0.15	ORD-104622
4545	53453	18	7	15.11	0.00	ORD-104623
4546	51786	20	1	334.22	0.05	ORD-104624
4547	55036	15	1	81.01	0.00	ORD-104625
4548	51588	13	1	499.58	0.00	ORD-104626
4549	55363	20	1	323.54	0.10	ORD-104627
4550	55363	19	2	21.78	0.05	ORD-104628
4551	52821	13	1	498.94	0.00	ORD-104629
4552	50684	13	2	526.12	0.05	ORD-104630
4553	55362	4	1	150.46	0.00	ORD-104631
4554	52672	9	4	11.77	0.00	ORD-104632
4555	55364	8	2	747.24	0.20	ORD-104633
4556	55037	20	2	344.47	0.05	ORD-104634
4557	55117	6	1	95.57	0.05	ORD-104635
4558	54945	16	1	660.96	0.15	ORD-104636
4559	50529	19	1	22.56	0.10	ORD-104637
4560	54404	11	4	9.44	0.00	ORD-104638
4561	50589	1	1	104.61	0.05	ORD-104639
4562	53533	16	1	622.56	0.05	ORD-104640
4563	50779	7	3	58.13	0.05	ORD-104641
4564	54272	11	1	9.43	0.10	ORD-104642
4565	52117	13	1	511.82	0.00	ORD-104643
4566	54188	18	3	15.42	0.00	ORD-104644
4567	54197	5	2	91.06	0.05	ORD-104645
4568	54405	10	2	172.03	0.10	ORD-104646
4569	53830	18	3	15.72	0.00	ORD-104647
4570	54523	13	1	509.83	0.00	ORD-104648
4571	51659	12	4	25.24	0.10	ORD-104649
4572	55149	14	1	211.78	0.05	ORD-104650
4573	52097	13	2	508.76	0.05	ORD-104651
4574	53211	11	5	8.59	0.10	ORD-104652
4575	53057	1	1	109.79	0.05	ORD-104653
4576	54707	5	2	85.59	0.00	ORD-104654
4577	50074	13	2	505.20	0.00	ORD-104655
4578	54826	15	2	77.90	0.10	ORD-104656
4579	53454	15	2	81.41	0.00	ORD-104657
4580	53993	5	1	90.32	0.05	ORD-104658
4581	50263	14	1	201.98	0.00	ORD-104659
4582	55720	1	1	109.70	0.00	ORD-104660
4583	54370	11	5	8.79	0.15	ORD-104661
4584	52296	13	1	534.87	0.00	ORD-104662
4585	53336	2	1	72.59	0.05	ORD-104663
4586	54075	9	5	12.41	0.05	ORD-104664
4587	51921	19	2	22.57	0.00	ORD-104665
4588	52379	9	4	12.07	0.00	ORD-104666
4589	50264	20	1	320.89	0.10	ORD-104667
4590	52771	14	1	210.51	0.05	ORD-104668
4591	54535	8	1	734.83	0.15	ORD-104669
4592	54877	11	3	8.85	0.15	ORD-104670
4593	53753	1	3	110.64	0.05	ORD-104671
4594	53559	2	1	69.78	0.05	ORD-104672
4595	55118	9	8	11.71	0.00	ORD-104673
4596	53892	9	3	12.24	0.20	ORD-104674
4597	53905	6	3	91.17	0.05	ORD-104675
4598	55486	14	2	207.43	0.00	ORD-104676
4599	54273	1	1	111.29	0.00	ORD-104677
4600	55118	8	1	778.72	0.05	ORD-104678
4601	50780	5	1	87.88	0.00	ORD-104679
4602	51299	11	3	9.29	0.10	ORD-104680
4603	54755	19	3	21.06	0.00	ORD-104681
4604	54092	11	4	8.57	0.15	ORD-104682
4605	51605	18	3	15.49	0.10	ORD-104683
4606	53337	15	1	83.25	0.10	ORD-104684
4607	50265	4	2	156.67	0.10	ORD-104685
4608	50422	3	1	134.75	0.10	ORD-104686
4609	52380	7	1	57.71	0.15	ORD-104687
4610	50108	6	1	97.89	0.00	ORD-104688
4611	50530	10	1	176.72	0.10	ORD-104689
4612	50210	7	3	60.04	0.10	ORD-104690
4613	51220	13	1	540.02	0.00	ORD-104691
4614	54134	13	2	536.57	0.10	ORD-104692
4615	55629	11	4	9.22	0.00	ORD-104693
4616	54968	2	2	67.36	0.05	ORD-104694
4617	50266	6	1	99.13	0.05	ORD-104695
4618	51219	10	1	183.70	0.00	ORD-104696
4619	50927	8	3	770.72	0.00	ORD-104697
4620	50435	1	2	112.75	0.00	ORD-104698
4621	52929	18	4	14.82	0.00	ORD-104699
4622	52884	15	1	81.47	0.00	ORD-104700
4623	50928	2	1	68.66	0.05	ORD-104701
4624	53893	10	1	171.57	0.15	ORD-104702
4625	50733	9	5	11.46	0.10	ORD-104703
4626	50423	12	1	24.38	0.05	ORD-104704
4627	54371	9	5	11.46	0.00	ORD-104705
4628	51831	6	1	95.68	0.00	ORD-104706
4629	51922	9	4	11.71	0.00	ORD-104707
4630	53338	1	1	113.08	0.15	ORD-104708
4631	51681	16	1	642.83	0.05	ORD-104709
4632	54734	18	5	14.93	0.00	ORD-104710
4633	51670	15	3	80.54	0.00	ORD-104711
4634	51479	5	1	93.92	0.05	ORD-104712
4635	50181	1	1	106.25	0.05	ORD-104713
4636	53477	14	2	204.36	0.00	ORD-104714
4637	52572	18	4	14.92	0.10	ORD-104715
4638	54536	5	2	87.34	0.00	ORD-104716
4639	55365	18	4	14.94	0.00	ORD-104717
4640	52708	9	5	12.30	0.00	ORD-104718
4641	50634	16	1	646.65	0.10	ORD-104719
4642	51203	19	5	22.88	0.10	ORD-104720
4643	53831	4	1	144.13	0.00	ORD-104721
4644	50614	18	6	14.90	0.00	ORD-104722
4645	54484	13	2	505.18	0.05	ORD-104723
4646	52350	15	1	83.82	0.00	ORD-104724
4647	54653	18	3	15.50	0.00	ORD-104725
4648	55119	19	4	21.54	0.05	ORD-104726
4649	52930	7	1	60.52	0.05	ORD-104727
4650	50781	2	3	72.85	0.10	ORD-104728
4651	50075	16	1	631.49	0.00	ORD-104729
4652	51741	11	2	8.77	0.00	ORD-104730
4653	54815	17	1	402.01	0.10	ORD-104731
4654	52673	1	2	113.04	0.10	ORD-104732
4655	52351	18	6	14.80	0.10	ORD-104733
4656	54735	5	1	94.45	0.00	ORD-104734
4657	54310	12	4	25.42	0.00	ORD-104735
4658	50359	11	3	9.09	0.20	ORD-104736
4659	53778	16	1	667.24	0.20	ORD-104737
4660	51480	11	2	8.82	0.00	ORD-104738
4661	53455	18	2	15.34	0.00	ORD-104739
4662	55609	9	4	12.50	0.00	ORD-104740
4663	55770	11	5	9.28	0.00	ORD-104741
4664	50182	13	2	523.64	0.20	ORD-104742
4665	53554	15	3	81.93	0.15	ORD-104743
4666	54352	6	1	90.92	0.00	ORD-104744
4667	51077	8	2	774.10	0.05	ORD-104745
4668	55366	4	2	155.67	0.00	ORD-104746
4669	50040	9	2	11.45	0.05	ORD-104747
4670	55038	19	2	21.81	0.00	ORD-104748
4671	52540	20	1	334.70	0.00	ORD-104749
4672	50868	13	2	544.08	0.00	ORD-104750
4673	52931	9	3	12.10	0.00	ORD-104751
4674	52402	19	4	21.80	0.00	ORD-104752
4675	54274	3	1	132.59	0.05	ORD-104753
4676	55536	3	2	135.34	0.00	ORD-104754
4677	54189	14	2	203.92	0.00	ORD-104755
4678	51707	11	3	9.43	0.00	ORD-104756
4679	55790	20	1	320.24	0.00	ORD-104757
4680	50183	12	3	26.01	0.00	ORD-104758
4681	51923	2	1	69.70	0.05	ORD-104759
4682	51300	1	2	113.87	0.10	ORD-104760
4683	53058	16	1	620.81	0.05	ORD-104761
4684	55367	1	1	114.63	0.10	ORD-104762
4685	54045	4	1	149.34	0.00	ORD-104763
4686	51377	9	9	12.57	0.20	ORD-104764
4687	53832	1	2	105.37	0.15	ORD-104765
4688	55690	12	1	24.95	0.00	ORD-104766
4689	51726	6	3	95.11	0.00	ORD-104767
4690	54692	18	4	15.50	0.05	ORD-104768
4691	50763	18	5	15.62	0.05	ORD-104769
4692	52352	14	2	213.03	0.00	ORD-104770
4693	55160	1	1	112.98	0.00	ORD-104771
4694	52403	4	1	151.44	0.10	ORD-104772
4695	54654	7	4	58.91	0.10	ORD-104773
4696	50360	20	2	315.07	0.15	ORD-104774
4697	50512	9	2	12.43	0.05	ORD-104775
4698	54835	11	4	8.80	0.00	ORD-104776
4699	55368	18	5	14.53	0.10	ORD-104777
4700	50590	12	3	24.30	0.00	ORD-104778
4701	50547	4	2	144.59	0.00	ORD-104779
4702	55672	9	3	11.97	0.00	ORD-104780
4703	51378	8	2	775.58	0.10	ORD-104781
4704	54587	12	4	24.96	0.10	ORD-104782
4705	51992	3	2	124.44	0.00	ORD-104783
4706	51078	3	1	128.10	0.00	ORD-104784
4707	51301	9	4	12.45	0.10	ORD-104785
4708	55369	3	1	123.88	0.00	ORD-104786
4709	50361	13	2	514.23	0.00	ORD-104787
4710	51481	18	3	14.78	0.05	ORD-104788
4711	54878	5	2	94.27	0.00	ORD-104789
4712	53059	11	3	8.64	0.05	ORD-104791
4713	50223	6	2	94.95	0.20	ORD-104792
4714	52353	11	6	9.42	0.00	ORD-104793
4715	50267	4	2	154.01	0.00	ORD-104794
4716	53624	8	2	760.01	0.00	ORD-104795
4717	54693	7	4	62.36	0.00	ORD-104796
4718	55039	2	2	72.24	0.00	ORD-104797
4719	54485	4	1	146.81	0.10	ORD-104798
4720	52048	8	1	763.16	0.00	ORD-104799
4721	54946	17	2	422.82	0.00	ORD-104800
4722	54879	3	1	126.23	0.20	ORD-104801
4723	55040	1	1	106.66	0.15	ORD-104802
4724	51302	1	1	109.74	0.20	ORD-104803
4725	50436	2	1	68.43	0.05	ORD-104804
4726	52232	6	1	92.36	0.00	ORD-104805
4727	51482	5	1	87.03	0.00	ORD-104806
4728	52523	13	2	503.14	0.00	ORD-104807
4729	51711	2	2	70.47	0.00	ORD-104808
4730	52798	6	1	97.52	0.15	ORD-104809
4731	51399	15	1	76.80	0.00	ORD-104810
4732	51379	18	3	15.25	0.00	ORD-104811
4733	53339	18	4	14.74	0.05	ORD-104812
4734	54275	11	6	8.91	0.00	ORD-104813
4735	50734	16	2	648.16	0.05	ORD-104814
4736	54504	20	1	345.31	0.00	ORD-104815
4737	54694	9	3	11.42	0.10	ORD-104816
4738	51303	4	1	150.22	0.15	ORD-104817
4739	51660	20	1	327.11	0.00	ORD-104818
4740	50735	17	1	417.04	0.20	ORD-104819
4741	51483	7	1	62.95	0.00	ORD-104820
4742	55370	4	1	152.13	0.10	ORD-104821
4743	51924	8	1	787.09	0.00	ORD-104822
4744	55371	13	1	518.69	0.15	ORD-104823
4745	54505	8	1	723.78	0.00	ORD-104824
4746	55371	19	1	21.38	0.05	ORD-104825
4747	50184	12	6	24.79	0.05	ORD-104826
4748	55651	7	2	58.87	0.00	ORD-104827
4749	55662	11	3	9.07	0.00	ORD-104828
4750	50362	14	1	215.32	0.00	ORD-104829
4751	53833	3	1	135.96	0.00	ORD-104830
4752	54736	8	1	775.31	0.00	ORD-104831
4753	51400	11	2	8.87	0.10	ORD-104832
4754	51079	9	2	11.95	0.00	ORD-104833
4755	55587	7	1	57.21	0.10	ORD-104834
4756	55041	12	5	24.55	0.00	ORD-104835
4757	50764	2	1	66.67	0.05	ORD-104836
4758	50268	10	1	175.63	0.20	ORD-104838
4759	52187	2	1	66.52	0.10	ORD-104839
4760	55120	9	1	12.39	0.10	ORD-104840
4761	54486	13	1	494.54	0.10	ORD-104841
4762	53994	13	3	533.65	0.10	ORD-104842
4763	54104	11	5	8.99	0.00	ORD-104843
4764	52932	18	4	14.47	0.10	ORD-104844
4765	52118	3	1	132.08	0.00	ORD-104845
4766	52582	19	2	21.18	0.00	ORD-104846
4767	50363	19	1	22.97	0.15	ORD-104847
4768	53534	18	4	15.06	0.00	ORD-104848
4769	54229	1	1	107.71	0.00	ORD-104849
4770	53834	19	1	21.83	0.00	ORD-104850
4771	50224	6	2	99.27	0.10	ORD-104851
4772	51177	20	1	323.34	0.00	ORD-104853
4773	55821	16	1	612.95	0.00	ORD-104854
4774	52124	5	3	93.48	0.00	ORD-104855
4775	54276	12	7	25.42	0.00	ORD-104856
4776	50393	16	1	638.52	0.00	ORD-104857
4777	50364	11	3	9.12	0.00	ORD-104858
4778	55372	2	1	70.80	0.00	ORD-104859
4779	53835	9	3	11.80	0.00	ORD-104860
4780	53504	5	1	88.85	0.00	ORD-104861
4781	55449	1	1	108.00	0.05	ORD-104862
4782	54518	9	5	12.24	0.00	ORD-104863
4783	55373	11	1	8.62	0.10	ORD-104864
4784	50498	5	1	86.54	0.00	ORD-104865
4785	51925	19	2	21.88	0.05	ORD-104867
4786	52822	13	1	530.01	0.05	ORD-104868
4787	54406	1	2	110.42	0.00	ORD-104869
4788	54105	13	2	539.33	0.05	ORD-104870
4789	54880	16	1	623.63	0.00	ORD-104871
4790	54836	15	3	83.79	0.00	ORD-104872
4791	54277	14	1	217.99	0.00	ORD-104873
4792	52282	1	1	111.74	0.05	ORD-104874
4793	50365	11	5	8.64	0.00	ORD-104875
4794	52243	9	4	12.42	0.00	ORD-104876
4795	50591	15	2	78.93	0.00	ORD-104877
4796	51081	7	2	59.85	0.10	ORD-104878
4797	51178	10	1	185.21	0.00	ORD-104879
4798	51080	18	4	14.81	0.00	ORD-104880
4799	54323	18	6	15.00	0.10	ORD-104881
4800	53478	10	1	185.77	0.20	ORD-104882
4801	54230	8	1	732.57	0.10	ORD-104883
4802	55374	9	3	11.69	0.20	ORD-104884
4803	53060	2	1	68.99	0.00	ORD-104885
4804	51727	6	2	96.06	0.20	ORD-104886
4805	52354	17	2	406.33	0.05	ORD-104887
4806	54537	7	2	60.72	0.00	ORD-104888
4807	53212	11	3	8.67	0.20	ORD-104889
4808	51926	11	2	8.94	0.00	ORD-104890
4809	55042	13	2	529.85	0.10	ORD-104891
4810	51606	5	2	86.33	0.15	ORD-104892
4811	51661	14	2	205.67	0.05	ORD-104893
4812	51304	9	1	11.94	0.00	ORD-104894
4813	51993	5	1	87.67	0.00	ORD-104895
4814	53213	19	2	21.04	0.10	ORD-104896
4815	53061	14	2	212.24	0.05	ORD-104897
4816	53214	12	4	24.77	0.20	ORD-104898
4817	53535	1	1	106.83	0.00	ORD-104899
4818	51082	11	4	8.77	0.00	ORD-104900
4819	53215	14	1	200.88	0.00	ORD-104901
4820	53456	11	2	8.66	0.15	ORD-104902
4821	53340	5	2	90.35	0.00	ORD-104903
4822	55630	18	2	15.16	0.20	ORD-104904
4823	55721	9	4	11.98	0.00	ORD-104905
4824	50399	11	4	9.03	0.00	ORD-104906
4825	51083	11	4	9.31	0.00	ORD-104907
4826	51927	8	2	724.10	0.00	ORD-104908
4827	51484	14	1	201.87	0.00	ORD-104909
4828	50765	19	2	21.59	0.10	ORD-104910
4829	51694	5	1	91.08	0.10	ORD-104911
4830	50929	6	3	98.16	0.10	ORD-104912
4831	55375	16	1	665.87	0.00	ORD-104913
4832	52355	11	2	8.96	0.00	ORD-104914
4833	54547	12	1	26.12	0.05	ORD-104915
4834	51928	20	1	332.17	0.15	ORD-104916
4835	53870	13	4	518.00	0.00	ORD-104917
4836	52995	6	3	93.11	0.05	ORD-104918
4837	50736	17	2	409.79	0.05	ORD-104919
4838	50930	14	1	207.03	0.15	ORD-104920
4839	53216	5	1	87.62	0.15	ORD-104921
4840	55376	19	1	21.16	0.10	ORD-104922
4841	54407	4	1	142.95	0.00	ORD-104923
4842	51929	11	3	9.07	0.00	ORD-104924
4843	53922	6	1	91.63	0.00	ORD-104925
4844	51485	14	2	217.27	0.05	ORD-104926
4845	51551	11	7	9.14	0.15	ORD-104927
4846	54311	16	1	627.43	0.00	ORD-104928
4847	50459	6	1	95.03	0.05	ORD-104929
4848	50600	4	1	151.72	0.00	ORD-104930
4849	52283	3	1	131.31	0.00	ORD-104931
4850	55631	5	1	93.59	0.20	ORD-104932
4851	53574	3	3	128.19	0.05	ORD-104933
4852	52188	3	1	135.54	0.20	ORD-104934
4853	51084	7	3	60.59	0.20	ORD-104935
4854	51085	7	1	59.93	0.00	ORD-104936
4855	52996	8	1	768.82	0.10	ORD-104937
4856	51695	9	5	12.08	0.00	ORD-104938
4857	53096	18	4	15.33	0.00	ORD-104939
4858	53217	11	3	9.38	0.00	ORD-104940
4859	55822	1	1	106.72	0.05	ORD-104941
4860	53505	7	3	58.88	0.05	ORD-104942
4861	53906	5	1	92.67	0.10	ORD-104943
4862	50869	8	1	741.33	0.00	ORD-104944
4863	50531	7	3	61.20	0.10	ORD-104945
4864	55043	9	4	12.00	0.00	ORD-104946
4865	50931	13	2	544.22	0.05	ORD-104947
4866	55494	20	1	331.88	0.00	ORD-104948
4867	50269	2	1	68.27	0.00	ORD-104949
4868	55377	7	2	57.66	0.05	ORD-104950
4869	50827	2	2	73.13	0.15	ORD-104951
4870	54231	4	3	153.36	0.00	ORD-104952
4871	53505	4	1	152.04	0.00	ORD-104953
4872	51930	10	1	179.15	0.15	ORD-104954
4873	54947	6	3	92.76	0.00	ORD-104955
4874	53285	15	2	76.19	0.00	ORD-104956
4875	54548	14	1	213.47	0.05	ORD-104957
4876	53106	5	2	92.19	0.10	ORD-104958
4877	55823	7	1	60.92	0.00	ORD-104959
4878	50041	1	2	110.10	0.20	ORD-104960
4879	52029	17	2	406.55	0.00	ORD-104961
4880	51086	8	1	756.78	0.00	ORD-104962
4881	53062	15	3	79.55	0.00	ORD-104963
4882	53107	16	1	662.13	0.05	ORD-104964
4883	53286	19	4	21.72	0.00	ORD-104965
4884	53457	20	2	335.30	0.00	ORD-104966
4885	52356	17	2	400.77	0.05	ORD-104967
4886	52284	6	1	98.05	0.05	ORD-104968
4887	53287	6	2	94.14	0.00	ORD-104969
4888	54232	13	2	527.06	0.15	ORD-104970
4889	55378	10	1	177.56	0.00	ORD-104971
4890	54756	6	1	90.90	0.00	ORD-104972
4891	51087	18	5	14.77	0.15	ORD-104973
4892	50812	11	4	8.93	0.00	ORD-104974
4893	53625	16	1	663.97	0.00	ORD-104975
4894	55121	8	2	778.01	0.00	ORD-104976
4895	55588	12	4	25.75	0.00	ORD-104977
4896	54046	10	1	174.51	0.00	ORD-104978
4897	53218	17	1	431.50	0.20	ORD-104979
4898	50282	17	1	425.05	0.00	ORD-104980
4899	50460	20	1	336.83	0.00	ORD-104981
4900	51814	9	2	12.05	0.10	ORD-104982
4901	54655	10	1	179.35	0.00	ORD-104983
4902	52615	4	2	152.72	0.00	ORD-104984
4903	54656	17	1	433.45	0.10	ORD-104985
4904	53063	12	4	23.88	0.00	ORD-104986
4905	52357	20	2	339.32	0.10	ORD-104987
4906	52285	13	1	508.04	0.15	ORD-104988
4907	50461	9	6	12.45	0.20	ORD-104989
4908	53288	20	2	315.24	0.05	ORD-104990
4909	52030	17	2	407.41	0.10	ORD-104991
4910	55122	3	2	125.79	0.20	ORD-104992
4911	51349	11	1	8.96	0.00	ORD-104993
4912	53697	18	3	15.27	0.00	ORD-104994
4913	51728	18	5	14.75	0.00	ORD-104995
4914	51672	9	2	12.05	0.00	ORD-104996
4915	50932	2	2	71.00	0.05	ORD-104997
4916	51141	6	1	92.18	0.00	ORD-104998
4917	50042	4	2	154.02	0.15	ORD-104999
4918	50042	18	5	14.79	0.00	ORD-105000
4919	50185	15	3	79.23	0.00	ORD-105001
4920	54948	18	2	14.56	0.10	ORD-105002
4921	54408	8	3	718.82	0.00	ORD-105003
4922	50058	16	1	653.32	0.05	ORD-105004
4923	53479	1	1	114.69	0.00	ORD-105005
4924	51088	5	1	93.15	0.00	ORD-105006
4925	52933	9	5	11.90	0.00	ORD-105007
4926	52997	19	2	21.44	0.05	ORD-105008
4927	54495	7	1	61.68	0.00	ORD-105009
4928	51931	12	7	25.22	0.20	ORD-105010
4929	52553	20	1	333.30	0.00	ORD-105011
4930	52616	4	1	148.76	0.00	ORD-105012
4931	53219	12	3	24.31	0.15	ORD-105013
4932	53907	19	1	21.00	0.00	ORD-105014
4933	54881	17	1	399.40	0.00	ORD-105015
4934	52799	10	1	187.63	0.10	ORD-105016
4935	54496	5	1	91.28	0.10	ORD-105017
4936	50601	8	1	781.93	0.10	ORD-105018
4937	51662	6	2	95.37	0.00	ORD-105019
4938	55572	3	1	128.87	0.20	ORD-105020
4939	50562	11	5	8.84	0.00	ORD-105021
4940	50499	16	1	610.58	0.00	ORD-105022
4941	54060	4	1	151.27	0.10	ORD-105023
4942	55044	8	1	744.36	0.10	ORD-105024
4943	53480	16	1	643.10	0.10	ORD-105025
4944	54409	7	1	59.15	0.05	ORD-105026
4945	52358	1	2	111.88	0.10	ORD-105027
4946	50870	20	1	332.37	0.00	ORD-105028
4947	50813	1	1	107.87	0.00	ORD-105029
4948	53995	2	1	69.93	0.15	ORD-105030
4949	53567	6	3	93.88	0.00	ORD-105031
4950	53856	10	1	182.79	0.00	ORD-105032
4951	52715	19	1	21.78	0.05	ORD-105033
4952	53289	18	6	14.59	0.00	ORD-105034
4953	50437	10	3	183.24	0.00	ORD-105035
4954	54737	17	2	419.10	0.00	ORD-105036
4955	50871	5	3	90.60	0.10	ORD-105037
4956	55379	15	3	80.89	0.10	ORD-105038
4957	52098	16	1	651.33	0.05	ORD-105039
4958	52998	9	6	11.78	0.00	ORD-105040
4959	52098	12	7	25.75	0.20	ORD-105041
4960	54278	6	1	97.63	0.00	ORD-105043
4961	53836	19	2	21.80	0.00	ORD-105044
4962	53626	19	3	22.58	0.00	ORD-105045
4963	55824	12	5	25.27	0.00	ORD-105046
4964	50570	15	2	82.56	0.10	ORD-105047
4965	52524	14	2	213.89	0.00	ORD-105048
4966	54657	3	1	133.82	0.00	ORD-105049
4967	52934	11	2	9.17	0.10	ORD-105050
4968	50933	1	1	115.47	0.00	ORD-105051
4969	55652	3	1	132.39	0.00	ORD-105052
4970	50086	1	1	115.19	0.10	ORD-105053
4971	54802	11	3	8.76	0.00	ORD-105054
4972	51552	2	1	71.58	0.00	ORD-105055
4973	53837	2	1	70.30	0.10	ORD-105056
4974	51089	7	1	57.71	0.05	ORD-105057
4975	50592	20	1	338.61	0.05	ORD-105058
4976	52147	8	1	740.45	0.20	ORD-105059
4977	53627	20	1	327.11	0.00	ORD-105060
4978	50366	15	3	81.08	0.05	ORD-105061
4979	50462	20	2	326.55	0.15	ORD-105062
4980	55450	20	1	337.97	0.15	ORD-105063
4981	51607	12	6	26.00	0.05	ORD-105064
4982	55632	6	1	90.96	0.05	ORD-105065
4983	54324	13	1	534.17	0.00	ORD-105066
4984	50283	19	2	21.71	0.00	ORD-105067
4985	51504	13	1	541.51	0.10	ORD-105068
4986	53290	8	2	769.30	0.00	ORD-105069
4987	55380	7	4	57.53	0.10	ORD-105070
4988	54487	9	3	12.22	0.00	ORD-105071
4989	53291	9	2	11.71	0.05	ORD-105072
4990	52731	7	3	62.74	0.00	ORD-105073
4991	54126	7	1	59.44	0.00	ORD-105074
4992	52848	13	1	531.47	0.10	ORD-105075
4993	51221	11	2	8.62	0.05	ORD-105076
4994	50548	15	2	83.94	0.15	ORD-105077
4995	55487	9	4	12.54	0.05	ORD-105078
4996	51090	5	2	88.62	0.10	ORD-105079
4997	54695	6	1	96.04	0.05	ORD-105080
4998	54279	4	2	144.55	0.15	ORD-105081
4999	53838	9	7	11.72	0.10	ORD-105082
5000	55381	12	3	25.96	0.00	ORD-105083
5001	52416	20	2	342.94	0.00	ORD-105084
5002	54280	3	2	125.52	0.05	ORD-105085
5003	51932	6	2	98.61	0.05	ORD-105086
5004	51933	14	1	213.41	0.00	ORD-105087
5005	51589	15	2	83.21	0.15	ORD-105088
5006	54658	4	1	154.23	0.00	ORD-105089
5007	53292	9	6	12.51	0.00	ORD-105090
5008	50186	9	4	12.22	0.00	ORD-105091
5009	52853	3	2	124.61	0.15	ORD-105092
5010	51360	13	1	535.16	0.05	ORD-105093
5011	51339	16	1	631.00	0.15	ORD-105094
5012	52849	18	1	14.55	0.00	ORD-105095
5013	54047	5	2	90.07	0.10	ORD-105096
5014	53064	10	1	177.70	0.00	ORD-105097
5015	54570	11	6	9.26	0.15	ORD-105098
5016	53628	16	1	661.16	0.00	ORD-105099
5017	54457	18	2	14.66	0.00	ORD-105100
5018	53754	12	3	24.88	0.00	ORD-105101
5019	50872	13	1	503.38	0.10	ORD-105102
5020	53394	18	4	14.83	0.00	ORD-105103
5021	53755	10	1	178.57	0.05	ORD-105104
5022	54708	20	1	315.13	0.05	ORD-105105
5023	54538	18	3	15.67	0.15	ORD-105106
5024	52850	9	3	12.30	0.00	ORD-105107
5025	50187	1	2	107.91	0.10	ORD-105108
5026	50513	2	1	67.48	0.05	ORD-105109
5027	51091	1	1	114.28	0.00	ORD-105110
5028	52800	5	1	90.24	0.00	ORD-105111
5029	51553	5	2	92.64	0.15	ORD-105112
5030	52935	13	1	494.05	0.00	ORD-105113
5031	54803	1	2	105.06	0.05	ORD-105114
5032	55045	19	1	21.64	0.10	ORD-105115
5033	54549	14	2	201.13	0.15	ORD-105116
5034	54106	15	1	79.57	0.05	ORD-105117
5035	55488	12	6	24.87	0.20	ORD-105118
5036	51380	16	1	635.93	0.05	ORD-105119
5037	54949	10	2	181.57	0.10	ORD-105120
5038	50367	8	2	725.47	0.05	ORD-105121
5039	50593	15	3	83.56	0.10	ORD-105122
5040	52760	14	1	206.97	0.05	ORD-105123
5041	52772	19	2	21.89	0.05	ORD-105124
5042	52617	20	2	321.51	0.05	ORD-105125
5043	50737	8	2	772.32	0.00	ORD-105126
5044	51554	13	2	502.30	0.00	ORD-105127
5045	53871	12	5	24.12	0.00	ORD-105128
5046	54198	18	3	15.12	0.00	ORD-105129
5047	52745	12	4	24.29	0.00	ORD-105130
5048	52618	16	1	648.29	0.00	ORD-105131
5049	54163	6	3	96.40	0.10	ORD-105132
5050	55691	13	2	509.48	0.05	ORD-105133
5051	51934	14	2	216.86	0.00	ORD-105134
5052	55383	19	1	20.97	0.00	ORD-105135
5053	50270	5	2	93.72	0.15	ORD-105136
5054	51179	20	2	334.97	0.00	ORD-105137
5055	55382	13	1	504.06	0.00	ORD-105138
5056	50873	19	1	20.97	0.15	ORD-105139
5057	50043	9	3	12.18	0.00	ORD-105140
5058	50368	18	5	14.45	0.10	ORD-105141
5059	51305	20	2	335.18	0.10	ORD-105142
5060	51307	20	1	331.37	0.00	ORD-105143
5061	55161	7	2	58.85	0.10	ORD-105144
5062	54827	15	2	79.75	0.00	ORD-105145
5063	55692	9	6	11.47	0.00	ORD-105146
5064	53536	7	1	57.09	0.00	ORD-105147
5065	50500	12	5	25.14	0.00	ORD-105148
5066	50271	9	5	12.27	0.00	ORD-105149
5067	51486	2	3	69.37	0.10	ORD-105150
5068	53220	8	2	777.27	0.00	ORD-105151
5069	51306	20	2	342.98	0.00	ORD-105152
5070	55384	12	1	25.01	0.00	ORD-105153
5071	54696	5	2	89.28	0.10	ORD-105154
5072	53120	14	1	210.47	0.10	ORD-105155
5073	52619	12	2	24.86	0.00	ORD-105156
5074	54076	1	1	104.82	0.20	ORD-105157
5075	55385	17	2	414.24	0.00	ORD-105158
5076	52286	1	1	108.80	0.00	ORD-105159
5077	54233	3	1	128.66	0.00	ORD-105160
5078	51555	18	4	15.04	0.00	ORD-105161
5079	54588	11	2	8.69	0.15	ORD-105162
5080	53996	20	1	336.39	0.05	ORD-105163
5081	51350	9	5	12.07	0.00	ORD-105164
5082	53341	6	2	98.96	0.15	ORD-105165
5083	53857	1	1	113.01	0.00	ORD-105167
5084	51935	17	1	439.58	0.15	ORD-105168
5085	52189	2	1	67.19	0.00	ORD-105169
5086	52761	9	4	11.82	0.10	ORD-105170
5087	52709	2	2	66.74	0.00	ORD-105171
5088	55673	19	1	21.94	0.15	ORD-105173
5089	53839	15	2	77.67	0.00	ORD-105174
5090	52148	17	1	406.79	0.00	ORD-105175
5091	51198	12	6	24.06	0.00	ORD-105176
5092	51556	8	1	721.01	0.00	ORD-105177
5093	52674	20	1	342.82	0.20	ORD-105178
5094	55506	14	1	213.42	0.10	ORD-105179
5095	54882	18	3	14.65	0.00	ORD-105180
5096	52478	19	2	22.82	0.15	ORD-105181
5097	52321	11	4	9.03	0.00	ORD-105182
5098	50044	9	3	11.94	0.00	ORD-105183
5099	50369	19	5	21.92	0.00	ORD-105184
5100	52936	1	5	113.92	0.05	ORD-105185
5101	51381	6	4	94.27	0.00	ORD-105186
5102	55386	18	4	14.77	0.00	ORD-105187
5103	51487	15	1	78.00	0.15	ORD-105188
5104	54061	12	1	24.20	0.00	ORD-105189
5105	55386	18	4	15.38	0.05	ORD-105190
5106	53293	14	1	200.36	0.15	ORD-105191
5107	52190	18	4	14.28	0.00	ORD-105192
5108	52422	9	8	12.60	0.05	ORD-105193
5109	52675	5	1	89.91	0.00	ORD-105194
5110	53997	19	2	22.82	0.00	ORD-105195
5111	50934	9	4	12.55	0.20	ORD-105196
5112	54816	7	2	62.98	0.00	ORD-105197
5113	53629	20	1	346.08	0.00	ORD-105198
5114	52525	4	1	155.49	0.10	ORD-105199
5115	54112	19	2	21.95	0.00	ORD-105200
5116	55387	7	2	62.80	0.00	ORD-105201
5117	52049	11	2	9.03	0.05	ORD-105202
5118	50935	4	1	150.35	0.00	ORD-105203
5119	51936	15	1	79.87	0.10	ORD-105204
5120	52443	10	1	181.35	0.00	ORD-105205
5121	55388	19	2	21.39	0.00	ORD-105206
5122	53537	19	2	21.55	0.00	ORD-105207
5123	50424	10	1	177.25	0.20	ORD-105208
5124	52885	5	1	92.84	0.05	ORD-105209
5125	51557	2	1	67.28	0.05	ORD-105210
5126	51199	10	1	183.96	0.00	ORD-105211
5127	54738	5	1	86.93	0.05	ORD-105212
5128	52946	4	1	147.51	0.00	ORD-105213
5129	51488	9	4	12.10	0.05	ORD-105214
5130	53097	6	3	94.42	0.10	ORD-105215
5131	54571	2	1	71.78	0.05	ORD-105216
5132	51558	6	2	91.96	0.05	ORD-105217
5133	54093	4	1	152.03	0.00	ORD-105218
5134	52322	12	4	25.35	0.00	ORD-105219
5135	53698	6	3	93.65	0.00	ORD-105220
5136	53555	16	1	657.63	0.05	ORD-105221
5137	50594	15	4	83.95	0.00	ORD-105222
5138	55389	10	1	186.52	0.20	ORD-105223
5139	53133	2	2	68.44	0.00	ORD-105224
5140	54883	18	2	15.52	0.15	ORD-105225
5141	55123	18	2	14.48	0.15	ORD-105226
5142	52359	2	3	69.70	0.00	ORD-105227
5143	52801	16	1	663.00	0.00	ORD-105228
5144	54841	6	1	90.82	0.00	ORD-105229
5145	53098	6	2	95.32	0.15	ORD-105230
5146	52444	3	2	128.67	0.00	ORD-105231
5147	51308	9	3	12.36	0.05	ORD-105232
5148	55390	15	3	81.12	0.15	ORD-105233
5149	51092	18	4	15.51	0.00	ORD-105234
5150	54804	2	2	71.61	0.10	ORD-105235
5151	52947	7	1	59.43	0.00	ORD-105236
5152	53411	14	1	216.37	0.10	ORD-105237
5153	53630	12	6	24.47	0.05	ORD-105238
5154	51093	13	1	513.40	0.00	ORD-105239
5155	53699	9	4	11.83	0.00	ORD-105240
5156	51559	12	5	25.76	0.00	ORD-105241
5157	55764	5	1	86.36	0.10	ORD-105242
5158	51937	8	3	775.10	0.15	ORD-105243
5159	52031	9	6	12.30	0.20	ORD-105244
5160	53998	3	1	124.52	0.10	ORD-105245
5161	51590	10	1	179.16	0.00	ORD-105246
5162	52541	7	1	57.47	0.15	ORD-105247
5163	50501	18	4	14.54	0.00	ORD-105248
5164	52479	18	5	14.52	0.15	ORD-105249
5165	54372	9	4	11.72	0.05	ORD-105250
5166	51574	6	3	92.83	0.10	ORD-105252
5167	52454	14	1	220.16	0.00	ORD-105253
5168	50635	12	3	25.46	0.15	ORD-105254
5169	53556	2	3	70.17	0.00	ORD-105255
5170	54281	10	1	172.44	0.00	ORD-105256
5171	55573	15	3	82.76	0.10	ORD-105257
5172	54604	17	1	409.06	0.00	ORD-105258
5173	55391	6	2	97.89	0.00	ORD-105259
5174	55791	10	2	186.73	0.00	ORD-105260
5175	53894	8	2	740.83	0.20	ORD-105261
5176	52125	16	2	628.02	0.00	ORD-105262
5177	52823	6	2	97.29	0.05	ORD-105263
5178	52620	17	1	420.95	0.00	ORD-105264
5179	52360	14	2	202.52	0.05	ORD-105265
5180	53065	14	1	203.81	0.00	ORD-105266
5181	54282	18	6	15.32	0.05	ORD-105267
5182	54697	3	3	127.86	0.00	ORD-105268
5183	54234	3	2	129.29	0.05	ORD-105269
5184	55392	6	2	96.51	0.00	ORD-105270
5185	55393	17	1	414.73	0.20	ORD-105271
5186	53700	20	1	330.87	0.15	ORD-105272
5187	50615	18	3	14.99	0.00	ORD-105273
5188	52191	4	2	153.81	0.10	ORD-105274
5189	55124	9	4	12.00	0.15	ORD-105275
5190	55125	13	1	527.91	0.05	ORD-105276
5191	55393	18	4	14.74	0.00	ORD-105277
5192	53858	3	2	126.26	0.00	ORD-105278
5193	53506	3	1	123.78	0.05	ORD-105279
5194	50936	11	7	8.73	0.05	ORD-105280
5195	50301	11	5	9.41	0.00	ORD-105281
5196	54684	15	1	77.66	0.05	ORD-105282
5197	52500	16	2	617.90	0.00	ORD-105283
5198	53875	15	1	82.69	0.10	ORD-105284
5199	53631	11	2	8.71	0.15	ORD-105285
5200	50076	15	1	76.36	0.10	ORD-105286
5201	53221	13	1	511.53	0.00	ORD-105287
5202	53756	15	1	76.59	0.20	ORD-105288
5203	53506	10	2	178.57	0.00	ORD-105289
5204	52937	12	3	25.15	0.10	ORD-105290
5205	52962	6	1	92.35	0.00	ORD-105291
5206	51094	18	8	15.40	0.05	ORD-105292
5207	51938	11	3	8.66	0.10	ORD-105293
5208	52573	19	2	22.99	0.05	ORD-105294
5209	55451	18	2	14.91	0.00	ORD-105295
5210	55765	14	1	202.24	0.10	ORD-105296
5211	52208	16	2	642.97	0.00	ORD-105297
5212	54235	18	3	14.90	0.00	ORD-105298
5213	53294	7	1	61.68	0.00	ORD-105299
5214	50738	7	4	57.70	0.20	ORD-105300
5215	55394	20	2	343.43	0.00	ORD-105301
5216	54184	12	3	25.44	0.15	ORD-105302
5217	50937	10	1	174.36	0.00	ORD-105303
5218	52032	9	4	12.34	0.00	ORD-105304
5219	52746	1	2	109.52	0.00	ORD-105305
5220	50616	20	1	319.48	0.00	ORD-105306
5221	50188	15	2	80.59	0.00	ORD-105307
5222	53701	6	1	92.18	0.00	ORD-105308
5223	54331	19	3	21.78	0.00	ORD-105309
5224	54572	16	1	652.45	0.00	ORD-105310
5225	55633	20	2	334.73	0.05	ORD-105311
5226	52209	20	1	327.24	0.05	ORD-105312
5227	54185	2	2	71.43	0.15	ORD-105313
5228	53757	5	1	94.21	0.00	ORD-105314
5229	53458	6	1	91.57	0.00	ORD-105315
5230	52526	5	2	87.15	0.10	ORD-105316
5231	50563	14	3	205.26	0.05	ORD-105317
5232	55537	6	1	96.28	0.00	ORD-105318
5233	52149	15	1	76.16	0.00	ORD-105319
5234	53632	18	3	15.27	0.20	ORD-105320
5235	55395	15	1	79.82	0.10	ORD-105321
5236	55552	18	2	15.28	0.10	ORD-105322
5237	53702	17	1	439.30	0.05	ORD-105323
5238	53999	18	2	14.57	0.10	ORD-105324
5239	52192	4	1	145.60	0.05	ORD-105325
5240	55396	15	2	82.81	0.05	ORD-105326
5241	52005	16	1	652.63	0.00	ORD-105327
5242	50211	20	1	344.52	0.00	ORD-105328
5243	54199	14	2	201.46	0.00	ORD-105329
5244	50782	2	2	69.87	0.10	ORD-105330
5245	55610	13	1	529.49	0.15	ORD-105331
5246	50302	15	2	78.74	0.00	ORD-105332
5247	55538	18	6	15.05	0.05	ORD-105333
5248	54660	13	2	523.09	0.00	ORD-105334
5249	52676	18	4	15.62	0.10	ORD-105335
5250	54659	14	2	217.88	0.05	ORD-105336
5251	54077	11	6	8.58	0.00	ORD-105337
5252	53507	10	4	185.14	0.10	ORD-105339
5253	51663	2	3	71.32	0.00	ORD-105340
5254	53633	19	1	21.90	0.00	ORD-105341
5255	52455	5	1	92.61	0.00	ORD-105342
5256	53342	9	3	11.77	0.05	ORD-105343
5257	51939	8	2	740.40	0.15	ORD-105344
5258	52423	6	2	95.80	0.00	ORD-105345
5259	53222	14	2	212.80	0.00	ORD-105346
5260	51382	10	1	188.31	0.05	ORD-105347
5261	54000	5	2	90.29	0.10	ORD-105348
5262	53223	20	1	317.94	0.00	ORD-105349
5263	50370	4	2	146.14	0.10	ORD-105350
5264	54113	19	1	22.32	0.10	ORD-105351
5265	53703	12	3	25.18	0.10	ORD-105352
5266	51309	11	5	8.92	0.00	ORD-105353
5267	51729	15	1	81.13	0.10	ORD-105354
5268	50516	13	1	531.76	0.05	ORD-105355
5269	51671	9	4	11.72	0.00	ORD-105356
5270	50884	8	1	724.65	0.05	ORD-105357
5271	52194	8	1	779.17	0.15	ORD-105358
5272	54471	1	1	112.08	0.10	ORD-105359
5273	52938	7	3	59.20	0.00	ORD-105360
5274	50502	6	2	98.51	0.00	ORD-105361
5275	54353	11	4	8.98	0.00	ORD-105362
5276	52574	13	2	527.31	0.20	ORD-105363
5277	52193	11	3	9.32	0.00	ORD-105364
5278	51730	10	1	172.08	0.05	ORD-105365
5279	50045	7	1	61.28	0.00	ORD-105366
5280	53840	16	1	671.49	0.10	ORD-105367
5281	51793	17	2	431.55	0.05	ORD-105368
5282	50189	4	1	150.05	0.00	ORD-105369
5283	55397	1	1	106.91	0.00	ORD-105370
5284	55634	2	2	66.52	0.00	ORD-105371
5285	54001	18	6	15.25	0.00	ORD-105372
5286	51832	6	1	97.38	0.15	ORD-105373
5287	54002	17	1	426.71	0.00	ORD-105374
5288	54661	2	3	69.30	0.00	ORD-105375
5289	52747	10	1	177.27	0.10	ORD-105376
5290	52361	12	3	24.05	0.00	ORD-105377
5291	52773	10	1	183.27	0.10	ORD-105378
5292	55750	16	1	621.39	0.05	ORD-105379
5293	51560	10	1	181.19	0.00	ORD-105381
5294	50685	7	2	60.06	0.05	ORD-105382
5295	51972	1	1	109.81	0.05	ORD-105383
5296	51383	5	1	92.94	0.00	ORD-105384
5297	50595	16	1	671.53	0.00	ORD-105385
5298	52099	3	1	130.99	0.00	ORD-105386
5299	55398	2	1	68.82	0.00	ORD-105387
5300	55452	7	1	58.73	0.10	ORD-105388
5301	51940	7	5	60.29	0.00	ORD-105389
5302	53842	3	2	135.02	0.10	ORD-105390
5303	54950	6	3	98.27	0.05	ORD-105391
5304	50739	3	1	126.94	0.00	ORD-105392
5305	55751	1	1	107.91	0.00	ORD-105393
5306	50272	4	1	144.53	0.00	ORD-105394
5307	52107	9	4	12.12	0.00	ORD-105395
5308	53841	8	2	712.55	0.00	ORD-105396
5309	53481	14	2	217.29	0.00	ORD-105397
5310	55398	9	6	12.40	0.00	ORD-105398
5311	52716	15	2	79.49	0.00	ORD-105399
5312	50425	10	1	183.54	0.05	ORD-105400
5313	52621	19	4	22.61	0.05	ORD-105401
5314	50672	13	1	509.57	0.10	ORD-105402
5315	51561	4	3	147.33	0.10	ORD-105403
5316	51310	8	2	769.62	0.00	ORD-105404
5317	52677	8	3	765.37	0.00	ORD-105405
5318	51664	18	2	14.36	0.00	ORD-105406
5319	50617	20	2	336.93	0.00	ORD-105407
5320	53066	18	1	14.26	0.00	ORD-105408
5321	54236	13	1	501.68	0.20	ORD-105409
5322	54003	11	8	9.35	0.05	ORD-105410
5323	51153	15	1	82.38	0.00	ORD-105411
5324	52999	4	1	152.64	0.00	ORD-105412
5325	50688	6	2	95.79	0.15	ORD-105413
5326	55803	18	2	14.43	0.05	ORD-105414
5327	51562	20	1	337.86	0.10	ORD-105415
5328	51686	4	1	150.25	0.00	ORD-105416
5329	50938	11	3	9.32	0.05	ORD-105417
5330	53067	8	2	727.81	0.15	ORD-105418
5331	50394	19	1	22.26	0.00	ORD-105419
5332	51563	12	5	25.59	0.05	ORD-105420
5333	52678	5	1	88.36	0.00	ORD-105421
5334	53343	19	2	22.27	0.00	ORD-105422
5335	51731	11	5	8.72	0.05	ORD-105423
5336	55653	3	1	132.56	0.10	ORD-105424
5337	53859	2	1	67.25	0.00	ORD-105425
5338	52678	11	3	8.87	0.15	ORD-105426
5339	51787	13	1	525.28	0.00	ORD-105427
5340	53634	20	2	328.25	0.05	ORD-105428
5341	54325	14	1	217.74	0.05	ORD-105429
5342	53068	15	2	78.98	0.10	ORD-105430
5343	51994	5	2	90.86	0.00	ORD-105431
5344	53895	3	1	135.57	0.00	ORD-105432
5345	50273	5	2	92.18	0.05	ORD-105433
5346	51095	11	3	9.29	0.00	ORD-105434
5347	53069	18	4	15.14	0.00	ORD-105435
5348	54312	5	2	94.20	0.15	ORD-105436
5349	52404	2	1	73.07	0.00	ORD-105437
5350	52033	20	2	320.08	0.05	ORD-105438
5351	51311	10	2	182.46	0.15	ORD-105439
5352	50190	18	5	15.69	0.00	ORD-105440
5353	55804	9	4	11.90	0.00	ORD-105441
5354	54062	2	1	66.86	0.20	ORD-105442
5355	51096	10	1	181.14	0.15	ORD-105443
5356	55495	7	3	57.69	0.05	ORD-105444
5357	52679	18	5	14.75	0.00	ORD-105445
5358	55150	8	2	761.78	0.00	ORD-105446
5359	53779	11	3	9.21	0.00	ORD-105447
5360	53129	12	7	23.87	0.00	ORD-105448
5361	51384	10	1	178.00	0.00	ORD-105449
5362	51361	2	2	68.93	0.00	ORD-105450
5363	50371	9	3	12.41	0.15	ORD-105451
5364	54951	4	2	153.71	0.05	ORD-105452
5365	54951	9	3	11.55	0.00	ORD-105453
5366	54462	12	1	25.61	0.00	ORD-105454
5367	51973	3	2	128.91	0.05	ORD-105455
5368	54094	2	4	66.80	0.20	ORD-105456
5369	52195	9	2	12.14	0.00	ORD-105457
5370	52680	6	2	97.46	0.20	ORD-105458
5371	51941	20	3	324.08	0.05	ORD-105459
5372	53780	18	5	14.39	0.00	ORD-105460
5373	52802	20	2	346.41	0.05	ORD-105461
5374	50741	12	5	25.69	0.05	ORD-105462
5375	50740	5	2	86.33	0.05	ORD-105463
5376	51312	4	2	145.98	0.10	ORD-105464
5377	52100	10	1	183.60	0.00	ORD-105465
5378	52886	5	1	87.20	0.10	ORD-105466
5379	54444	19	1	21.53	0.15	ORD-105467
5380	54506	5	2	89.87	0.05	ORD-105468
5381	52533	12	5	24.27	0.00	ORD-105469
5382	53369	10	2	186.16	0.05	ORD-105470
5383	55792	8	1	760.45	0.00	ORD-105471
5384	55399	11	6	8.71	0.00	ORD-105472
5385	52223	12	4	26.18	0.10	ORD-105473
5386	50874	8	2	721.62	0.00	ORD-105474
5387	52575	10	3	188.61	0.05	ORD-105475
5388	52501	19	4	22.03	0.05	ORD-105476
5389	52939	14	3	213.68	0.05	ORD-105477
5390	51564	10	1	174.72	0.00	ORD-105478
5391	53704	13	1	496.15	0.10	ORD-105479
5392	51313	3	1	124.41	0.05	ORD-105480
5393	55046	13	1	522.99	0.00	ORD-105481
5394	52940	18	5	14.87	0.05	ORD-105482
5395	51942	6	1	98.18	0.20	ORD-105483
5396	53000	14	2	215.69	0.15	ORD-105484
5397	53758	2	2	67.17	0.20	ORD-105485
5398	51942	9	5	12.36	0.00	ORD-105486
5399	50783	4	1	143.25	0.05	ORD-105487
5400	52732	12	4	24.11	0.15	ORD-105488
5401	50463	2	2	70.16	0.00	ORD-105489
5402	53635	19	4	21.18	0.10	ORD-105490
5403	53759	5	2	92.54	0.10	ORD-105491
5404	54828	1	1	108.35	0.00	ORD-105492
5405	55654	3	2	123.65	0.20	ORD-105493
5406	50689	18	6	15.28	0.00	ORD-105494
5407	54952	12	5	23.84	0.00	ORD-105495
5408	52480	15	4	81.81	0.00	ORD-105496
5409	55674	4	1	156.63	0.00	ORD-105497
5410	53636	16	1	668.67	0.00	ORD-105498
5411	50303	4	1	149.93	0.10	ORD-105499
5412	50372	17	2	440.44	0.00	ORD-105500
5413	53344	1	1	110.73	0.10	ORD-105501
5414	52101	11	5	9.32	0.10	ORD-105502
5415	55825	11	4	9.09	0.00	ORD-105503
5416	54539	18	3	15.17	0.20	ORD-105504
5417	54338	3	1	127.98	0.00	ORD-105505
5418	51340	9	2	11.41	0.10	ORD-105506
5419	51098	8	1	769.62	0.00	ORD-105507
5420	51565	8	1	782.46	0.10	ORD-105508
5421	51794	10	1	178.17	0.15	ORD-105509
5422	51943	3	1	129.54	0.05	ORD-105510
5423	54107	1	2	105.38	0.00	ORD-105511
5424	54805	19	2	22.74	0.00	ORD-105512
5425	52588	12	3	23.83	0.00	ORD-105513
5426	50201	11	3	8.83	0.05	ORD-105514
5427	55539	6	4	96.80	0.00	ORD-105515
5428	55793	1	1	111.19	0.00	ORD-105516
5429	55693	11	6	8.71	0.00	ORD-105517
5430	50503	10	1	174.18	0.00	ORD-105518
5431	55047	1	1	109.90	0.00	ORD-105519
5432	52196	14	2	209.20	0.00	ORD-105520
5433	53130	9	1	11.43	0.10	ORD-105521
5434	54668	18	5	15.05	0.00	ORD-105522
5435	51097	13	2	541.15	0.10	ORD-105523
5436	50087	5	4	87.95	0.20	ORD-105525
5437	51099	8	2	751.35	0.00	ORD-105526
5438	50274	13	2	506.44	0.00	ORD-105527
5439	50284	15	1	82.30	0.00	ORD-105528
5440	54135	6	2	96.05	0.20	ORD-105529
5441	51142	15	1	76.98	0.10	ORD-105530
5442	55794	11	5	9.01	0.05	ORD-105531
5443	50828	15	3	82.35	0.05	ORD-105532
5444	52851	7	2	62.75	0.00	ORD-105533
5445	52887	6	3	99.14	0.00	ORD-105534
5446	53637	7	2	61.71	0.15	ORD-105535
5447	52481	9	6	11.88	0.20	ORD-105536
5448	54605	17	1	418.96	0.10	ORD-105537
5449	51566	9	3	11.53	0.00	ORD-105538
5450	55400	17	1	422.03	0.15	ORD-105539
5451	50564	18	1	15.21	0.10	ORD-105540
5452	52502	9	6	12.60	0.10	ORD-105541
5453	50191	13	1	542.98	0.00	ORD-105542
5454	52527	12	1	25.58	0.05	ORD-105543
5455	54739	13	1	508.37	0.10	ORD-105544
5456	55400	20	3	323.09	0.15	ORD-105545
5457	53295	9	6	12.39	0.20	ORD-105546
5458	51314	10	1	180.59	0.05	ORD-105547
5459	50275	12	2	24.12	0.00	ORD-105548
5460	51385	10	1	182.88	0.00	ORD-105549
5461	54472	8	1	760.51	0.05	ORD-105550
5462	52824	2	2	68.71	0.00	ORD-105551
5463	54806	18	3	14.32	0.00	ORD-105552
5464	50276	11	3	9.03	0.10	ORD-105553
5465	55611	16	1	650.09	0.10	ORD-105554
5466	54740	12	6	25.28	0.00	ORD-105555
5467	50504	15	2	82.08	0.05	ORD-105556
5468	51315	2	2	70.26	0.20	ORD-105557
5469	52576	18	8	14.96	0.00	ORD-105558
5470	54807	9	4	11.65	0.05	ORD-105559
5471	53760	12	5	24.57	0.05	ORD-105560
5472	51665	19	2	22.97	0.00	ORD-105561
5473	54709	19	1	21.01	0.20	ORD-105562
5474	53843	3	1	135.30	0.00	ORD-105563
5475	54048	20	1	341.00	0.10	ORD-105564
5476	54698	3	1	131.25	0.00	ORD-105565
5477	53224	7	4	58.84	0.00	ORD-105566
5478	55401	10	1	172.14	0.05	ORD-105567
5479	50789	19	2	21.33	0.00	ORD-105568
5480	55402	18	2	15.43	0.10	ORD-105569
5481	55540	17	2	430.14	0.15	ORD-105570
5482	51995	11	4	9.39	0.00	ORD-105571
5483	55403	2	2	68.99	0.00	ORD-105572
5484	51180	10	2	185.74	0.00	ORD-105573
5485	55404	1	1	111.47	0.00	ORD-105574
5486	50939	17	1	416.95	0.00	ORD-105575
5487	53908	1	2	108.04	0.05	ORD-105576
5488	53705	8	1	769.39	0.00	ORD-105577
5489	51489	6	2	94.74	0.00	ORD-105578
5490	51591	6	1	94.82	0.20	ORD-105579
5491	51222	13	2	538.18	0.00	ORD-105580
5492	52854	15	2	77.89	0.05	ORD-105581
5493	55048	13	2	523.80	0.10	ORD-105582
5494	54237	16	1	653.71	0.00	ORD-105583
5495	53706	14	1	201.05	0.00	ORD-105584
5496	53370	19	3	22.84	0.10	ORD-105585
5497	50192	5	2	89.13	0.00	ORD-105586
5498	52681	2	1	68.39	0.10	ORD-105587
5499	50439	19	3	21.18	0.15	ORD-105588
5500	50277	1	1	109.95	0.00	ORD-105589
5501	50193	5	3	88.63	0.05	ORD-105590
5502	53761	4	2	149.42	0.20	ORD-105591
5503	54842	9	3	12.10	0.15	ORD-105592
5504	50438	9	4	12.50	0.00	ORD-105593
5505	55453	14	2	210.02	0.15	ORD-105594
5506	50940	2	2	71.50	0.10	ORD-105595
5507	52622	8	2	747.00	0.00	ORD-105596
5508	55722	12	1	24.13	0.00	ORD-105597
5509	53762	5	2	91.81	0.00	ORD-105598
5510	52405	13	2	512.31	0.00	ORD-105599
5511	54884	4	1	144.87	0.20	ORD-105600
5512	53482	8	2	721.82	0.00	ORD-105601
5513	50941	9	4	12.23	0.20	ORD-105602
5514	55405	9	4	12.13	0.00	ORD-105603
5515	51739	11	6	8.92	0.20	ORD-105604
5516	50875	18	6	15.11	0.00	ORD-105605
5517	51708	4	1	144.38	0.00	ORD-105606
5518	54741	15	2	78.01	0.00	ORD-105607
5519	54410	17	1	439.30	0.00	ORD-105608
5520	54004	15	3	83.79	0.10	ORD-105609
5521	50532	13	1	541.20	0.10	ORD-105610
5522	53345	19	1	20.90	0.00	ORD-105611
5523	50278	7	1	59.10	0.00	ORD-105612
5524	50373	6	4	97.70	0.00	ORD-105613
5525	52362	18	5	15.50	0.10	ORD-105614
5526	52888	12	4	24.02	0.00	ORD-105615
5527	50109	18	3	15.19	0.10	ORD-105616
5528	51316	12	5	23.87	0.20	ORD-105617
5529	53860	12	3	25.59	0.00	ORD-105618
5530	50876	9	4	12.58	0.10	ORD-105619
5531	53070	8	1	733.60	0.10	ORD-105620
5532	50464	4	2	147.82	0.00	ORD-105621
5533	51944	8	2	736.73	0.00	ORD-105622
5534	54005	7	4	61.22	0.05	ORD-105623
5535	55406	18	4	15.45	0.10	ORD-105624
5536	55406	19	1	21.99	0.00	ORD-105625
5537	51815	1	1	106.17	0.00	ORD-105626
5538	51567	7	3	59.37	0.00	ORD-105627
5539	52633	7	1	57.05	0.00	ORD-105628
5540	51100	5	2	91.22	0.10	ORD-105629
5541	51945	18	2	15.68	0.10	ORD-105630
5542	52006	19	1	21.50	0.05	ORD-105631
5543	52577	13	2	526.59	0.00	ORD-105632
5544	54953	12	7	25.06	0.00	ORD-105633
5545	51100	12	6	24.02	0.00	ORD-105634
5546	52482	7	1	57.31	0.05	ORD-105635
5547	51317	10	1	181.07	0.10	ORD-105636
5548	53071	14	1	206.50	0.00	ORD-105637
5549	51740	9	6	12.01	0.10	ORD-105638
5550	52503	9	6	11.50	0.00	ORD-105639
5551	51624	18	6	15.56	0.05	ORD-105640
5552	53296	4	1	155.89	0.00	ORD-105641
5553	53072	2	1	72.37	0.00	ORD-105642
5554	52578	12	5	24.33	0.20	ORD-105643
5555	51200	15	1	80.16	0.20	ORD-105644
5556	52210	19	3	22.14	0.00	ORD-105645
5557	55407	17	1	424.79	0.10	ORD-105646
5558	55723	2	1	68.83	0.05	ORD-105647
5559	51401	13	1	528.76	0.05	ORD-105648
5560	55126	18	1	15.07	0.00	ORD-105649
5561	53073	15	2	79.61	0.05	ORD-105650
5562	51101	11	6	8.88	0.05	ORD-105651
5563	54283	1	2	112.22	0.05	ORD-105652
5564	52197	4	1	146.78	0.00	ORD-105653
5565	51102	12	2	25.08	0.05	ORD-105654
5566	54954	11	3	9.03	0.00	ORD-105655
5567	52198	2	1	73.21	0.00	ORD-105656
5568	54238	12	4	25.45	0.10	ORD-105657
5569	53297	15	1	82.50	0.00	ORD-105658
5570	54114	11	2	8.94	0.00	ORD-105659
5571	54127	1	1	114.20	0.15	ORD-105660
5572	54238	4	1	153.47	0.10	ORD-105661
5573	54662	8	2	779.32	0.00	ORD-105662
5574	54411	5	1	86.06	0.00	ORD-105663
5575	52528	2	1	70.15	0.00	ORD-105664
5576	55589	1	1	108.52	0.05	ORD-105665
5577	53483	9	10	12.03	0.05	ORD-105666
5578	55408	10	1	183.08	0.05	ORD-105667
5579	54128	7	2	57.80	0.00	ORD-105668
5580	53459	7	2	60.21	0.00	ORD-105669
5581	52483	18	1	15.04	0.15	ORD-105670
5582	51402	20	2	324.74	0.00	ORD-105671
5583	54519	1	1	113.06	0.05	ORD-105672
5584	53844	19	2	21.40	0.00	ORD-105673
5585	51318	10	1	173.90	0.10	ORD-105674
5586	53781	18	4	14.40	0.10	ORD-105675
5587	54809	11	5	9.01	0.05	ORD-105676
5588	52456	6	3	95.49	0.00	ORD-105677
5589	53638	15	1	77.86	0.00	ORD-105678
5590	54808	13	1	516.13	0.00	ORD-105679
5591	52889	3	1	130.29	0.00	ORD-105680
5592	54809	11	1	9.00	0.00	ORD-105681
5593	53763	5	2	89.42	0.05	ORD-105682
5594	55489	8	1	734.17	0.15	ORD-105683
5595	53845	18	1	14.37	0.00	ORD-105684
5596	50225	12	4	24.99	0.00	ORD-105685
5597	54445	20	1	322.55	0.00	ORD-105686
5598	53460	10	1	175.69	0.00	ORD-105687
5599	50766	18	6	14.63	0.05	ORD-105688
5600	54955	12	6	26.09	0.10	ORD-105689
5601	53484	16	1	649.69	0.20	ORD-105690
5602	52034	12	4	25.45	0.20	ORD-105691
5603	50636	18	4	15.73	0.05	ORD-105692
5604	55541	5	2	92.52	0.00	ORD-105693
5605	52406	19	2	22.33	0.00	ORD-105694
5606	52297	3	1	135.92	0.00	ORD-105695
5607	50742	4	2	146.02	0.00	ORD-105696
5608	50194	10	2	187.41	0.10	ORD-105697
5609	51608	16	1	657.83	0.15	ORD-105698
5610	52941	4	1	144.98	0.20	ORD-105699
5611	53508	9	4	12.49	0.00	ORD-105700
5612	54136	2	2	68.99	0.10	ORD-105701
5613	54956	20	2	324.25	0.10	ORD-105702
5614	53782	3	1	125.74	0.05	ORD-105703
5615	53538	20	1	322.81	0.15	ORD-105704
5616	50374	11	3	8.56	0.05	ORD-105705
5617	51319	12	8	25.61	0.20	ORD-105706
5618	50046	15	3	80.58	0.00	ORD-105707
5619	54831	9	4	11.49	0.05	ORD-105708
5620	51103	3	2	135.33	0.00	ORD-105709
5621	52407	15	2	79.38	0.10	ORD-105710
5622	52784	6	3	96.73	0.15	ORD-105711
5623	55454	6	1	92.50	0.20	ORD-105712
5624	50426	3	1	126.80	0.10	ORD-105713
5625	51103	11	4	8.75	0.00	ORD-105714
5626	55409	5	1	94.22	0.00	ORD-105715
5627	53846	2	2	70.00	0.00	ORD-105716
5628	54313	7	1	57.44	0.00	ORD-105717
5629	55410	5	2	90.94	0.00	ORD-105718
5630	54239	3	1	130.63	0.00	ORD-105719
5631	55675	4	2	146.31	0.10	ORD-105720
5632	54186	19	2	22.28	0.05	ORD-105721
5633	54957	12	4	23.98	0.00	ORD-105722
5634	50942	18	5	14.80	0.05	ORD-105723
5635	55411	5	1	85.88	0.00	ORD-105724
5636	54284	3	1	134.07	0.15	ORD-105725
5637	55062	2	1	69.68	0.00	ORD-105726
5638	51105	16	1	660.18	0.00	ORD-105727
5639	53578	5	1	88.17	0.10	ORD-105728
5640	50549	18	3	14.79	0.00	ORD-105729
5641	55413	2	2	69.06	0.05	ORD-105730
5642	52244	15	4	81.23	0.10	ORD-105731
5643	53110	9	3	12.20	0.00	ORD-105732
5644	55412	2	1	72.43	0.15	ORD-105733
5645	55063	10	1	178.89	0.05	ORD-105734
5646	51104	1	2	106.10	0.05	ORD-105735
5647	52102	6	1	92.32	0.00	ORD-105736
5648	51833	12	6	23.79	0.05	ORD-105737
5649	52504	2	1	67.05	0.10	ORD-105738
5650	51625	15	2	81.50	0.15	ORD-105739
5651	51490	7	5	62.96	0.00	ORD-105740
5652	50877	19	3	21.69	0.10	ORD-105741
5653	52199	6	1	94.86	0.20	ORD-105742
5654	51946	20	1	321.78	0.00	ORD-105743
5655	54540	18	2	15.54	0.00	ORD-105744
5656	55655	18	4	15.63	0.00	ORD-105745
5657	53923	5	2	85.94	0.00	ORD-105746
5658	50878	12	3	25.25	0.05	ORD-105747
5659	54354	4	2	155.09	0.05	ORD-105748
5660	52762	10	1	174.39	0.10	ORD-105749
5661	50533	14	2	201.14	0.10	ORD-105751
5662	50673	12	7	26.05	0.15	ORD-105752
5663	52623	19	1	22.90	0.10	ORD-105753
5664	55414	15	3	82.28	0.00	ORD-105754
5665	53707	19	3	22.44	0.00	ORD-105755
5666	54314	14	3	212.14	0.10	ORD-105756
5667	54373	2	1	66.94	0.00	ORD-105757
5668	55049	15	1	78.45	0.05	ORD-105758
5669	55795	14	1	211.30	0.00	ORD-105759
5670	51320	1	3	112.48	0.10	ORD-105760
5671	54315	10	1	180.56	0.20	ORD-105761
5672	50637	13	3	501.15	0.05	ORD-105762
5673	53412	5	2	88.65	0.05	ORD-105763
5674	50375	10	1	188.24	0.10	ORD-105764
5675	51204	15	2	83.55	0.00	ORD-105765
5676	52942	6	2	95.98	0.00	ORD-105766
5677	53485	11	3	8.59	0.00	ORD-105767
5678	55542	13	1	523.36	0.10	ORD-105768
5679	55415	6	2	94.24	0.00	ORD-105769
5680	51666	7	3	58.17	0.05	ORD-105770
5681	52710	3	1	127.19	0.00	ORD-105771
5682	52763	15	1	83.46	0.15	ORD-105772
5683	54958	5	1	88.66	0.15	ORD-105773
5684	54412	8	2	737.56	0.05	ORD-105774
5685	51223	1	1	106.22	0.05	ORD-105775
5686	52890	7	3	60.12	0.20	ORD-105776
5687	54006	14	1	209.47	0.00	ORD-105777
5688	53074	16	2	660.10	0.20	ORD-105778
5689	54078	12	5	24.66	0.00	ORD-105779
5690	54959	4	1	142.99	0.05	ORD-105780
5691	55050	7	1	59.20	0.10	ORD-105781
5692	51816	12	2	23.99	0.05	ORD-105782
5693	54810	17	1	417.22	0.00	ORD-105783
5694	51403	16	1	660.13	0.00	ORD-105784
5695	54589	14	1	212.98	0.00	ORD-105785
5696	55656	18	5	14.87	0.00	ORD-105786
5697	51321	7	3	59.29	0.15	ORD-105787
5698	51947	2	1	67.74	0.05	ORD-105788
5699	50829	13	2	544.86	0.00	ORD-105789
5700	52287	12	7	24.70	0.05	ORD-105790
5701	53847	16	1	628.79	0.00	ORD-105791
5702	55590	13	2	499.57	0.05	ORD-105792
5703	50110	2	1	67.26	0.00	ORD-105793
5704	54285	3	1	134.06	0.00	ORD-105794
5705	55127	14	4	211.55	0.15	ORD-105795
5706	53764	9	2	12.40	0.00	ORD-105796
5707	54446	6	2	99.47	0.00	ORD-105797
5708	52288	5	1	86.06	0.20	ORD-105798
5709	52803	5	1	88.65	0.00	ORD-105799
5710	52368	18	3	15.73	0.00	ORD-105800
5711	51322	13	1	506.47	0.15	ORD-105801
5712	55766	9	4	12.48	0.00	ORD-105802
5713	54007	1	2	109.40	0.20	ORD-105803
5714	54463	18	6	14.87	0.10	ORD-105804
5715	55416	18	5	15.38	0.00	ORD-105805
5716	52711	8	2	768.60	0.00	ORD-105806
5717	51626	2	1	70.48	0.00	ORD-105807
5718	50376	19	3	22.38	0.00	ORD-105808
5719	53075	7	2	62.74	0.00	ORD-105809
5720	55417	3	2	136.04	0.00	ORD-105810
5721	51817	12	4	25.07	0.15	ORD-105811
5722	51948	16	2	617.10	0.10	ORD-105812
5723	52363	17	1	412.53	0.00	ORD-105813
5724	50879	17	1	423.48	0.10	ORD-105814
5725	52289	5	2	91.45	0.05	ORD-105815
5726	52200	13	1	534.69	0.10	ORD-105816
5727	54413	18	3	15.71	0.00	ORD-105817
5728	54541	7	4	57.31	0.05	ORD-105818
5729	54137	13	1	508.34	0.00	ORD-105819
5730	50596	1	1	105.25	0.00	ORD-105820
5731	51412	15	1	83.96	0.00	ORD-105821
5732	54008	11	4	8.87	0.00	ORD-105822
5733	50195	9	2	11.96	0.00	ORD-105823
5734	52852	12	3	25.69	0.00	ORD-105824
5735	54414	2	1	67.92	0.05	ORD-105825
5736	53413	20	2	341.25	0.10	ORD-105826
5737	52408	6	3	93.95	0.05	ORD-105827
5738	54757	3	1	126.90	0.00	ORD-105828
5739	54240	14	1	209.65	0.05	ORD-105829
5740	55051	17	1	405.91	0.00	ORD-105830
5741	50550	11	6	9.39	0.10	ORD-105831
5742	53848	12	3	24.29	0.00	ORD-105832
5743	52891	13	1	538.66	0.00	ORD-105833
5744	53395	19	3	22.98	0.00	ORD-105834
5745	54507	19	2	22.20	0.10	ORD-105835
5746	53225	2	1	70.24	0.15	ORD-105836
5747	53539	2	1	71.16	0.05	ORD-105837
5748	51323	6	1	96.46	0.15	ORD-105838
5749	50880	1	4	112.27	0.00	ORD-105839
5750	51404	14	1	202.59	0.10	ORD-105840
5751	53225	6	3	91.77	0.00	ORD-105841
5752	55418	6	5	98.04	0.15	ORD-105842
5753	53414	19	1	22.99	0.20	ORD-105844
5754	50378	2	2	71.33	0.05	ORD-105845
5755	54811	14	1	216.07	0.15	ORD-105846
5756	50059	16	1	634.62	0.00	ORD-105847
5757	54663	20	1	316.33	0.00	ORD-105848
5758	50196	11	4	8.96	0.00	ORD-105849
5759	53076	13	1	530.05	0.00	ORD-105850
5760	50377	9	4	11.87	0.05	ORD-105851
5761	55419	5	2	93.85	0.00	ORD-105852
5762	54355	5	1	91.62	0.00	ORD-105853
5763	55796	13	1	530.47	0.00	ORD-105854
5764	54447	6	2	93.98	0.00	ORD-105855
5765	51818	13	2	543.77	0.05	ORD-105856
5766	52825	3	1	132.25	0.05	ORD-105857
5767	52542	11	1	8.73	0.00	ORD-105858
5768	53346	12	5	24.30	0.00	ORD-105860
5769	53639	11	7	8.90	0.05	ORD-105861
5770	54115	18	5	15.68	0.00	ORD-105862
5771	54079	1	1	111.81	0.10	ORD-105863
5772	53708	11	2	9.07	0.00	ORD-105864
5773	52634	17	1	435.03	0.10	ORD-105865
5774	54488	16	1	658.37	0.00	ORD-105866
5775	54009	11	3	9.32	0.10	ORD-105867
5776	51627	1	1	110.59	0.00	ORD-105868
5777	51491	20	3	331.42	0.00	ORD-105869
5778	53396	10	1	172.38	0.00	ORD-105870
5779	55151	12	4	25.38	0.00	ORD-105871
5780	54458	15	3	78.81	0.00	ORD-105872
5781	54080	14	1	206.16	0.00	ORD-105873
5782	54164	3	1	125.44	0.00	ORD-105874
5783	52712	15	5	80.19	0.00	ORD-105875
5784	51696	5	1	87.65	0.00	ORD-105876
5785	55420	7	2	59.46	0.20	ORD-105877
5786	53001	6	2	95.77	0.10	ORD-105878
5787	52484	1	1	109.95	0.10	ORD-105879
5788	52050	17	1	440.54	0.20	ORD-105880
5789	54758	20	1	343.48	0.10	ORD-105881
5790	51568	17	1	405.81	0.20	ORD-105882
5791	51834	8	3	748.41	0.10	ORD-105883
5792	52892	8	3	769.56	0.00	ORD-105884
5793	52635	1	1	104.60	0.05	ORD-105885
5794	50674	6	3	94.24	0.00	ORD-105886
5795	51949	20	3	329.84	0.10	ORD-105887
5796	54415	14	2	203.60	0.20	ORD-105888
5797	50551	1	1	115.39	0.05	ORD-105889
5798	51949	19	3	21.08	0.05	ORD-105890
5799	53397	1	2	104.84	0.00	ORD-105891
5800	55574	18	4	14.60	0.00	ORD-105892
5801	54374	1	1	106.64	0.10	ORD-105893
5802	51324	9	3	11.97	0.00	ORD-105894
5803	50505	1	2	107.74	0.00	ORD-105895
5804	50944	12	3	25.52	0.00	ORD-105896
5805	50943	7	1	62.91	0.15	ORD-105897
5806	53077	17	1	427.82	0.10	ORD-105898
5807	54316	19	2	21.84	0.00	ORD-105899
5808	52682	7	2	59.91	0.10	ORD-105900
5809	51569	4	1	154.26	0.05	ORD-105901
5810	52893	4	1	144.39	0.05	ORD-105902
5811	55676	11	3	9.18	0.00	ORD-105903
5812	54417	7	2	61.92	0.10	ORD-105904
5813	51492	1	1	112.66	0.00	ORD-105905
5814	50202	5	1	90.69	0.10	ORD-105906
5815	50506	12	3	25.30	0.00	ORD-105907
5816	55162	16	1	668.99	0.00	ORD-105908
5817	54416	2	3	72.57	0.00	ORD-105909
5818	53896	19	3	21.69	0.20	ORD-105910
5819	51106	18	6	14.45	0.00	ORD-105911
5820	52290	17	1	408.63	0.00	ORD-105912
5821	51819	20	2	324.21	0.15	ORD-105913
5822	50784	9	4	12.55	0.05	ORD-105914
5823	55128	13	1	495.79	0.10	ORD-105915
5824	52290	18	3	15.39	0.00	ORD-105916
5825	52943	15	1	79.93	0.05	ORD-105917
5826	55657	14	1	214.64	0.00	ORD-105918
5827	51952	15	3	77.98	0.10	ORD-105919
5828	53078	5	1	92.75	0.00	ORD-105920
5829	52409	11	4	9.20	0.05	ORD-105921
5830	51951	8	2	759.09	0.15	ORD-105922
5831	50743	18	4	15.26	0.00	ORD-105923
5832	50945	3	1	136.24	0.00	ORD-105924
5833	51974	8	1	716.76	0.20	ORD-105925
5834	50379	15	1	82.18	0.00	ORD-105926
5835	51950	20	2	321.40	0.10	ORD-105927
5836	54473	15	1	80.88	0.00	ORD-105928
5837	54418	7	1	62.78	0.00	ORD-105929
5838	55421	5	1	87.79	0.00	ORD-105930
5839	54459	5	1	90.74	0.00	ORD-105931
5840	54317	19	1	21.32	0.10	ORD-105932
5841	52785	9	2	12.31	0.00	ORD-105933
5842	54742	15	2	79.65	0.15	ORD-105934
5843	53121	8	1	715.04	0.00	ORD-105935
5844	51953	12	1	26.03	0.10	ORD-105936
5845	51325	7	2	59.58	0.20	ORD-105937
5846	52713	17	2	430.95	0.00	ORD-105938
5847	53226	2	2	72.68	0.00	ORD-105939
5848	54664	9	2	12.27	0.00	ORD-105940
5849	51326	20	4	341.62	0.00	ORD-105941
5850	51107	19	4	22.04	0.10	ORD-105942
5851	51953	11	6	9.13	0.10	ORD-105943
5852	54960	14	2	202.53	0.10	ORD-105944
5853	50465	16	1	639.04	0.00	ORD-105945
5854	55052	11	2	9.09	0.05	ORD-105946
5855	51788	20	1	333.63	0.15	ORD-105947
5856	53640	10	1	175.08	0.10	ORD-105949
5857	55422	20	1	331.53	0.05	ORD-105950
5858	50226	19	3	22.23	0.00	ORD-105951
5859	50744	12	6	26.00	0.05	ORD-105952
5860	52894	13	1	517.21	0.00	ORD-105953
5861	51954	17	1	412.30	0.00	ORD-105954
5862	53079	2	1	69.56	0.05	ORD-105955
5863	51955	11	3	8.98	0.05	ORD-105956
5864	51609	9	5	11.64	0.00	ORD-105957
5865	54286	5	2	89.11	0.00	ORD-105958
5866	50279	2	1	69.21	0.15	ORD-105959
5867	55064	15	1	81.43	0.05	ORD-105960
5868	50380	5	1	89.59	0.05	ORD-105961
5869	51956	1	1	113.87	0.00	ORD-105962
5870	51201	2	2	67.47	0.05	ORD-105963
5871	50111	6	2	91.63	0.15	ORD-105964
5872	53641	6	2	93.33	0.05	ORD-105965
5873	50280	5	1	93.02	0.05	ORD-105966
5874	54187	17	1	418.96	0.05	ORD-105967
5875	51957	18	3	14.84	0.20	ORD-105968
5876	52543	9	6	11.71	0.00	ORD-105969
5877	54241	18	6	14.29	0.00	ORD-105970
5878	50946	18	4	14.85	0.10	ORD-105971
5879	54095	10	1	175.65	0.15	ORD-105972
5880	50304	4	1	152.41	0.00	ORD-105973
5881	50381	16	1	662.32	0.00	ORD-105974
5882	54489	20	1	338.46	0.00	ORD-105975
5883	51327	14	1	215.08	0.10	ORD-105976
5884	55423	11	5	8.91	0.05	ORD-105977
5885	55543	11	5	8.75	0.10	ORD-105978
5886	54685	1	1	110.40	0.10	ORD-105979
5887	54081	9	5	11.82	0.00	ORD-105980
5888	53557	18	2	15.17	0.00	ORD-105981
5889	52786	14	1	208.53	0.05	ORD-105982
5890	51996	17	1	412.02	0.00	ORD-105983
5891	54743	4	1	145.45	0.00	ORD-105984
5892	51181	2	1	66.55	0.10	ORD-105985
5893	54961	12	7	23.84	0.05	ORD-105986
5894	50382	15	1	78.00	0.10	ORD-105987
5895	55424	20	1	334.80	0.00	ORD-105988
5896	52410	12	12	26.06	0.00	ORD-105989
5897	52505	15	1	78.83	0.00	ORD-105991
5898	54672	18	2	15.07	0.00	ORD-105992
5899	51108	8	3	744.01	0.15	ORD-105993
5900	51570	17	2	411.42	0.10	ORD-105994
5901	50881	18	3	15.12	0.10	ORD-105995
5902	54082	2	2	69.55	0.00	ORD-105996
5903	53709	13	1	505.48	0.00	ORD-105997
5904	52624	9	6	11.55	0.00	ORD-105998
5905	53298	20	2	326.25	0.10	ORD-105999
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orders (order_id, order_date, customer_id, payment_method) FROM stdin;
50001	2024-01-06	CUST-1000	Credit Card
50002	2024-01-21	CUST-1000	Credit Card
50003	2024-03-08	CUST-1000	Credit Card
50004	2024-03-16	CUST-1000	Cash
50005	2024-03-16	CUST-1000	Credit Card
50006	2024-04-06	CUST-1000	Debit Card
50007	2024-04-12	CUST-1000	Debit Card
50008	2024-04-21	CUST-1000	Debit Card
50009	2024-04-22	CUST-1000	Credit Card
50010	2024-05-21	CUST-1000	Cash
50011	2024-05-28	CUST-1000	Cash
50012	2024-06-03	CUST-1000	Cash
50013	2024-06-30	CUST-1000	Cash
50014	2024-07-08	CUST-1000	Paypal
50015	2024-08-15	CUST-1000	Credit Card
50016	2024-08-25	CUST-1000	Debit Card
50017	2024-09-04	CUST-1000	Debit Card
50018	2024-09-09	CUST-1000	Cash
50019	2024-09-09	CUST-1000	Credit Card
50020	2024-10-01	CUST-1000	Credit Card
50021	2024-10-24	CUST-1000	Paypal
50022	2024-11-26	CUST-1000	Credit Card
50023	2024-11-30	CUST-1000	Credit Card
50024	2024-12-02	CUST-1000	Credit Card
50025	2024-12-03	CUST-1000	Debit Card
50026	2024-12-08	CUST-1000	Credit Card
50027	2024-12-20	CUST-1000	Credit Card
50028	2024-12-31	CUST-1000	Cash
50029	2025-01-25	CUST-1000	Cash
50030	2025-02-11	CUST-1000	Debit Card
50031	2025-03-15	CUST-1000	Debit Card
50032	2025-03-24	CUST-1000	Debit Card
50033	2025-03-26	CUST-1000	Paypal
50034	2025-04-09	CUST-1000	Credit Card
50035	2025-06-18	CUST-1000	Credit Card
50036	2025-07-14	CUST-1000	Debit Card
50037	2025-07-15	CUST-1000	Paypal
50038	2025-07-28	CUST-1000	Credit Card
50039	2025-08-15	CUST-1000	Cash
50040	2025-09-10	CUST-1000	Paypal
50041	2025-10-04	CUST-1000	Credit Card
50042	2025-10-08	CUST-1000	Credit Card
50043	2025-10-23	CUST-1000	Paypal
50044	2025-10-28	CUST-1000	Paypal
50045	2025-11-11	CUST-1000	Cash
50046	2025-12-09	CUST-1000	Debit Card
50047	2024-02-04	CUST-1001	Debit Card
50048	2024-03-28	CUST-1001	Paypal
50049	2024-04-05	CUST-1001	Cash
50050	2024-04-19	CUST-1001	Credit Card
50051	2024-09-30	CUST-1001	Paypal
50052	2024-11-21	CUST-1001	Debit Card
50053	2024-12-14	CUST-1001	Cash
50054	2024-12-15	CUST-1001	Credit Card
50055	2025-01-02	CUST-1001	Debit Card
50056	2025-01-03	CUST-1001	Paypal
50057	2025-08-06	CUST-1001	Cash
50058	2025-10-08	CUST-1001	Paypal
50059	2025-12-21	CUST-1001	Paypal
50060	2024-01-29	CUST-1002	Credit Card
50061	2024-03-29	CUST-1002	Debit Card
50062	2024-04-03	CUST-1002	Debit Card
50063	2024-05-01	CUST-1002	Debit Card
50064	2024-06-08	CUST-1002	Credit Card
50065	2024-06-22	CUST-1002	Paypal
50066	2024-07-10	CUST-1002	Paypal
50067	2024-10-31	CUST-1002	Debit Card
50068	2024-11-07	CUST-1002	Paypal
50069	2024-11-08	CUST-1002	Cash
50070	2024-12-16	CUST-1002	Credit Card
50071	2025-02-11	CUST-1002	Credit Card
50072	2025-02-14	CUST-1002	Credit Card
50073	2025-07-08	CUST-1002	Debit Card
50074	2025-08-28	CUST-1002	Credit Card
50075	2025-09-07	CUST-1002	Cash
50076	2025-11-05	CUST-1002	Debit Card
50077	2025-05-02	CUST-1004	Cash
50078	2025-07-11	CUST-1004	Debit Card
50079	2025-07-23	CUST-1004	Debit Card
50080	2024-08-31	CUST-1005	Credit Card
50081	2024-09-14	CUST-1005	Paypal
50082	2024-09-19	CUST-1005	Credit Card
50083	2024-11-09	CUST-1005	Debit Card
50084	2025-01-13	CUST-1005	Credit Card
50085	2025-07-23	CUST-1005	Cash
50086	2025-10-14	CUST-1005	Credit Card
50087	2025-11-25	CUST-1005	Credit Card
50088	2024-01-29	CUST-1006	Debit Card
50089	2024-07-04	CUST-1006	Cash
50090	2024-12-17	CUST-1006	Debit Card
50091	2024-01-03	CUST-1007	Debit Card
50092	2024-01-23	CUST-1007	Credit Card
50093	2024-02-06	CUST-1007	Cash
50094	2024-03-30	CUST-1007	Debit Card
50095	2024-07-04	CUST-1007	Cash
50096	2024-10-05	CUST-1007	Credit Card
50097	2024-10-26	CUST-1007	Credit Card
50098	2024-11-18	CUST-1007	Credit Card
50099	2024-12-17	CUST-1007	Debit Card
50100	2025-02-01	CUST-1007	Credit Card
50101	2025-02-02	CUST-1007	Credit Card
50102	2025-03-12	CUST-1007	Debit Card
50103	2025-03-30	CUST-1007	Debit Card
50104	2025-04-24	CUST-1007	Debit Card
50105	2025-05-31	CUST-1007	Credit Card
50106	2025-06-18	CUST-1007	Paypal
50107	2025-08-19	CUST-1007	Credit Card
50108	2025-09-01	CUST-1007	Debit Card
50109	2025-12-02	CUST-1007	Credit Card
50110	2025-12-16	CUST-1007	Credit Card
50111	2025-12-29	CUST-1007	Debit Card
50112	2024-01-25	CUST-1008	Credit Card
50113	2024-01-31	CUST-1008	Debit Card
50114	2024-02-10	CUST-1008	Paypal
50115	2024-02-13	CUST-1008	Cash
50116	2024-02-26	CUST-1008	Credit Card
50117	2024-03-07	CUST-1008	Paypal
50118	2024-03-30	CUST-1008	Cash
50119	2024-04-01	CUST-1008	Debit Card
50120	2024-04-05	CUST-1008	Debit Card
50121	2024-04-20	CUST-1008	Credit Card
50122	2024-04-27	CUST-1008	Credit Card
50123	2024-04-28	CUST-1008	Credit Card
50124	2024-05-01	CUST-1008	Credit Card
50125	2024-05-06	CUST-1008	Cash
50126	2024-05-13	CUST-1008	Cash
50127	2024-05-18	CUST-1008	Debit Card
50128	2024-06-02	CUST-1008	Debit Card
50129	2024-06-11	CUST-1008	Cash
50130	2024-07-03	CUST-1008	Credit Card
50131	2024-07-18	CUST-1008	Debit Card
50132	2024-07-27	CUST-1008	Credit Card
50133	2024-07-28	CUST-1008	Debit Card
50134	2024-08-06	CUST-1008	Paypal
50135	2024-08-20	CUST-1008	Credit Card
50136	2024-08-20	CUST-1008	Debit Card
50137	2024-08-30	CUST-1008	Credit Card
50138	2024-09-02	CUST-1008	Credit Card
50139	2024-09-19	CUST-1008	Credit Card
50140	2024-10-15	CUST-1008	Credit Card
50141	2024-10-15	CUST-1008	Paypal
50142	2024-10-23	CUST-1008	Credit Card
50143	2024-10-24	CUST-1008	Credit Card
50144	2024-11-03	CUST-1008	Paypal
50145	2024-11-17	CUST-1008	Credit Card
50146	2024-11-22	CUST-1008	Credit Card
50147	2024-11-24	CUST-1008	Debit Card
50148	2024-12-05	CUST-1008	Cash
50149	2024-12-09	CUST-1008	Debit Card
50150	2024-12-13	CUST-1008	Debit Card
50151	2024-12-14	CUST-1008	Credit Card
50152	2024-12-30	CUST-1008	Debit Card
50153	2025-01-03	CUST-1008	Credit Card
50154	2025-02-15	CUST-1008	Cash
50155	2025-02-25	CUST-1008	Credit Card
50156	2025-03-16	CUST-1008	Credit Card
50157	2025-03-30	CUST-1008	Debit Card
50158	2025-04-01	CUST-1008	Credit Card
50159	2025-04-26	CUST-1008	Paypal
50160	2025-04-30	CUST-1008	Credit Card
50161	2025-05-01	CUST-1008	Cash
50162	2025-05-22	CUST-1008	Debit Card
50163	2025-05-27	CUST-1008	Paypal
50164	2025-06-01	CUST-1008	Credit Card
50165	2025-06-04	CUST-1008	Cash
50166	2025-06-10	CUST-1008	Cash
50167	2025-06-11	CUST-1008	Debit Card
50168	2025-06-15	CUST-1008	Debit Card
50169	2025-06-20	CUST-1008	Credit Card
50170	2025-06-30	CUST-1008	Cash
50171	2025-07-06	CUST-1008	Credit Card
50172	2025-07-16	CUST-1008	Cash
50173	2025-07-16	CUST-1008	Debit Card
50174	2025-07-22	CUST-1008	Paypal
50175	2025-07-25	CUST-1008	Credit Card
50176	2025-08-12	CUST-1008	Paypal
50177	2025-08-16	CUST-1008	Credit Card
50178	2025-08-16	CUST-1008	Paypal
50179	2025-08-18	CUST-1008	Paypal
50180	2025-08-23	CUST-1008	Debit Card
50181	2025-09-05	CUST-1008	Paypal
50182	2025-09-10	CUST-1008	Debit Card
50183	2025-09-12	CUST-1008	Paypal
50184	2025-09-19	CUST-1008	Credit Card
50185	2025-10-08	CUST-1008	Debit Card
50186	2025-10-19	CUST-1008	Debit Card
50187	2025-10-20	CUST-1008	Paypal
50188	2025-11-06	CUST-1008	Credit Card
50189	2025-11-11	CUST-1008	Paypal
50190	2025-11-18	CUST-1008	Debit Card
50191	2025-11-26	CUST-1008	Cash
50192	2025-11-30	CUST-1008	Credit Card
50193	2025-11-30	CUST-1008	Paypal
50194	2025-12-09	CUST-1008	Cash
50195	2025-12-19	CUST-1008	Cash
50196	2025-12-21	CUST-1008	Credit Card
50197	2024-01-05	CUST-1009	Debit Card
50198	2024-01-26	CUST-1009	Credit Card
50199	2024-12-17	CUST-1009	Cash
50200	2025-04-19	CUST-1009	Debit Card
50201	2025-11-24	CUST-1009	Debit Card
50202	2025-12-26	CUST-1009	Debit Card
50203	2024-05-05	CUST-1010	Credit Card
50204	2024-06-10	CUST-1010	Debit Card
50205	2024-09-12	CUST-1010	Debit Card
50206	2024-10-21	CUST-1010	Paypal
50207	2024-12-24	CUST-1010	Debit Card
50208	2025-02-03	CUST-1010	Debit Card
50209	2025-04-17	CUST-1010	Cash
50210	2025-09-02	CUST-1010	Paypal
50211	2025-11-08	CUST-1010	Debit Card
50212	2024-02-05	CUST-1011	Debit Card
50213	2024-03-25	CUST-1011	Paypal
50214	2024-06-15	CUST-1011	Credit Card
50215	2024-06-21	CUST-1011	Credit Card
50216	2024-07-01	CUST-1011	Debit Card
50217	2024-07-31	CUST-1011	Credit Card
50218	2024-08-03	CUST-1011	Credit Card
50219	2024-08-09	CUST-1011	Debit Card
50220	2024-10-14	CUST-1011	Credit Card
50221	2024-12-28	CUST-1011	Credit Card
50222	2025-05-22	CUST-1011	Credit Card
50223	2025-09-16	CUST-1011	Debit Card
50224	2025-09-22	CUST-1011	Credit Card
50225	2025-12-07	CUST-1011	Debit Card
50226	2025-12-29	CUST-1011	Credit Card
50227	2024-01-18	CUST-1012	Cash
50228	2024-01-27	CUST-1012	Paypal
50229	2024-02-10	CUST-1012	Debit Card
50230	2024-02-14	CUST-1012	Debit Card
50231	2024-05-12	CUST-1012	Debit Card
50232	2024-05-15	CUST-1012	Debit Card
50233	2024-05-27	CUST-1012	Credit Card
50234	2024-06-21	CUST-1012	Debit Card
50235	2024-06-27	CUST-1012	Cash
50236	2024-07-01	CUST-1012	Credit Card
50237	2024-07-07	CUST-1012	Debit Card
50238	2024-08-22	CUST-1012	Cash
50239	2024-09-05	CUST-1012	Cash
50240	2024-09-16	CUST-1012	Credit Card
50241	2024-09-24	CUST-1012	Credit Card
50242	2024-10-30	CUST-1012	Cash
50243	2024-11-10	CUST-1012	Cash
50244	2024-12-04	CUST-1012	Debit Card
50245	2024-12-07	CUST-1012	Credit Card
50246	2024-12-14	CUST-1012	Debit Card
50247	2024-12-15	CUST-1012	Cash
50248	2025-01-11	CUST-1012	Credit Card
50249	2025-01-12	CUST-1012	Debit Card
50250	2025-01-13	CUST-1012	Debit Card
50251	2025-01-23	CUST-1012	Debit Card
50252	2025-02-05	CUST-1012	Credit Card
50253	2025-02-28	CUST-1012	Credit Card
50254	2025-03-10	CUST-1012	Credit Card
50255	2025-03-18	CUST-1012	Credit Card
50256	2025-03-20	CUST-1012	Debit Card
50257	2025-05-21	CUST-1012	Credit Card
50258	2025-05-27	CUST-1012	Credit Card
50259	2025-06-06	CUST-1012	Debit Card
50260	2025-06-10	CUST-1012	Paypal
50261	2025-07-12	CUST-1012	Credit Card
50262	2025-07-18	CUST-1012	Credit Card
50263	2025-08-29	CUST-1012	Debit Card
50264	2025-08-30	CUST-1012	Debit Card
50265	2025-09-01	CUST-1012	Credit Card
50266	2025-09-02	CUST-1012	Debit Card
50267	2025-09-16	CUST-1012	Paypal
50268	2025-09-20	CUST-1012	Paypal
50269	2025-10-03	CUST-1012	Cash
50270	2025-10-23	CUST-1012	Credit Card
50271	2025-10-24	CUST-1012	Credit Card
50272	2025-11-13	CUST-1012	Credit Card
50273	2025-11-17	CUST-1012	Debit Card
50274	2025-11-25	CUST-1012	Paypal
50275	2025-11-27	CUST-1012	Cash
50276	2025-11-27	CUST-1012	Credit Card
50277	2025-11-30	CUST-1012	Credit Card
50278	2025-12-01	CUST-1012	Credit Card
50279	2025-12-29	CUST-1012	Credit Card
50280	2025-12-30	CUST-1012	Credit Card
50281	2025-03-14	CUST-1013	Credit Card
50282	2025-10-07	CUST-1013	Debit Card
50283	2025-10-16	CUST-1013	Credit Card
50284	2025-11-25	CUST-1013	Credit Card
50285	2024-01-26	CUST-1014	Cash
50286	2024-08-06	CUST-1014	Paypal
50287	2024-10-11	CUST-1014	Cash
50288	2024-10-27	CUST-1014	Credit Card
50289	2024-10-28	CUST-1014	Debit Card
50290	2024-11-18	CUST-1014	Debit Card
50291	2024-12-23	CUST-1014	Debit Card
50292	2025-02-02	CUST-1014	Paypal
50293	2025-04-08	CUST-1014	Credit Card
50294	2025-04-26	CUST-1014	Debit Card
50295	2025-05-21	CUST-1014	Debit Card
50296	2025-06-14	CUST-1014	Credit Card
50297	2025-06-30	CUST-1014	Paypal
50298	2025-07-11	CUST-1014	Debit Card
50299	2025-07-27	CUST-1014	Cash
50300	2025-08-07	CUST-1014	Debit Card
50301	2025-11-05	CUST-1014	Credit Card
50302	2025-11-08	CUST-1014	Credit Card
50303	2025-11-23	CUST-1014	Credit Card
50304	2025-12-30	CUST-1014	Cash
50305	2024-01-04	CUST-1015	Credit Card
50306	2024-02-24	CUST-1015	Paypal
50307	2024-03-04	CUST-1015	Debit Card
50308	2024-03-07	CUST-1015	Credit Card
50309	2024-03-31	CUST-1015	Cash
50310	2024-05-10	CUST-1015	Credit Card
50311	2024-06-19	CUST-1015	Cash
50312	2024-07-24	CUST-1015	Paypal
50313	2024-08-04	CUST-1015	Credit Card
50314	2024-08-16	CUST-1015	Paypal
50315	2024-08-28	CUST-1015	Credit Card
50316	2024-09-16	CUST-1015	Credit Card
50317	2024-09-18	CUST-1015	Paypal
50318	2024-09-22	CUST-1015	Credit Card
50319	2024-10-07	CUST-1015	Credit Card
50320	2024-10-08	CUST-1015	Debit Card
50321	2024-10-12	CUST-1015	Paypal
50322	2024-10-17	CUST-1015	Credit Card
50323	2024-10-18	CUST-1015	Debit Card
50324	2024-10-23	CUST-1015	Debit Card
50325	2024-11-09	CUST-1015	Debit Card
50326	2024-11-16	CUST-1015	Credit Card
50327	2024-11-27	CUST-1015	Debit Card
50328	2024-11-29	CUST-1015	Paypal
50329	2024-12-03	CUST-1015	Credit Card
50330	2024-12-11	CUST-1015	Credit Card
50331	2024-12-27	CUST-1015	Paypal
50332	2025-01-03	CUST-1015	Credit Card
50333	2025-01-17	CUST-1015	Credit Card
50334	2025-02-14	CUST-1015	Paypal
50335	2025-03-08	CUST-1015	Paypal
50336	2025-03-14	CUST-1015	Cash
50337	2025-03-20	CUST-1015	Credit Card
50338	2025-03-26	CUST-1015	Debit Card
50339	2025-04-04	CUST-1015	Debit Card
50340	2025-04-09	CUST-1015	Debit Card
50341	2025-04-20	CUST-1015	Paypal
50342	2025-05-13	CUST-1015	Credit Card
50343	2025-05-14	CUST-1015	Credit Card
50344	2025-05-14	CUST-1015	Debit Card
50345	2025-05-16	CUST-1015	Cash
50346	2025-05-29	CUST-1015	Cash
50347	2025-06-01	CUST-1015	Cash
50348	2025-06-01	CUST-1015	Credit Card
50349	2025-06-05	CUST-1015	Paypal
50350	2025-06-20	CUST-1015	Paypal
50351	2025-06-24	CUST-1015	Cash
50352	2025-06-25	CUST-1015	Paypal
50353	2025-07-01	CUST-1015	Paypal
50354	2025-07-17	CUST-1015	Credit Card
50355	2025-08-13	CUST-1015	Debit Card
50356	2025-08-14	CUST-1015	Cash
50357	2025-08-15	CUST-1015	Paypal
50358	2025-08-16	CUST-1015	Credit Card
50359	2025-09-09	CUST-1015	Cash
50360	2025-09-14	CUST-1015	Paypal
50361	2025-09-15	CUST-1015	Cash
50362	2025-09-19	CUST-1015	Debit Card
50363	2025-09-21	CUST-1015	Debit Card
50364	2025-09-23	CUST-1015	Paypal
50365	2025-09-26	CUST-1015	Credit Card
50366	2025-10-15	CUST-1015	Credit Card
50367	2025-10-21	CUST-1015	Debit Card
50368	2025-10-23	CUST-1015	Credit Card
50369	2025-10-28	CUST-1015	Debit Card
50370	2025-11-09	CUST-1015	Cash
50371	2025-11-19	CUST-1015	Debit Card
50372	2025-11-23	CUST-1015	Credit Card
50373	2025-12-01	CUST-1015	Debit Card
50374	2025-12-09	CUST-1015	Cash
50375	2025-12-14	CUST-1015	Credit Card
50376	2025-12-18	CUST-1015	Cash
50377	2025-12-21	CUST-1015	Credit Card
50378	2025-12-21	CUST-1015	Paypal
50379	2025-12-27	CUST-1015	Debit Card
50380	2025-12-29	CUST-1015	Debit Card
50381	2025-12-30	CUST-1015	Cash
50382	2025-12-31	CUST-1015	Credit Card
50383	2024-02-28	CUST-1016	Credit Card
50384	2024-12-15	CUST-1016	Cash
50385	2024-09-12	CUST-1017	Debit Card
50386	2025-02-05	CUST-1017	Cash
50387	2025-04-02	CUST-1017	Debit Card
50388	2024-05-06	CUST-1018	Cash
50389	2024-06-14	CUST-1018	Debit Card
50390	2024-12-03	CUST-1018	Credit Card
50391	2025-05-05	CUST-1018	Credit Card
50392	2025-06-04	CUST-1018	Debit Card
50393	2025-09-23	CUST-1018	Debit Card
50394	2025-11-15	CUST-1018	Debit Card
50395	2024-12-02	CUST-1019	Credit Card
50396	2025-02-17	CUST-1019	Credit Card
50397	2025-07-29	CUST-1019	Paypal
50398	2025-08-11	CUST-1019	Paypal
50399	2025-09-29	CUST-1019	Credit Card
50400	2024-01-18	CUST-1020	Debit Card
50401	2024-02-27	CUST-1020	Cash
50402	2024-03-18	CUST-1020	Credit Card
50403	2024-04-22	CUST-1020	Debit Card
50404	2024-05-28	CUST-1020	Cash
50405	2024-05-29	CUST-1020	Paypal
50406	2024-06-01	CUST-1020	Paypal
50407	2024-06-15	CUST-1020	Credit Card
50408	2024-09-05	CUST-1020	Credit Card
50409	2024-09-08	CUST-1020	Paypal
50410	2024-10-17	CUST-1020	Debit Card
50411	2024-10-29	CUST-1020	Debit Card
50412	2024-12-22	CUST-1020	Paypal
50413	2025-04-13	CUST-1020	Credit Card
50414	2025-04-22	CUST-1020	Credit Card
50415	2025-04-25	CUST-1020	Credit Card
50416	2025-05-14	CUST-1020	Debit Card
50417	2025-06-08	CUST-1020	Debit Card
50418	2025-06-13	CUST-1020	Credit Card
50419	2025-07-21	CUST-1020	Paypal
50420	2025-07-27	CUST-1020	Cash
50421	2025-08-19	CUST-1020	Credit Card
50422	2025-09-01	CUST-1020	Credit Card
50423	2025-09-03	CUST-1020	Debit Card
50424	2025-10-30	CUST-1020	Debit Card
50425	2025-11-13	CUST-1020	Debit Card
50426	2025-12-10	CUST-1020	Credit Card
50427	2024-04-10	CUST-1021	Debit Card
50428	2024-07-27	CUST-1021	Debit Card
50429	2024-08-09	CUST-1021	Credit Card
50430	2024-09-29	CUST-1021	Debit Card
50431	2024-10-31	CUST-1021	Credit Card
50432	2025-01-19	CUST-1021	Debit Card
50433	2025-03-16	CUST-1021	Credit Card
50434	2025-03-30	CUST-1021	Credit Card
50435	2025-09-02	CUST-1021	Cash
50436	2025-09-17	CUST-1021	Paypal
50437	2025-10-13	CUST-1021	Paypal
50438	2025-11-30	CUST-1021	Credit Card
50439	2025-11-30	CUST-1021	Paypal
50440	2024-06-08	CUST-1022	Debit Card
50441	2024-09-21	CUST-1022	Debit Card
50442	2025-06-23	CUST-1022	Debit Card
50443	2025-07-21	CUST-1022	Debit Card
50444	2024-02-12	CUST-1023	Cash
50445	2024-02-21	CUST-1023	Credit Card
50446	2024-04-10	CUST-1023	Credit Card
50447	2024-06-07	CUST-1023	Credit Card
50448	2024-08-30	CUST-1023	Credit Card
50449	2024-09-19	CUST-1023	Debit Card
50450	2024-09-21	CUST-1023	Debit Card
50451	2024-10-14	CUST-1023	Credit Card
50452	2024-10-15	CUST-1023	Credit Card
50453	2024-11-14	CUST-1023	Credit Card
50454	2024-11-14	CUST-1023	Debit Card
50455	2025-03-03	CUST-1023	Debit Card
50456	2025-03-18	CUST-1023	Paypal
50457	2025-06-02	CUST-1023	Credit Card
50458	2025-08-11	CUST-1023	Debit Card
50459	2025-10-02	CUST-1023	Debit Card
50460	2025-10-07	CUST-1023	Debit Card
50461	2025-10-07	CUST-1023	Paypal
50462	2025-10-15	CUST-1023	Cash
50463	2025-11-22	CUST-1023	Credit Card
50464	2025-12-02	CUST-1023	Credit Card
50465	2025-12-28	CUST-1023	Credit Card
50466	2024-03-01	CUST-1024	Credit Card
50467	2024-07-12	CUST-1024	Cash
50468	2025-05-27	CUST-1024	Paypal
50469	2025-06-02	CUST-1024	Credit Card
50470	2025-07-25	CUST-1024	Paypal
50471	2024-01-16	CUST-1025	Credit Card
50472	2024-02-09	CUST-1025	Debit Card
50473	2024-03-20	CUST-1025	Paypal
50474	2024-05-05	CUST-1025	Cash
50475	2024-05-07	CUST-1025	Debit Card
50476	2024-05-27	CUST-1025	Credit Card
50477	2024-06-14	CUST-1025	Credit Card
50478	2024-06-25	CUST-1025	Credit Card
50479	2024-07-01	CUST-1025	Debit Card
50480	2024-09-16	CUST-1025	Credit Card
50481	2024-09-27	CUST-1025	Debit Card
50482	2024-11-30	CUST-1025	Credit Card
50483	2024-11-30	CUST-1025	Paypal
50484	2024-12-24	CUST-1025	Credit Card
50485	2024-12-31	CUST-1025	Credit Card
50486	2025-01-14	CUST-1025	Debit Card
50487	2025-01-15	CUST-1025	Debit Card
50488	2025-01-17	CUST-1025	Credit Card
50489	2025-01-19	CUST-1025	Credit Card
50490	2025-02-02	CUST-1025	Credit Card
50491	2025-03-01	CUST-1025	Debit Card
50492	2025-04-25	CUST-1025	Credit Card
50493	2025-05-03	CUST-1025	Credit Card
50494	2025-05-17	CUST-1025	Cash
50495	2025-05-17	CUST-1025	Debit Card
50496	2025-06-05	CUST-1025	Credit Card
50497	2025-08-12	CUST-1025	Cash
50498	2025-09-24	CUST-1025	Debit Card
50499	2025-10-11	CUST-1025	Credit Card
50500	2025-10-24	CUST-1025	Credit Card
50501	2025-11-02	CUST-1025	Debit Card
50502	2025-11-10	CUST-1025	Credit Card
50503	2025-11-24	CUST-1025	Debit Card
50504	2025-11-27	CUST-1025	Credit Card
50505	2025-12-25	CUST-1025	Debit Card
50506	2025-12-26	CUST-1025	Debit Card
50507	2024-07-21	CUST-1026	Credit Card
50508	2024-12-01	CUST-1026	Paypal
50509	2024-12-21	CUST-1026	Debit Card
50510	2024-12-27	CUST-1026	Credit Card
50511	2025-01-03	CUST-1026	Credit Card
50512	2025-09-14	CUST-1026	Paypal
50513	2025-10-21	CUST-1026	Credit Card
50514	2025-02-17	CUST-1027	Debit Card
50515	2025-07-24	CUST-1027	Debit Card
50516	2025-11-10	CUST-1027	Credit Card
50517	2024-01-29	CUST-1028	Debit Card
50518	2024-04-05	CUST-1028	Debit Card
50519	2024-07-22	CUST-1028	Debit Card
50520	2024-09-20	CUST-1028	Debit Card
50521	2024-10-06	CUST-1028	Debit Card
50522	2024-10-23	CUST-1028	Paypal
50523	2024-12-09	CUST-1028	Debit Card
50524	2024-12-10	CUST-1028	Cash
50525	2024-12-13	CUST-1028	Credit Card
50526	2024-12-20	CUST-1028	Debit Card
50527	2025-02-26	CUST-1028	Credit Card
50528	2025-03-20	CUST-1028	Paypal
50529	2025-08-25	CUST-1028	Credit Card
50530	2025-09-02	CUST-1028	Credit Card
50531	2025-10-03	CUST-1028	Debit Card
50532	2025-12-01	CUST-1028	Debit Card
50533	2025-12-13	CUST-1028	Paypal
50534	2024-03-22	CUST-1029	Cash
50535	2024-04-27	CUST-1029	Cash
50536	2024-07-11	CUST-1029	Credit Card
50537	2024-10-03	CUST-1029	Debit Card
50538	2024-10-15	CUST-1029	Debit Card
50539	2024-11-14	CUST-1029	Debit Card
50540	2024-12-08	CUST-1029	Debit Card
50541	2024-12-19	CUST-1029	Credit Card
50542	2025-01-08	CUST-1029	Credit Card
50543	2025-02-02	CUST-1029	Debit Card
50544	2025-03-08	CUST-1029	Cash
50545	2025-03-08	CUST-1029	Credit Card
50546	2025-05-06	CUST-1029	Debit Card
50547	2025-09-14	CUST-1029	Debit Card
50548	2025-10-17	CUST-1029	Credit Card
50549	2025-12-11	CUST-1029	Debit Card
50550	2025-12-19	CUST-1029	Credit Card
50551	2025-12-24	CUST-1029	Credit Card
50552	2024-06-15	CUST-1030	Credit Card
50553	2024-10-24	CUST-1030	Credit Card
50554	2024-11-15	CUST-1030	Credit Card
50555	2024-12-10	CUST-1030	Cash
50556	2024-12-14	CUST-1030	Credit Card
50557	2024-12-28	CUST-1030	Paypal
50558	2025-03-20	CUST-1030	Debit Card
50559	2025-05-23	CUST-1030	Credit Card
50560	2025-06-08	CUST-1030	Debit Card
50561	2025-08-19	CUST-1030	Debit Card
50562	2025-10-11	CUST-1030	Credit Card
50563	2025-11-07	CUST-1030	Paypal
50564	2025-11-26	CUST-1030	Credit Card
50565	2024-06-03	CUST-1031	Credit Card
50566	2025-01-20	CUST-1031	Credit Card
50567	2025-02-14	CUST-1031	Credit Card
50568	2025-03-13	CUST-1031	Debit Card
50569	2025-03-17	CUST-1031	Credit Card
50570	2025-10-14	CUST-1031	Debit Card
50571	2024-03-08	CUST-1032	Cash
50572	2024-04-09	CUST-1032	Cash
50573	2024-05-07	CUST-1032	Debit Card
50574	2024-05-24	CUST-1032	Cash
50575	2024-06-19	CUST-1032	Debit Card
50576	2024-07-09	CUST-1032	Cash
50577	2024-07-14	CUST-1032	Cash
50578	2024-09-05	CUST-1032	Credit Card
50579	2024-10-04	CUST-1032	Paypal
50580	2024-10-26	CUST-1032	Credit Card
50581	2024-11-03	CUST-1032	Debit Card
50582	2025-01-17	CUST-1032	Debit Card
50583	2025-01-21	CUST-1032	Cash
50584	2025-04-27	CUST-1032	Debit Card
50585	2025-05-14	CUST-1032	Credit Card
50586	2025-06-15	CUST-1032	Credit Card
50587	2025-07-12	CUST-1032	Debit Card
50588	2025-08-17	CUST-1032	Credit Card
50589	2025-08-26	CUST-1032	Paypal
50590	2025-09-14	CUST-1032	Debit Card
50591	2025-09-26	CUST-1032	Credit Card
50592	2025-10-15	CUST-1032	Credit Card
50593	2025-10-21	CUST-1032	Debit Card
50594	2025-10-31	CUST-1032	Credit Card
50595	2025-11-12	CUST-1032	Debit Card
50596	2025-12-18	CUST-1032	Credit Card
50597	2024-03-02	CUST-1033	Debit Card
50598	2024-05-31	CUST-1033	Credit Card
50599	2024-06-08	CUST-1033	Debit Card
50600	2025-10-02	CUST-1033	Debit Card
50601	2025-10-10	CUST-1033	Cash
50602	2024-02-16	CUST-1034	Debit Card
50603	2024-05-25	CUST-1034	Paypal
50604	2024-08-04	CUST-1034	Credit Card
50605	2024-08-09	CUST-1034	Debit Card
50606	2024-11-09	CUST-1034	Credit Card
50607	2025-01-18	CUST-1034	Credit Card
50608	2025-02-07	CUST-1034	Paypal
50609	2025-02-16	CUST-1034	Credit Card
50610	2025-04-16	CUST-1034	Credit Card
50611	2025-05-23	CUST-1034	Cash
50612	2025-06-08	CUST-1034	Paypal
50613	2025-08-21	CUST-1034	Credit Card
50614	2025-09-07	CUST-1034	Credit Card
50615	2025-11-05	CUST-1034	Cash
50616	2025-11-06	CUST-1034	Credit Card
50617	2025-11-14	CUST-1034	Paypal
50618	2024-07-07	CUST-1035	Credit Card
50619	2025-03-11	CUST-1035	Credit Card
50620	2025-04-10	CUST-1035	Cash
50621	2024-01-14	CUST-1036	Paypal
50622	2024-04-19	CUST-1036	Cash
50623	2024-06-15	CUST-1036	Debit Card
50624	2024-06-21	CUST-1036	Paypal
50625	2024-06-24	CUST-1036	Credit Card
50626	2024-10-01	CUST-1036	Credit Card
50627	2024-10-05	CUST-1036	Credit Card
50628	2024-11-15	CUST-1036	Credit Card
50629	2025-01-17	CUST-1036	Debit Card
50630	2025-02-07	CUST-1036	Cash
50631	2025-06-14	CUST-1036	Debit Card
50632	2025-07-05	CUST-1036	Cash
50633	2025-07-24	CUST-1036	Cash
50634	2025-09-06	CUST-1036	Debit Card
50635	2025-11-03	CUST-1036	Credit Card
50636	2025-12-08	CUST-1036	Credit Card
50637	2025-12-14	CUST-1036	Credit Card
50638	2024-11-16	CUST-1037	Paypal
50639	2024-08-11	CUST-1038	Debit Card
50640	2024-09-02	CUST-1038	Debit Card
50641	2024-12-28	CUST-1038	Debit Card
50642	2025-01-27	CUST-1038	Paypal
50643	2025-03-17	CUST-1038	Credit Card
50644	2024-04-01	CUST-1039	Credit Card
50645	2024-06-05	CUST-1039	Debit Card
50646	2024-06-10	CUST-1039	Credit Card
50647	2024-07-14	CUST-1039	Cash
50648	2024-07-24	CUST-1039	Paypal
50649	2024-07-25	CUST-1039	Paypal
50650	2024-08-12	CUST-1039	Credit Card
50651	2024-08-27	CUST-1039	Credit Card
50652	2024-10-10	CUST-1039	Credit Card
50653	2024-10-12	CUST-1039	Credit Card
50654	2024-10-15	CUST-1039	Debit Card
50655	2024-10-25	CUST-1039	Debit Card
50656	2024-10-29	CUST-1039	Credit Card
50657	2025-02-16	CUST-1039	Paypal
50658	2025-03-02	CUST-1039	Cash
50659	2025-03-04	CUST-1039	Debit Card
50660	2025-03-29	CUST-1039	Credit Card
50661	2025-04-16	CUST-1039	Debit Card
50662	2025-05-02	CUST-1039	Cash
50663	2025-05-18	CUST-1039	Credit Card
50664	2025-05-19	CUST-1039	Debit Card
50665	2025-05-21	CUST-1039	Debit Card
50666	2025-06-08	CUST-1039	Credit Card
50667	2025-06-24	CUST-1039	Credit Card
50668	2025-07-12	CUST-1039	Debit Card
50669	2025-07-26	CUST-1039	Credit Card
50670	2025-08-05	CUST-1039	Cash
50671	2025-08-11	CUST-1039	Cash
50672	2025-11-14	CUST-1039	Paypal
50673	2025-12-13	CUST-1039	Credit Card
50674	2025-12-24	CUST-1039	Credit Card
50675	2024-01-05	CUST-1040	Debit Card
50676	2024-01-07	CUST-1040	Credit Card
50677	2024-05-02	CUST-1040	Debit Card
50678	2024-05-17	CUST-1040	Credit Card
50679	2024-06-12	CUST-1040	Debit Card
50680	2024-10-12	CUST-1040	Paypal
50681	2024-12-15	CUST-1040	Debit Card
50682	2025-02-23	CUST-1040	Credit Card
50683	2025-08-11	CUST-1040	Paypal
50684	2025-08-24	CUST-1040	Cash
50685	2025-11-12	CUST-1040	Debit Card
50686	2024-10-14	CUST-1041	Paypal
50687	2024-10-26	CUST-1041	Credit Card
50688	2025-11-15	CUST-1041	Credit Card
50689	2025-11-23	CUST-1041	Debit Card
50690	2024-01-11	CUST-1042	Credit Card
50691	2024-01-16	CUST-1042	Cash
50692	2024-02-02	CUST-1042	Credit Card
50693	2024-02-27	CUST-1042	Credit Card
50694	2024-03-06	CUST-1042	Credit Card
50695	2024-03-12	CUST-1042	Credit Card
50696	2024-03-13	CUST-1042	Debit Card
50697	2024-03-18	CUST-1042	Paypal
50698	2024-03-20	CUST-1042	Debit Card
50699	2024-04-07	CUST-1042	Credit Card
50700	2024-04-28	CUST-1042	Credit Card
50701	2024-05-27	CUST-1042	Credit Card
50702	2024-06-04	CUST-1042	Paypal
50703	2024-06-25	CUST-1042	Debit Card
50704	2024-07-09	CUST-1042	Cash
50705	2024-07-23	CUST-1042	Debit Card
50706	2024-08-14	CUST-1042	Debit Card
50707	2024-08-18	CUST-1042	Cash
50708	2024-08-23	CUST-1042	Paypal
50709	2024-09-02	CUST-1042	Debit Card
50710	2024-09-12	CUST-1042	Credit Card
50711	2024-09-26	CUST-1042	Debit Card
50712	2024-10-30	CUST-1042	Debit Card
50713	2024-11-03	CUST-1042	Debit Card
50714	2024-11-18	CUST-1042	Credit Card
50715	2024-11-20	CUST-1042	Debit Card
50716	2024-11-22	CUST-1042	Credit Card
50717	2025-01-29	CUST-1042	Debit Card
50718	2025-02-05	CUST-1042	Debit Card
50719	2025-04-10	CUST-1042	Debit Card
50720	2025-04-28	CUST-1042	Paypal
50721	2025-05-11	CUST-1042	Credit Card
50722	2025-05-15	CUST-1042	Cash
50723	2025-05-26	CUST-1042	Cash
50724	2025-06-02	CUST-1042	Cash
50725	2025-06-16	CUST-1042	Credit Card
50726	2025-06-19	CUST-1042	Paypal
50727	2025-06-27	CUST-1042	Credit Card
50728	2025-07-20	CUST-1042	Debit Card
50729	2025-07-23	CUST-1042	Debit Card
50730	2025-07-31	CUST-1042	Debit Card
50731	2025-08-07	CUST-1042	Credit Card
50732	2025-08-09	CUST-1042	Debit Card
50733	2025-09-03	CUST-1042	Cash
50734	2025-09-18	CUST-1042	Credit Card
50735	2025-09-18	CUST-1042	Debit Card
50736	2025-09-30	CUST-1042	Paypal
50737	2025-10-22	CUST-1042	Credit Card
50738	2025-11-06	CUST-1042	Credit Card
50739	2025-11-13	CUST-1042	Credit Card
50740	2025-11-20	CUST-1042	Credit Card
50741	2025-11-20	CUST-1042	Debit Card
50742	2025-12-08	CUST-1042	Debit Card
50743	2025-12-27	CUST-1042	Debit Card
50744	2025-12-29	CUST-1042	Paypal
50745	2024-07-05	CUST-1043	Credit Card
50746	2024-07-24	CUST-1043	Debit Card
50747	2024-07-27	CUST-1043	Credit Card
50748	2024-09-15	CUST-1043	Paypal
50749	2025-05-19	CUST-1043	Paypal
50750	2025-06-09	CUST-1043	Credit Card
50751	2025-07-18	CUST-1043	Debit Card
50752	2024-02-15	CUST-1044	Cash
50753	2024-03-16	CUST-1044	Credit Card
50754	2024-05-31	CUST-1044	Credit Card
50755	2024-09-13	CUST-1044	Paypal
50756	2024-11-21	CUST-1044	Credit Card
50757	2024-12-26	CUST-1044	Debit Card
50758	2025-04-06	CUST-1044	Paypal
50759	2025-05-29	CUST-1044	Debit Card
50760	2025-06-23	CUST-1044	Cash
50761	2025-07-14	CUST-1044	Paypal
50762	2025-08-11	CUST-1044	Debit Card
50763	2025-09-13	CUST-1044	Paypal
50764	2025-09-20	CUST-1044	Credit Card
50765	2025-09-30	CUST-1044	Credit Card
50766	2025-12-08	CUST-1044	Debit Card
50767	2024-01-29	CUST-1045	Credit Card
50768	2024-02-24	CUST-1045	Credit Card
50769	2024-03-30	CUST-1045	Paypal
50770	2024-04-01	CUST-1045	Credit Card
50771	2024-05-13	CUST-1045	Credit Card
50772	2024-08-19	CUST-1045	Debit Card
50773	2024-09-19	CUST-1045	Credit Card
50774	2024-11-17	CUST-1045	Debit Card
50775	2024-12-12	CUST-1045	Credit Card
50776	2025-03-27	CUST-1045	Debit Card
50777	2025-04-25	CUST-1045	Credit Card
50778	2025-08-15	CUST-1045	Credit Card
50779	2025-08-26	CUST-1045	Cash
50780	2025-08-31	CUST-1045	Debit Card
50781	2025-09-07	CUST-1045	Credit Card
50782	2025-11-08	CUST-1045	Debit Card
50783	2025-11-22	CUST-1045	Debit Card
50784	2025-12-26	CUST-1045	Credit Card
50785	2024-06-02	CUST-1046	Credit Card
50786	2024-10-02	CUST-1046	Credit Card
50787	2025-05-27	CUST-1046	Paypal
50788	2025-06-28	CUST-1046	Credit Card
50789	2025-11-28	CUST-1046	Credit Card
50790	2024-01-31	CUST-1047	Debit Card
50791	2024-03-02	CUST-1047	Debit Card
50792	2024-03-16	CUST-1047	Debit Card
50793	2024-03-30	CUST-1047	Debit Card
50794	2024-06-17	CUST-1047	Paypal
50795	2024-06-22	CUST-1047	Credit Card
50796	2024-07-07	CUST-1047	Credit Card
50797	2024-10-02	CUST-1047	Paypal
50798	2024-10-11	CUST-1047	Paypal
50799	2024-10-17	CUST-1047	Paypal
50800	2024-10-19	CUST-1047	Debit Card
50801	2024-10-24	CUST-1047	Credit Card
50802	2024-11-25	CUST-1047	Credit Card
50803	2024-12-27	CUST-1047	Cash
50804	2024-12-29	CUST-1047	Credit Card
50805	2025-01-31	CUST-1047	Debit Card
50806	2025-02-05	CUST-1047	Paypal
50807	2025-03-10	CUST-1047	Cash
50808	2025-03-25	CUST-1047	Debit Card
50809	2025-05-05	CUST-1047	Credit Card
50810	2025-07-04	CUST-1047	Debit Card
50811	2025-07-24	CUST-1047	Credit Card
50812	2025-10-06	CUST-1047	Debit Card
50813	2025-10-12	CUST-1047	Credit Card
50814	2024-05-03	CUST-1048	Debit Card
50815	2024-10-09	CUST-1048	Cash
50816	2025-04-02	CUST-1048	Cash
50817	2025-04-07	CUST-1048	Debit Card
50818	2024-03-25	CUST-1049	Paypal
50819	2024-05-10	CUST-1049	Credit Card
50820	2024-07-28	CUST-1049	Cash
50821	2024-10-26	CUST-1049	Credit Card
50822	2024-11-13	CUST-1049	Debit Card
50823	2024-12-03	CUST-1049	Debit Card
50824	2025-03-21	CUST-1049	Cash
50825	2025-07-02	CUST-1049	Credit Card
50826	2025-07-15	CUST-1049	Cash
50827	2025-10-03	CUST-1049	Paypal
50828	2025-11-25	CUST-1049	Credit Card
50829	2025-12-16	CUST-1049	Debit Card
50830	2024-01-07	CUST-1050	Credit Card
50831	2024-01-23	CUST-1050	Debit Card
50832	2024-01-24	CUST-1050	Debit Card
50833	2024-01-28	CUST-1050	Debit Card
50834	2024-02-02	CUST-1050	Debit Card
50835	2024-03-08	CUST-1050	Credit Card
50836	2024-04-01	CUST-1050	Credit Card
50837	2024-05-20	CUST-1050	Credit Card
50838	2024-06-29	CUST-1050	Credit Card
50839	2024-07-13	CUST-1050	Credit Card
50840	2024-07-24	CUST-1050	Credit Card
50841	2024-08-09	CUST-1050	Credit Card
50842	2024-08-12	CUST-1050	Credit Card
50843	2024-09-19	CUST-1050	Paypal
50844	2024-10-02	CUST-1050	Debit Card
50845	2024-10-06	CUST-1050	Debit Card
50846	2024-10-14	CUST-1050	Debit Card
50847	2024-10-22	CUST-1050	Paypal
50848	2024-11-15	CUST-1050	Credit Card
50849	2024-11-16	CUST-1050	Paypal
50850	2024-11-19	CUST-1050	Debit Card
50851	2024-11-24	CUST-1050	Paypal
50852	2024-12-11	CUST-1050	Credit Card
50853	2024-12-15	CUST-1050	Debit Card
50854	2024-12-25	CUST-1050	Debit Card
50855	2024-12-30	CUST-1050	Cash
50856	2025-01-05	CUST-1050	Paypal
50857	2025-01-09	CUST-1050	Cash
50858	2025-02-19	CUST-1050	Debit Card
50859	2025-04-15	CUST-1050	Credit Card
50860	2025-05-11	CUST-1050	Paypal
50861	2025-05-14	CUST-1050	Debit Card
50862	2025-05-24	CUST-1050	Credit Card
50863	2025-05-25	CUST-1050	Paypal
50864	2025-05-31	CUST-1050	Credit Card
50865	2025-06-01	CUST-1050	Debit Card
50866	2025-06-29	CUST-1050	Paypal
50867	2025-08-12	CUST-1050	Paypal
50868	2025-09-11	CUST-1050	Credit Card
50869	2025-10-03	CUST-1050	Paypal
50870	2025-10-12	CUST-1050	Debit Card
50871	2025-10-13	CUST-1050	Cash
50872	2025-10-19	CUST-1050	Credit Card
50873	2025-10-23	CUST-1050	Credit Card
50874	2025-11-21	CUST-1050	Debit Card
50875	2025-12-01	CUST-1050	Paypal
50876	2025-12-02	CUST-1050	Debit Card
50877	2025-12-11	CUST-1050	Credit Card
50878	2025-12-12	CUST-1050	Debit Card
50879	2025-12-18	CUST-1050	Debit Card
50880	2025-12-20	CUST-1050	Credit Card
50881	2025-12-31	CUST-1050	Credit Card
50882	2024-07-09	CUST-1051	Credit Card
50883	2024-08-26	CUST-1051	Debit Card
50884	2025-11-10	CUST-1051	Paypal
50885	2024-01-22	CUST-1053	Credit Card
50886	2024-02-16	CUST-1053	Debit Card
50887	2024-02-24	CUST-1053	Debit Card
50888	2024-03-12	CUST-1053	Credit Card
50889	2024-03-18	CUST-1053	Cash
50890	2024-03-22	CUST-1053	Credit Card
50891	2024-03-27	CUST-1053	Paypal
50892	2024-04-14	CUST-1053	Debit Card
50893	2024-04-21	CUST-1053	Paypal
50894	2024-05-14	CUST-1053	Credit Card
50895	2024-05-24	CUST-1053	Credit Card
50896	2024-05-27	CUST-1053	Debit Card
50897	2024-06-01	CUST-1053	Credit Card
50898	2024-06-02	CUST-1053	Debit Card
50899	2024-06-10	CUST-1053	Credit Card
50900	2024-06-22	CUST-1053	Paypal
50901	2024-07-28	CUST-1053	Cash
50902	2024-08-31	CUST-1053	Credit Card
50903	2024-09-15	CUST-1053	Credit Card
50904	2024-10-01	CUST-1053	Credit Card
50905	2024-10-12	CUST-1053	Credit Card
50906	2024-10-16	CUST-1053	Paypal
50907	2024-10-31	CUST-1053	Cash
50908	2024-11-17	CUST-1053	Credit Card
50909	2024-11-21	CUST-1053	Credit Card
50910	2024-11-22	CUST-1053	Credit Card
50911	2024-11-26	CUST-1053	Paypal
50912	2024-11-28	CUST-1053	Debit Card
50913	2024-12-11	CUST-1053	Debit Card
50914	2024-12-22	CUST-1053	Credit Card
50915	2025-01-14	CUST-1053	Debit Card
50916	2025-01-26	CUST-1053	Debit Card
50917	2025-01-30	CUST-1053	Credit Card
50918	2025-02-26	CUST-1053	Debit Card
50919	2025-03-16	CUST-1053	Credit Card
50920	2025-04-29	CUST-1053	Credit Card
50921	2025-05-04	CUST-1053	Paypal
50922	2025-06-10	CUST-1053	Credit Card
50923	2025-06-17	CUST-1053	Cash
50924	2025-07-29	CUST-1053	Credit Card
50925	2025-08-07	CUST-1053	Debit Card
50926	2025-08-23	CUST-1053	Credit Card
50927	2025-09-02	CUST-1053	Debit Card
50928	2025-09-03	CUST-1053	Credit Card
50929	2025-09-30	CUST-1053	Credit Card
50930	2025-10-01	CUST-1053	Credit Card
50931	2025-10-03	CUST-1053	Debit Card
50932	2025-10-08	CUST-1053	Credit Card
50933	2025-10-14	CUST-1053	Credit Card
50934	2025-10-28	CUST-1053	Credit Card
50935	2025-10-29	CUST-1053	Debit Card
50936	2025-11-05	CUST-1053	Paypal
50937	2025-11-06	CUST-1053	Paypal
50938	2025-11-15	CUST-1053	Debit Card
50939	2025-11-29	CUST-1053	Debit Card
50940	2025-11-30	CUST-1053	Credit Card
50941	2025-12-01	CUST-1053	Debit Card
50942	2025-12-10	CUST-1053	Credit Card
50943	2025-12-25	CUST-1053	Credit Card
50944	2025-12-25	CUST-1053	Debit Card
50945	2025-12-27	CUST-1053	Credit Card
50946	2025-12-30	CUST-1053	Credit Card
50947	2024-01-22	CUST-1054	Credit Card
50948	2024-02-01	CUST-1054	Cash
50949	2024-02-10	CUST-1054	Debit Card
50950	2024-02-16	CUST-1054	Credit Card
50951	2024-02-21	CUST-1054	Debit Card
50952	2024-02-26	CUST-1054	Debit Card
50953	2024-03-06	CUST-1054	Debit Card
50954	2024-03-29	CUST-1054	Credit Card
50955	2024-04-06	CUST-1054	Debit Card
50956	2024-04-06	CUST-1054	Paypal
50957	2024-04-11	CUST-1054	Credit Card
50958	2024-04-24	CUST-1054	Credit Card
50959	2024-05-06	CUST-1054	Cash
50960	2024-05-08	CUST-1054	Credit Card
50961	2024-05-11	CUST-1054	Cash
50962	2024-05-14	CUST-1054	Credit Card
50963	2024-05-20	CUST-1054	Cash
50964	2024-05-21	CUST-1054	Cash
50965	2024-05-29	CUST-1054	Cash
50966	2024-05-30	CUST-1054	Credit Card
50967	2024-06-01	CUST-1054	Cash
50968	2024-06-03	CUST-1054	Debit Card
50969	2024-06-05	CUST-1054	Credit Card
50970	2024-06-14	CUST-1054	Credit Card
50971	2024-06-14	CUST-1054	Debit Card
50972	2024-06-19	CUST-1054	Cash
50973	2024-06-22	CUST-1054	Credit Card
50974	2024-06-24	CUST-1054	Debit Card
50975	2024-07-02	CUST-1054	Debit Card
50976	2024-07-08	CUST-1054	Credit Card
50977	2024-07-09	CUST-1054	Debit Card
50978	2024-07-15	CUST-1054	Debit Card
50979	2024-07-17	CUST-1054	Debit Card
50980	2024-07-19	CUST-1054	Credit Card
50981	2024-07-22	CUST-1054	Credit Card
50982	2024-07-23	CUST-1054	Paypal
50983	2024-07-24	CUST-1054	Credit Card
50984	2024-07-25	CUST-1054	Debit Card
50985	2024-07-29	CUST-1054	Credit Card
50986	2024-07-30	CUST-1054	Debit Card
50987	2024-08-04	CUST-1054	Cash
50988	2024-08-15	CUST-1054	Credit Card
50989	2024-08-19	CUST-1054	Credit Card
50990	2024-08-20	CUST-1054	Credit Card
50991	2024-08-25	CUST-1054	Credit Card
50992	2024-08-26	CUST-1054	Credit Card
50993	2024-09-04	CUST-1054	Cash
50994	2024-09-05	CUST-1054	Credit Card
50995	2024-09-06	CUST-1054	Debit Card
50996	2024-09-12	CUST-1054	Cash
50997	2024-09-13	CUST-1054	Credit Card
50998	2024-09-18	CUST-1054	Paypal
50999	2024-09-21	CUST-1054	Debit Card
51000	2024-09-23	CUST-1054	Credit Card
51001	2024-09-25	CUST-1054	Cash
51002	2024-09-28	CUST-1054	Debit Card
51003	2024-10-11	CUST-1054	Credit Card
51004	2024-10-15	CUST-1054	Debit Card
51005	2024-10-24	CUST-1054	Credit Card
51006	2024-10-26	CUST-1054	Debit Card
51007	2024-10-29	CUST-1054	Credit Card
51008	2024-10-31	CUST-1054	Debit Card
51009	2024-11-02	CUST-1054	Credit Card
51010	2024-11-02	CUST-1054	Debit Card
51011	2024-11-06	CUST-1054	Debit Card
51012	2024-11-10	CUST-1054	Cash
51013	2024-11-11	CUST-1054	Debit Card
51014	2024-11-14	CUST-1054	Debit Card
51015	2024-11-17	CUST-1054	Debit Card
51016	2024-11-20	CUST-1054	Debit Card
51017	2024-11-21	CUST-1054	Paypal
51018	2024-11-23	CUST-1054	Debit Card
51019	2024-12-05	CUST-1054	Paypal
51020	2024-12-06	CUST-1054	Credit Card
51021	2024-12-09	CUST-1054	Credit Card
51022	2024-12-12	CUST-1054	Debit Card
51023	2024-12-13	CUST-1054	Credit Card
51024	2024-12-18	CUST-1054	Paypal
51025	2024-12-19	CUST-1054	Credit Card
51026	2024-12-21	CUST-1054	Cash
51027	2024-12-23	CUST-1054	Credit Card
51028	2024-12-25	CUST-1054	Credit Card
51029	2024-12-26	CUST-1054	Paypal
51030	2024-12-27	CUST-1054	Cash
51031	2024-12-31	CUST-1054	Credit Card
51032	2025-01-08	CUST-1054	Credit Card
51033	2025-01-10	CUST-1054	Debit Card
51034	2025-01-14	CUST-1054	Debit Card
51035	2025-01-18	CUST-1054	Paypal
51036	2025-01-21	CUST-1054	Debit Card
51037	2025-01-28	CUST-1054	Cash
51038	2025-02-03	CUST-1054	Credit Card
51039	2025-02-15	CUST-1054	Credit Card
51040	2025-02-24	CUST-1054	Paypal
51041	2025-03-08	CUST-1054	Credit Card
51042	2025-03-12	CUST-1054	Credit Card
51043	2025-03-19	CUST-1054	Cash
51044	2025-03-24	CUST-1054	Cash
51045	2025-03-25	CUST-1054	Credit Card
51046	2025-03-25	CUST-1054	Paypal
51047	2025-03-29	CUST-1054	Credit Card
51048	2025-04-03	CUST-1054	Debit Card
51049	2025-04-08	CUST-1054	Paypal
51050	2025-04-11	CUST-1054	Paypal
51051	2025-04-21	CUST-1054	Credit Card
51052	2025-04-24	CUST-1054	Debit Card
51053	2025-04-25	CUST-1054	Debit Card
51054	2025-05-04	CUST-1054	Credit Card
51055	2025-05-08	CUST-1054	Credit Card
51056	2025-05-08	CUST-1054	Debit Card
51057	2025-05-09	CUST-1054	Paypal
51058	2025-05-11	CUST-1054	Credit Card
51059	2025-05-23	CUST-1054	Debit Card
51060	2025-05-25	CUST-1054	Credit Card
51061	2025-06-03	CUST-1054	Paypal
51062	2025-06-07	CUST-1054	Credit Card
51063	2025-06-08	CUST-1054	Debit Card
51064	2025-06-12	CUST-1054	Paypal
51065	2025-06-13	CUST-1054	Paypal
51066	2025-06-23	CUST-1054	Debit Card
51067	2025-06-26	CUST-1054	Cash
51068	2025-06-27	CUST-1054	Credit Card
51069	2025-07-01	CUST-1054	Cash
51070	2025-07-07	CUST-1054	Debit Card
51071	2025-07-14	CUST-1054	Debit Card
51072	2025-07-27	CUST-1054	Cash
51073	2025-08-17	CUST-1054	Debit Card
51074	2025-08-19	CUST-1054	Credit Card
51075	2025-08-19	CUST-1054	Debit Card
51076	2025-08-23	CUST-1054	Credit Card
51077	2025-09-10	CUST-1054	Credit Card
51078	2025-09-14	CUST-1054	Paypal
51079	2025-09-20	CUST-1054	Cash
51080	2025-09-26	CUST-1054	Credit Card
51081	2025-09-26	CUST-1054	Paypal
51082	2025-09-28	CUST-1054	Credit Card
51083	2025-09-29	CUST-1054	Paypal
51084	2025-10-02	CUST-1054	Cash
51085	2025-10-02	CUST-1054	Credit Card
51086	2025-10-04	CUST-1054	Credit Card
51087	2025-10-05	CUST-1054	Debit Card
51088	2025-10-09	CUST-1054	Debit Card
51089	2025-10-15	CUST-1054	Debit Card
51090	2025-10-17	CUST-1054	Credit Card
51091	2025-10-21	CUST-1054	Credit Card
51092	2025-11-01	CUST-1054	Credit Card
51093	2025-11-02	CUST-1054	Cash
51094	2025-11-05	CUST-1054	Paypal
51095	2025-11-17	CUST-1054	Debit Card
51096	2025-11-18	CUST-1054	Cash
51097	2025-11-24	CUST-1054	Debit Card
51098	2025-11-24	CUST-1054	Paypal
51099	2025-11-25	CUST-1054	Debit Card
51100	2025-12-03	CUST-1054	Credit Card
51101	2025-12-04	CUST-1054	Credit Card
51102	2025-12-05	CUST-1054	Credit Card
51103	2025-12-10	CUST-1054	Credit Card
51104	2025-12-11	CUST-1054	Cash
51105	2025-12-11	CUST-1054	Paypal
51106	2025-12-26	CUST-1054	Cash
51107	2025-12-28	CUST-1054	Debit Card
51108	2025-12-31	CUST-1054	Credit Card
51109	2024-12-04	CUST-1055	Credit Card
51110	2024-12-14	CUST-1055	Credit Card
51111	2025-02-20	CUST-1055	Credit Card
51112	2025-04-10	CUST-1055	Paypal
51113	2025-05-18	CUST-1055	Credit Card
51114	2025-06-08	CUST-1055	Credit Card
51115	2025-07-06	CUST-1055	Debit Card
51116	2025-08-09	CUST-1055	Credit Card
51117	2024-02-19	CUST-1056	Debit Card
51118	2024-05-08	CUST-1057	Paypal
51119	2024-06-29	CUST-1057	Credit Card
51120	2024-08-22	CUST-1057	Paypal
51121	2024-09-27	CUST-1057	Paypal
51122	2024-11-09	CUST-1057	Debit Card
51123	2024-11-12	CUST-1057	Paypal
51124	2025-01-30	CUST-1057	Paypal
51125	2025-02-03	CUST-1057	Cash
51126	2025-05-02	CUST-1057	Credit Card
51127	2025-06-02	CUST-1057	Debit Card
51128	2025-07-01	CUST-1057	Credit Card
51129	2024-01-27	CUST-1058	Debit Card
51130	2024-03-11	CUST-1058	Credit Card
51131	2024-05-31	CUST-1058	Credit Card
51132	2024-07-01	CUST-1058	Paypal
51133	2024-07-10	CUST-1058	Paypal
51134	2024-07-26	CUST-1058	Credit Card
51135	2024-07-29	CUST-1058	Debit Card
51136	2024-10-20	CUST-1058	Debit Card
51137	2024-11-26	CUST-1058	Cash
51138	2025-03-05	CUST-1058	Credit Card
51139	2025-04-10	CUST-1058	Debit Card
51140	2025-07-01	CUST-1058	Paypal
51141	2025-10-08	CUST-1058	Paypal
51142	2025-11-25	CUST-1058	Credit Card
51143	2024-03-07	CUST-1059	Debit Card
51144	2024-07-16	CUST-1059	Debit Card
51145	2025-01-10	CUST-1059	Credit Card
51146	2025-05-13	CUST-1059	Paypal
51147	2025-06-08	CUST-1059	Credit Card
51148	2025-06-14	CUST-1059	Credit Card
51149	2024-03-14	CUST-1060	Debit Card
51150	2024-08-20	CUST-1060	Cash
51151	2025-06-28	CUST-1060	Credit Card
51152	2025-08-13	CUST-1060	Credit Card
51153	2025-11-15	CUST-1060	Debit Card
51154	2024-03-08	CUST-1061	Credit Card
51155	2024-04-14	CUST-1061	Paypal
51156	2024-08-14	CUST-1061	Debit Card
51157	2024-09-08	CUST-1061	Credit Card
51158	2024-09-27	CUST-1061	Debit Card
51159	2024-10-14	CUST-1061	Cash
51160	2024-10-17	CUST-1061	Debit Card
51161	2024-10-27	CUST-1061	Credit Card
51162	2024-11-06	CUST-1061	Debit Card
51163	2024-11-27	CUST-1061	Debit Card
51164	2025-02-17	CUST-1061	Cash
51165	2025-03-01	CUST-1061	Credit Card
51166	2025-03-10	CUST-1061	Credit Card
51167	2025-03-13	CUST-1061	Debit Card
51168	2025-03-22	CUST-1061	Credit Card
51169	2025-03-23	CUST-1061	Credit Card
51170	2025-04-20	CUST-1061	Credit Card
51171	2025-04-24	CUST-1061	Paypal
51172	2025-05-09	CUST-1061	Credit Card
51173	2025-06-07	CUST-1061	Credit Card
51174	2025-06-10	CUST-1061	Paypal
51175	2025-07-12	CUST-1061	Debit Card
51176	2025-07-18	CUST-1061	Credit Card
51177	2025-09-22	CUST-1061	Credit Card
51178	2025-09-26	CUST-1061	Credit Card
51179	2025-10-23	CUST-1061	Debit Card
51180	2025-11-29	CUST-1061	Credit Card
51181	2025-12-31	CUST-1061	Cash
51182	2024-02-09	CUST-1062	Debit Card
51183	2024-03-06	CUST-1062	Cash
51184	2024-03-07	CUST-1062	Credit Card
51185	2024-03-08	CUST-1062	Cash
51186	2024-03-16	CUST-1062	Debit Card
51187	2024-05-23	CUST-1062	Paypal
51188	2024-07-13	CUST-1062	Debit Card
51189	2024-07-20	CUST-1062	Credit Card
51190	2024-09-27	CUST-1062	Credit Card
51191	2024-09-29	CUST-1062	Credit Card
51192	2024-10-31	CUST-1062	Debit Card
51193	2025-01-29	CUST-1062	Debit Card
51194	2025-03-10	CUST-1062	Credit Card
51195	2025-03-21	CUST-1062	Debit Card
51196	2025-05-28	CUST-1062	Credit Card
51197	2025-08-02	CUST-1062	Cash
51198	2025-10-27	CUST-1062	Debit Card
51199	2025-10-30	CUST-1062	Credit Card
51200	2025-12-04	CUST-1062	Credit Card
51201	2025-12-29	CUST-1062	Credit Card
51202	2024-12-24	CUST-1063	Credit Card
51203	2025-09-06	CUST-1063	Paypal
51204	2025-12-14	CUST-1063	Debit Card
51205	2024-01-23	CUST-1064	Credit Card
51206	2024-01-31	CUST-1064	Credit Card
51207	2024-02-16	CUST-1064	Debit Card
51208	2024-09-23	CUST-1064	Credit Card
51209	2024-10-01	CUST-1064	Paypal
51210	2024-11-19	CUST-1064	Credit Card
51211	2024-11-21	CUST-1064	Credit Card
51212	2024-12-29	CUST-1064	Credit Card
51213	2025-02-04	CUST-1064	Credit Card
51214	2025-05-05	CUST-1064	Debit Card
51215	2025-06-05	CUST-1064	Credit Card
51216	2025-07-01	CUST-1064	Credit Card
51217	2025-07-14	CUST-1064	Debit Card
51218	2025-08-04	CUST-1064	Cash
51219	2025-09-02	CUST-1064	Debit Card
51220	2025-09-02	CUST-1064	Paypal
51221	2025-10-17	CUST-1064	Paypal
51222	2025-11-29	CUST-1064	Debit Card
51223	2025-12-14	CUST-1064	Credit Card
51224	2024-01-02	CUST-1065	Cash
51225	2024-01-03	CUST-1065	Paypal
51226	2024-01-18	CUST-1065	Paypal
51227	2024-01-22	CUST-1065	Credit Card
51228	2024-02-19	CUST-1065	Credit Card
51229	2024-02-20	CUST-1065	Paypal
51230	2024-04-23	CUST-1065	Paypal
51231	2024-04-27	CUST-1065	Cash
51232	2024-05-07	CUST-1065	Credit Card
51233	2024-05-19	CUST-1065	Credit Card
51234	2024-05-27	CUST-1065	Credit Card
51235	2024-06-01	CUST-1065	Paypal
51236	2024-06-16	CUST-1065	Credit Card
51237	2024-06-17	CUST-1065	Credit Card
51238	2024-06-25	CUST-1065	Credit Card
51239	2024-07-01	CUST-1065	Credit Card
51240	2024-07-06	CUST-1065	Cash
51241	2024-07-10	CUST-1065	Debit Card
51242	2024-07-12	CUST-1065	Credit Card
51243	2024-07-17	CUST-1065	Paypal
51244	2024-07-25	CUST-1065	Credit Card
51245	2024-07-28	CUST-1065	Credit Card
51246	2024-08-13	CUST-1065	Credit Card
51247	2024-09-04	CUST-1065	Debit Card
51248	2024-09-05	CUST-1065	Credit Card
51249	2024-09-05	CUST-1065	Debit Card
51250	2024-09-06	CUST-1065	Debit Card
51251	2024-09-07	CUST-1065	Credit Card
51252	2024-09-09	CUST-1065	Cash
51253	2024-09-10	CUST-1065	Credit Card
51254	2024-09-16	CUST-1065	Credit Card
51255	2024-09-20	CUST-1065	Credit Card
51256	2024-10-10	CUST-1065	Debit Card
51257	2024-10-18	CUST-1065	Debit Card
51258	2024-10-22	CUST-1065	Credit Card
51259	2024-10-29	CUST-1065	Credit Card
51260	2024-10-30	CUST-1065	Debit Card
51261	2024-11-09	CUST-1065	Credit Card
51262	2024-11-23	CUST-1065	Cash
51263	2024-11-23	CUST-1065	Debit Card
51264	2024-11-26	CUST-1065	Credit Card
51265	2024-11-27	CUST-1065	Cash
51266	2024-12-02	CUST-1065	Credit Card
51267	2024-12-03	CUST-1065	Credit Card
51268	2024-12-08	CUST-1065	Credit Card
51269	2024-12-08	CUST-1065	Debit Card
51270	2024-12-10	CUST-1065	Debit Card
51271	2024-12-11	CUST-1065	Credit Card
51272	2024-12-13	CUST-1065	Paypal
51273	2024-12-28	CUST-1065	Debit Card
51274	2024-12-31	CUST-1065	Credit Card
51275	2025-01-03	CUST-1065	Cash
51276	2025-01-20	CUST-1065	Cash
51277	2025-02-08	CUST-1065	Credit Card
51278	2025-03-09	CUST-1065	Cash
51279	2025-03-13	CUST-1065	Paypal
51280	2025-04-07	CUST-1065	Credit Card
51281	2025-04-09	CUST-1065	Debit Card
51282	2025-04-13	CUST-1065	Cash
51283	2025-04-13	CUST-1065	Debit Card
51284	2025-04-21	CUST-1065	Debit Card
51285	2025-04-30	CUST-1065	Paypal
51286	2025-05-02	CUST-1065	Debit Card
51287	2025-05-05	CUST-1065	Credit Card
51288	2025-05-08	CUST-1065	Credit Card
51289	2025-05-10	CUST-1065	Debit Card
51290	2025-05-26	CUST-1065	Credit Card
51291	2025-06-07	CUST-1065	Credit Card
51292	2025-06-19	CUST-1065	Credit Card
51293	2025-06-21	CUST-1065	Paypal
51294	2025-06-25	CUST-1065	Credit Card
51295	2025-07-08	CUST-1065	Cash
51296	2025-08-05	CUST-1065	Debit Card
51297	2025-08-12	CUST-1065	Credit Card
51298	2025-08-20	CUST-1065	Debit Card
51299	2025-08-31	CUST-1065	Paypal
51300	2025-09-12	CUST-1065	Credit Card
51301	2025-09-15	CUST-1065	Cash
51302	2025-09-17	CUST-1065	Credit Card
51303	2025-09-18	CUST-1065	Cash
51304	2025-09-28	CUST-1065	Credit Card
51305	2025-10-24	CUST-1065	Cash
51306	2025-10-24	CUST-1065	Credit Card
51307	2025-10-24	CUST-1065	Paypal
51308	2025-11-01	CUST-1065	Cash
51309	2025-11-09	CUST-1065	Credit Card
51310	2025-11-14	CUST-1065	Paypal
51311	2025-11-18	CUST-1065	Credit Card
51312	2025-11-20	CUST-1065	Paypal
51313	2025-11-21	CUST-1065	Credit Card
51314	2025-11-27	CUST-1065	Credit Card
51315	2025-11-27	CUST-1065	Paypal
51316	2025-12-02	CUST-1065	Credit Card
51317	2025-12-03	CUST-1065	Cash
51318	2025-12-07	CUST-1065	Cash
51319	2025-12-09	CUST-1065	Credit Card
51320	2025-12-14	CUST-1065	Credit Card
51321	2025-12-16	CUST-1065	Credit Card
51322	2025-12-17	CUST-1065	Cash
51323	2025-12-20	CUST-1065	Credit Card
51324	2025-12-25	CUST-1065	Credit Card
51325	2025-12-28	CUST-1065	Credit Card
51326	2025-12-28	CUST-1065	Debit Card
51327	2025-12-30	CUST-1065	Debit Card
51328	2024-05-21	CUST-1066	Cash
51329	2024-06-14	CUST-1066	Credit Card
51330	2024-06-23	CUST-1066	Paypal
51331	2024-09-02	CUST-1066	Credit Card
51332	2024-09-26	CUST-1066	Paypal
51333	2024-12-14	CUST-1066	Credit Card
51334	2025-01-02	CUST-1066	Debit Card
51335	2025-04-26	CUST-1066	Paypal
51336	2025-04-27	CUST-1066	Cash
51337	2025-05-01	CUST-1066	Credit Card
51338	2025-07-23	CUST-1066	Debit Card
51339	2025-10-19	CUST-1066	Cash
51340	2025-11-24	CUST-1066	Credit Card
51341	2024-02-24	CUST-1067	Paypal
51342	2024-09-14	CUST-1067	Debit Card
51343	2024-10-22	CUST-1067	Debit Card
51344	2024-11-12	CUST-1067	Credit Card
51345	2024-12-27	CUST-1067	Credit Card
51346	2025-04-12	CUST-1067	Credit Card
51347	2025-04-23	CUST-1067	Debit Card
51348	2025-07-02	CUST-1067	Credit Card
51349	2025-10-08	CUST-1067	Credit Card
51350	2025-10-25	CUST-1067	Debit Card
51351	2024-02-09	CUST-1068	Credit Card
51352	2024-07-24	CUST-1068	Debit Card
51353	2024-08-29	CUST-1068	Debit Card
51354	2024-11-22	CUST-1068	Debit Card
51355	2024-12-02	CUST-1068	Credit Card
51356	2024-12-08	CUST-1068	Cash
51357	2024-12-20	CUST-1068	Debit Card
51358	2025-03-05	CUST-1068	Credit Card
51359	2025-06-10	CUST-1068	Debit Card
51360	2025-10-19	CUST-1068	Debit Card
51361	2025-11-19	CUST-1068	Paypal
51362	2024-03-04	CUST-1069	Credit Card
51363	2024-03-24	CUST-1069	Cash
51364	2024-05-12	CUST-1069	Paypal
51365	2024-07-07	CUST-1069	Paypal
51366	2024-07-24	CUST-1069	Debit Card
51367	2024-09-12	CUST-1069	Cash
51368	2025-01-04	CUST-1069	Paypal
51369	2025-02-05	CUST-1069	Credit Card
51370	2025-03-29	CUST-1069	Credit Card
51371	2025-04-18	CUST-1069	Paypal
51372	2025-06-29	CUST-1069	Credit Card
51373	2025-07-02	CUST-1069	Credit Card
51374	2025-07-10	CUST-1069	Cash
51375	2025-07-22	CUST-1069	Paypal
51376	2025-08-21	CUST-1069	Cash
51377	2025-09-13	CUST-1069	Credit Card
51378	2025-09-14	CUST-1069	Debit Card
51379	2025-09-18	CUST-1069	Debit Card
51380	2025-10-21	CUST-1069	Credit Card
51381	2025-10-28	CUST-1069	Cash
51382	2025-11-09	CUST-1069	Paypal
51383	2025-11-12	CUST-1069	Credit Card
51384	2025-11-19	CUST-1069	Cash
51385	2025-11-27	CUST-1069	Cash
51386	2024-02-17	CUST-1071	Credit Card
51387	2024-03-13	CUST-1071	Credit Card
51388	2024-03-22	CUST-1071	Paypal
51389	2024-04-26	CUST-1071	Credit Card
51390	2024-05-22	CUST-1071	Debit Card
51391	2024-07-09	CUST-1071	Debit Card
51392	2024-07-22	CUST-1071	Debit Card
51393	2024-07-23	CUST-1071	Credit Card
51394	2024-08-23	CUST-1071	Credit Card
51395	2024-12-15	CUST-1071	Credit Card
51396	2025-04-12	CUST-1071	Credit Card
51397	2025-05-31	CUST-1071	Debit Card
51398	2025-08-04	CUST-1071	Paypal
51399	2025-09-18	CUST-1071	Credit Card
51400	2025-09-20	CUST-1071	Debit Card
51401	2025-12-04	CUST-1071	Credit Card
51402	2025-12-06	CUST-1071	Debit Card
51403	2025-12-15	CUST-1071	Cash
51404	2025-12-20	CUST-1071	Cash
51405	2024-03-29	CUST-1072	Paypal
51406	2024-04-03	CUST-1072	Credit Card
51407	2024-08-22	CUST-1072	Credit Card
51408	2024-09-21	CUST-1072	Credit Card
51409	2024-09-24	CUST-1072	Paypal
51410	2024-12-03	CUST-1072	Credit Card
51411	2025-02-17	CUST-1072	Credit Card
51412	2025-12-19	CUST-1072	Credit Card
51413	2024-02-17	CUST-1073	Credit Card
51414	2024-03-08	CUST-1073	Credit Card
51415	2024-03-14	CUST-1073	Credit Card
51416	2024-04-06	CUST-1073	Credit Card
51417	2024-04-14	CUST-1073	Paypal
51418	2024-04-20	CUST-1073	Credit Card
51419	2024-04-28	CUST-1073	Cash
51420	2024-04-29	CUST-1073	Paypal
51421	2024-05-04	CUST-1073	Paypal
51422	2024-05-30	CUST-1073	Debit Card
51423	2024-06-02	CUST-1073	Paypal
51424	2024-06-06	CUST-1073	Credit Card
51425	2024-06-06	CUST-1073	Debit Card
51426	2024-06-12	CUST-1073	Credit Card
51427	2024-06-14	CUST-1073	Cash
51428	2024-06-24	CUST-1073	Debit Card
51429	2024-07-01	CUST-1073	Credit Card
51430	2024-07-13	CUST-1073	Debit Card
51431	2024-07-15	CUST-1073	Debit Card
51432	2024-08-06	CUST-1073	Debit Card
51433	2024-08-15	CUST-1073	Paypal
51434	2024-08-21	CUST-1073	Credit Card
51435	2024-09-05	CUST-1073	Cash
51436	2024-09-10	CUST-1073	Credit Card
51437	2024-09-13	CUST-1073	Credit Card
51438	2024-09-14	CUST-1073	Cash
51439	2024-09-19	CUST-1073	Debit Card
51440	2024-10-02	CUST-1073	Debit Card
51441	2024-10-15	CUST-1073	Cash
51442	2024-10-25	CUST-1073	Cash
51443	2024-10-31	CUST-1073	Paypal
51444	2024-11-02	CUST-1073	Debit Card
51445	2024-11-04	CUST-1073	Credit Card
51446	2024-11-08	CUST-1073	Paypal
51447	2024-11-18	CUST-1073	Debit Card
51448	2024-11-30	CUST-1073	Debit Card
51449	2024-12-08	CUST-1073	Credit Card
51450	2024-12-17	CUST-1073	Debit Card
51451	2024-12-24	CUST-1073	Debit Card
51452	2024-12-27	CUST-1073	Debit Card
51453	2024-12-31	CUST-1073	Debit Card
51454	2025-02-07	CUST-1073	Credit Card
51455	2025-02-08	CUST-1073	Credit Card
51456	2025-02-12	CUST-1073	Debit Card
51457	2025-02-20	CUST-1073	Debit Card
51458	2025-02-20	CUST-1073	Paypal
51459	2025-03-11	CUST-1073	Cash
51460	2025-03-22	CUST-1073	Paypal
51461	2025-03-30	CUST-1073	Credit Card
51462	2025-04-07	CUST-1073	Cash
51463	2025-04-12	CUST-1073	Debit Card
51464	2025-04-19	CUST-1073	Credit Card
51465	2025-04-25	CUST-1073	Cash
51466	2025-04-29	CUST-1073	Credit Card
51467	2025-05-02	CUST-1073	Paypal
51468	2025-05-20	CUST-1073	Credit Card
51469	2025-06-07	CUST-1073	Paypal
51470	2025-06-15	CUST-1073	Debit Card
51471	2025-06-21	CUST-1073	Debit Card
51472	2025-06-22	CUST-1073	Debit Card
51473	2025-07-04	CUST-1073	Cash
51474	2025-07-04	CUST-1073	Debit Card
51475	2025-07-16	CUST-1073	Cash
51476	2025-08-13	CUST-1073	Cash
51477	2025-08-15	CUST-1073	Credit Card
51478	2025-08-16	CUST-1073	Debit Card
51479	2025-09-05	CUST-1073	Debit Card
51480	2025-09-09	CUST-1073	Credit Card
51481	2025-09-15	CUST-1073	Paypal
51482	2025-09-17	CUST-1073	Credit Card
51483	2025-09-18	CUST-1073	Cash
51484	2025-09-30	CUST-1073	Cash
51485	2025-10-01	CUST-1073	Credit Card
51486	2025-10-24	CUST-1073	Credit Card
51487	2025-10-28	CUST-1073	Credit Card
51488	2025-10-30	CUST-1073	Cash
51489	2025-11-29	CUST-1073	Paypal
51490	2025-12-11	CUST-1073	Credit Card
51491	2025-12-23	CUST-1073	Debit Card
51492	2025-12-26	CUST-1073	Paypal
51493	2024-03-22	CUST-1074	Credit Card
51494	2024-04-06	CUST-1074	Credit Card
51495	2024-05-23	CUST-1074	Paypal
51496	2024-07-31	CUST-1074	Cash
51497	2024-08-04	CUST-1074	Debit Card
51498	2024-10-20	CUST-1074	Credit Card
51499	2024-10-31	CUST-1074	Credit Card
51500	2025-01-26	CUST-1074	Cash
51501	2025-03-14	CUST-1074	Credit Card
51502	2025-06-17	CUST-1074	Paypal
51503	2025-06-29	CUST-1074	Debit Card
51504	2025-10-16	CUST-1074	Credit Card
51505	2024-01-01	CUST-1075	Debit Card
51506	2024-03-31	CUST-1075	Credit Card
51507	2024-04-16	CUST-1075	Credit Card
51508	2024-04-19	CUST-1075	Debit Card
51509	2024-04-20	CUST-1075	Debit Card
51510	2024-04-25	CUST-1075	Debit Card
51511	2024-05-28	CUST-1075	Debit Card
51512	2024-06-02	CUST-1075	Paypal
51513	2024-06-04	CUST-1075	Credit Card
51514	2024-06-18	CUST-1075	Credit Card
51515	2024-06-21	CUST-1075	Debit Card
51516	2024-07-06	CUST-1075	Credit Card
51517	2024-07-10	CUST-1075	Credit Card
51518	2024-07-30	CUST-1075	Paypal
51519	2024-09-26	CUST-1075	Debit Card
51520	2024-10-02	CUST-1075	Paypal
51521	2024-10-16	CUST-1075	Credit Card
51522	2024-11-25	CUST-1075	Paypal
51523	2024-12-01	CUST-1075	Credit Card
51524	2024-12-04	CUST-1075	Credit Card
51525	2024-12-04	CUST-1075	Paypal
51526	2024-12-13	CUST-1075	Credit Card
51527	2024-12-20	CUST-1075	Credit Card
51528	2024-12-27	CUST-1075	Debit Card
51529	2025-01-12	CUST-1075	Credit Card
51530	2025-01-16	CUST-1075	Debit Card
51531	2025-01-31	CUST-1075	Paypal
51532	2025-02-05	CUST-1075	Cash
51533	2025-02-13	CUST-1075	Debit Card
51534	2025-02-16	CUST-1075	Credit Card
51535	2025-02-24	CUST-1075	Credit Card
51536	2025-02-28	CUST-1075	Debit Card
51537	2025-03-06	CUST-1075	Credit Card
51538	2025-03-14	CUST-1075	Cash
51539	2025-04-02	CUST-1075	Debit Card
51540	2025-04-12	CUST-1075	Debit Card
51541	2025-05-18	CUST-1075	Paypal
51542	2025-06-07	CUST-1075	Debit Card
51543	2025-06-12	CUST-1075	Debit Card
51544	2025-06-13	CUST-1075	Debit Card
51545	2025-07-08	CUST-1075	Debit Card
51546	2025-07-19	CUST-1075	Credit Card
51547	2025-07-30	CUST-1075	Credit Card
51548	2025-07-31	CUST-1075	Paypal
51549	2025-08-16	CUST-1075	Credit Card
51550	2025-08-21	CUST-1075	Debit Card
51551	2025-10-02	CUST-1075	Debit Card
51552	2025-10-15	CUST-1075	Credit Card
51553	2025-10-21	CUST-1075	Credit Card
51554	2025-10-22	CUST-1075	Credit Card
51555	2025-10-25	CUST-1075	Credit Card
51556	2025-10-27	CUST-1075	Credit Card
51557	2025-10-30	CUST-1075	Credit Card
51558	2025-10-31	CUST-1075	Credit Card
51559	2025-11-02	CUST-1075	Paypal
51560	2025-11-12	CUST-1075	Debit Card
51561	2025-11-14	CUST-1075	Credit Card
51562	2025-11-15	CUST-1075	Cash
51563	2025-11-16	CUST-1075	Debit Card
51564	2025-11-21	CUST-1075	Debit Card
51565	2025-11-24	CUST-1075	Paypal
51566	2025-11-26	CUST-1075	Credit Card
51567	2025-12-03	CUST-1075	Credit Card
51568	2025-12-23	CUST-1075	Cash
51569	2025-12-25	CUST-1075	Debit Card
51570	2025-12-31	CUST-1075	Credit Card
51571	2024-07-01	CUST-1076	Debit Card
51572	2024-12-19	CUST-1076	Cash
51573	2025-06-04	CUST-1076	Debit Card
51574	2025-11-02	CUST-1076	Debit Card
51575	2024-04-12	CUST-1077	Cash
51576	2024-04-12	CUST-1077	Debit Card
51577	2024-05-15	CUST-1077	Credit Card
51578	2024-06-30	CUST-1077	Debit Card
51579	2024-07-26	CUST-1077	Credit Card
51580	2024-09-03	CUST-1077	Credit Card
51581	2024-11-22	CUST-1077	Paypal
51582	2024-11-26	CUST-1077	Cash
51583	2024-12-14	CUST-1077	Credit Card
51584	2024-12-22	CUST-1077	Credit Card
51585	2025-03-31	CUST-1077	Debit Card
51586	2025-04-10	CUST-1077	Cash
51587	2025-05-11	CUST-1077	Debit Card
51588	2025-08-24	CUST-1077	Credit Card
51589	2025-10-19	CUST-1077	Credit Card
51590	2025-11-02	CUST-1077	Cash
51591	2025-11-29	CUST-1077	Debit Card
51592	2024-01-08	CUST-1078	Cash
51593	2024-01-23	CUST-1078	Paypal
51594	2024-08-20	CUST-1078	Credit Card
51595	2024-09-25	CUST-1078	Debit Card
51596	2024-11-08	CUST-1078	Cash
51597	2024-12-25	CUST-1078	Debit Card
51598	2024-12-31	CUST-1078	Paypal
51599	2025-02-01	CUST-1078	Debit Card
51600	2025-04-10	CUST-1078	Cash
51601	2025-05-19	CUST-1078	Cash
51602	2025-05-31	CUST-1078	Debit Card
51603	2025-06-20	CUST-1078	Debit Card
51604	2025-08-09	CUST-1078	Debit Card
51605	2025-09-01	CUST-1078	Credit Card
51606	2025-09-27	CUST-1078	Debit Card
51607	2025-10-16	CUST-1078	Credit Card
51608	2025-12-09	CUST-1078	Credit Card
51609	2025-12-29	CUST-1078	Cash
51610	2024-03-30	CUST-1079	Debit Card
51611	2024-08-12	CUST-1079	Debit Card
51612	2025-06-30	CUST-1079	Paypal
51613	2024-02-16	CUST-1080	Credit Card
51614	2024-03-09	CUST-1080	Credit Card
51615	2024-09-02	CUST-1080	Paypal
51616	2024-09-21	CUST-1080	Cash
51617	2024-10-27	CUST-1080	Paypal
51618	2024-11-24	CUST-1080	Debit Card
51619	2024-12-28	CUST-1080	Credit Card
51620	2025-04-19	CUST-1080	Credit Card
51621	2025-05-14	CUST-1080	Credit Card
51622	2025-06-16	CUST-1080	Cash
51623	2025-06-29	CUST-1080	Credit Card
51624	2025-12-04	CUST-1080	Cash
51625	2025-12-11	CUST-1080	Paypal
51626	2025-12-18	CUST-1080	Debit Card
51627	2025-12-22	CUST-1080	Cash
51628	2024-02-27	CUST-1081	Debit Card
51629	2024-03-06	CUST-1081	Credit Card
51630	2024-03-31	CUST-1081	Cash
51631	2024-04-02	CUST-1081	Cash
51632	2024-04-07	CUST-1081	Debit Card
51633	2024-04-22	CUST-1081	Credit Card
51634	2024-05-02	CUST-1081	Paypal
51635	2024-05-20	CUST-1081	Cash
51636	2024-05-31	CUST-1081	Credit Card
51637	2024-06-14	CUST-1081	Debit Card
51638	2024-06-29	CUST-1081	Credit Card
51639	2024-07-06	CUST-1081	Credit Card
51640	2024-07-12	CUST-1081	Debit Card
51641	2024-09-28	CUST-1081	Credit Card
51642	2024-10-08	CUST-1081	Debit Card
51643	2024-10-15	CUST-1081	Cash
51644	2024-10-20	CUST-1081	Debit Card
51645	2024-10-22	CUST-1081	Cash
51646	2024-10-25	CUST-1081	Paypal
51647	2024-11-04	CUST-1081	Credit Card
51648	2024-11-09	CUST-1081	Credit Card
51649	2024-11-11	CUST-1081	Credit Card
51650	2024-11-24	CUST-1081	Debit Card
51651	2024-12-01	CUST-1081	Credit Card
51652	2024-12-13	CUST-1081	Credit Card
51653	2024-12-23	CUST-1081	Credit Card
51654	2025-01-20	CUST-1081	Credit Card
51655	2025-03-08	CUST-1081	Paypal
51656	2025-06-26	CUST-1081	Credit Card
51657	2025-06-30	CUST-1081	Paypal
51658	2025-07-21	CUST-1081	Credit Card
51659	2025-08-27	CUST-1081	Cash
51660	2025-09-18	CUST-1081	Credit Card
51661	2025-09-27	CUST-1081	Credit Card
51662	2025-10-10	CUST-1081	Credit Card
51663	2025-11-09	CUST-1081	Credit Card
51664	2025-11-14	CUST-1081	Credit Card
51665	2025-11-28	CUST-1081	Debit Card
51666	2025-12-14	CUST-1081	Debit Card
51667	2024-01-20	CUST-1082	Cash
51668	2025-04-28	CUST-1082	Credit Card
51669	2025-05-25	CUST-1082	Credit Card
51670	2025-09-04	CUST-1082	Debit Card
51671	2025-11-10	CUST-1082	Paypal
51672	2025-10-08	CUST-1083	Debit Card
51673	2024-06-21	CUST-1084	Credit Card
51674	2024-08-16	CUST-1084	Credit Card
51675	2024-11-21	CUST-1084	Credit Card
51676	2024-12-26	CUST-1084	Credit Card
51677	2025-01-04	CUST-1084	Credit Card
51678	2025-05-21	CUST-1084	Credit Card
51679	2025-07-13	CUST-1084	Credit Card
51680	2025-07-28	CUST-1084	Credit Card
51681	2025-09-04	CUST-1084	Credit Card
51682	2024-10-09	CUST-1085	Credit Card
51683	2024-11-23	CUST-1085	Debit Card
51684	2025-01-14	CUST-1085	Credit Card
51685	2025-08-08	CUST-1085	Credit Card
51686	2025-11-15	CUST-1085	Credit Card
51687	2024-05-02	CUST-1086	Credit Card
51688	2024-07-27	CUST-1086	Cash
51689	2024-08-14	CUST-1086	Cash
51690	2024-08-15	CUST-1086	Debit Card
51691	2024-08-27	CUST-1086	Credit Card
51692	2024-11-30	CUST-1086	Credit Card
51693	2024-12-07	CUST-1086	Paypal
51694	2025-09-30	CUST-1086	Paypal
51695	2025-10-02	CUST-1086	Paypal
51696	2025-12-23	CUST-1086	Debit Card
51697	2024-01-05	CUST-1087	Paypal
51698	2024-01-30	CUST-1087	Paypal
51699	2024-02-08	CUST-1087	Credit Card
51700	2024-05-02	CUST-1087	Credit Card
51701	2024-05-14	CUST-1087	Credit Card
51702	2024-05-28	CUST-1087	Debit Card
51703	2025-04-20	CUST-1087	Debit Card
51704	2025-05-04	CUST-1087	Credit Card
51705	2025-05-06	CUST-1087	Paypal
51706	2025-05-22	CUST-1087	Debit Card
51707	2025-09-11	CUST-1087	Cash
51708	2025-12-01	CUST-1087	Debit Card
51709	2024-09-03	CUST-1088	Cash
51710	2025-03-03	CUST-1088	Credit Card
51711	2025-09-17	CUST-1089	Paypal
51712	2024-05-05	CUST-1090	Debit Card
51713	2024-05-27	CUST-1090	Credit Card
51714	2024-06-06	CUST-1090	Credit Card
51715	2024-06-30	CUST-1090	Paypal
51716	2024-09-14	CUST-1090	Credit Card
51717	2024-10-24	CUST-1090	Credit Card
51718	2024-11-22	CUST-1090	Debit Card
51719	2024-12-19	CUST-1090	Debit Card
51720	2025-01-02	CUST-1090	Debit Card
51721	2025-02-01	CUST-1090	Paypal
51722	2025-02-14	CUST-1090	Debit Card
51723	2025-02-23	CUST-1090	Credit Card
51724	2025-04-05	CUST-1090	Credit Card
51725	2025-05-27	CUST-1090	Credit Card
51726	2025-09-13	CUST-1090	Debit Card
51727	2025-09-27	CUST-1090	Credit Card
51728	2025-10-08	CUST-1090	Debit Card
51729	2025-11-10	CUST-1090	Cash
51730	2025-11-10	CUST-1090	Debit Card
51731	2025-11-16	CUST-1090	Debit Card
51732	2024-04-08	CUST-1091	Paypal
51733	2024-06-28	CUST-1091	Credit Card
51734	2024-07-23	CUST-1091	Paypal
51735	2024-09-27	CUST-1091	Debit Card
51736	2024-11-07	CUST-1091	Debit Card
51737	2024-12-24	CUST-1091	Credit Card
51738	2025-07-07	CUST-1091	Credit Card
51739	2025-12-01	CUST-1091	Paypal
51740	2025-12-03	CUST-1091	Paypal
51741	2025-09-08	CUST-1092	Credit Card
51742	2024-02-09	CUST-1093	Debit Card
51743	2024-02-14	CUST-1093	Debit Card
51744	2024-05-13	CUST-1093	Credit Card
51745	2024-05-20	CUST-1093	Debit Card
51746	2024-05-26	CUST-1093	Credit Card
51747	2024-07-08	CUST-1093	Credit Card
51748	2024-07-18	CUST-1093	Debit Card
51749	2024-08-08	CUST-1093	Debit Card
51750	2024-08-12	CUST-1093	Cash
51751	2024-09-03	CUST-1093	Credit Card
51752	2024-10-11	CUST-1093	Credit Card
51753	2024-11-06	CUST-1093	Debit Card
51754	2024-11-08	CUST-1093	Debit Card
51755	2024-11-22	CUST-1093	Credit Card
51756	2024-11-24	CUST-1093	Debit Card
51757	2024-12-17	CUST-1093	Debit Card
51758	2024-12-21	CUST-1093	Credit Card
51759	2024-12-27	CUST-1093	Debit Card
51760	2024-12-30	CUST-1093	Debit Card
51761	2025-02-03	CUST-1093	Credit Card
51762	2025-02-23	CUST-1093	Cash
51763	2025-03-04	CUST-1093	Debit Card
51764	2025-03-23	CUST-1093	Debit Card
51765	2025-04-27	CUST-1093	Cash
51766	2025-04-30	CUST-1093	Debit Card
51767	2025-06-27	CUST-1093	Debit Card
51768	2025-07-25	CUST-1093	Credit Card
51769	2024-02-29	CUST-1094	Credit Card
51770	2024-03-15	CUST-1094	Debit Card
51771	2024-03-28	CUST-1094	Paypal
51772	2024-05-10	CUST-1094	Cash
51773	2024-07-20	CUST-1094	Credit Card
51774	2024-09-28	CUST-1094	Debit Card
51775	2024-11-08	CUST-1094	Paypal
51776	2024-11-21	CUST-1094	Debit Card
51777	2025-01-02	CUST-1094	Paypal
51778	2025-01-07	CUST-1094	Credit Card
51779	2025-01-23	CUST-1094	Debit Card
51780	2025-03-08	CUST-1094	Credit Card
51781	2025-03-16	CUST-1094	Credit Card
51782	2025-04-17	CUST-1094	Debit Card
51783	2025-05-07	CUST-1094	Credit Card
51784	2025-08-01	CUST-1094	Paypal
51785	2025-08-15	CUST-1094	Credit Card
51786	2025-08-24	CUST-1094	Paypal
51787	2025-11-17	CUST-1094	Credit Card
51788	2025-12-28	CUST-1094	Debit Card
51789	2024-03-06	CUST-1095	Debit Card
51790	2024-06-02	CUST-1095	Debit Card
51791	2025-06-25	CUST-1095	Debit Card
51792	2025-08-15	CUST-1095	Credit Card
51793	2025-11-11	CUST-1095	Cash
51794	2025-11-24	CUST-1096	Debit Card
51795	2024-01-10	CUST-1097	Credit Card
51796	2024-02-11	CUST-1097	Credit Card
51797	2024-04-07	CUST-1097	Credit Card
51798	2024-06-16	CUST-1097	Debit Card
51799	2024-07-02	CUST-1097	Cash
51800	2024-07-23	CUST-1097	Debit Card
51801	2024-08-22	CUST-1097	Paypal
51802	2024-09-16	CUST-1097	Credit Card
51803	2024-10-05	CUST-1097	Cash
51804	2024-11-02	CUST-1097	Credit Card
51805	2024-11-02	CUST-1097	Paypal
51806	2024-12-05	CUST-1097	Debit Card
51807	2024-12-20	CUST-1097	Credit Card
51808	2025-01-10	CUST-1097	Debit Card
51809	2025-01-11	CUST-1097	Debit Card
51810	2025-02-07	CUST-1097	Credit Card
51811	2025-02-16	CUST-1097	Credit Card
51812	2025-04-11	CUST-1097	Debit Card
51813	2025-06-25	CUST-1097	Debit Card
51814	2025-10-07	CUST-1097	Credit Card
51815	2025-12-02	CUST-1097	Debit Card
51816	2025-12-15	CUST-1097	Credit Card
51817	2025-12-18	CUST-1097	Debit Card
51818	2025-12-21	CUST-1097	Debit Card
51819	2025-12-26	CUST-1097	Credit Card
51820	2024-01-17	CUST-1098	Paypal
51821	2024-02-15	CUST-1098	Credit Card
51822	2024-03-23	CUST-1098	Credit Card
51823	2024-04-19	CUST-1098	Debit Card
51824	2024-07-25	CUST-1098	Credit Card
51825	2024-10-12	CUST-1098	Debit Card
51826	2024-10-23	CUST-1098	Credit Card
51827	2025-01-20	CUST-1098	Debit Card
51828	2025-02-25	CUST-1098	Paypal
51829	2025-05-08	CUST-1098	Debit Card
51830	2025-07-22	CUST-1098	Paypal
51831	2025-09-03	CUST-1098	Paypal
51832	2025-11-11	CUST-1098	Credit Card
51833	2025-12-11	CUST-1098	Debit Card
51834	2025-12-24	CUST-1098	Debit Card
51835	2024-01-29	CUST-1099	Debit Card
51836	2024-02-04	CUST-1099	Credit Card
51837	2024-02-06	CUST-1099	Debit Card
51838	2024-02-13	CUST-1099	Paypal
51839	2024-03-04	CUST-1099	Cash
51840	2024-03-12	CUST-1099	Cash
51841	2024-03-14	CUST-1099	Paypal
51842	2024-03-19	CUST-1099	Credit Card
51843	2024-04-07	CUST-1099	Debit Card
51844	2024-04-13	CUST-1099	Credit Card
51845	2024-05-07	CUST-1099	Cash
51846	2024-05-10	CUST-1099	Credit Card
51847	2024-05-23	CUST-1099	Credit Card
51848	2024-05-25	CUST-1099	Debit Card
51849	2024-05-27	CUST-1099	Credit Card
51850	2024-06-06	CUST-1099	Credit Card
51851	2024-06-10	CUST-1099	Credit Card
51852	2024-06-25	CUST-1099	Paypal
51853	2024-07-02	CUST-1099	Credit Card
51854	2024-07-07	CUST-1099	Debit Card
51855	2024-07-10	CUST-1099	Debit Card
51856	2024-07-12	CUST-1099	Credit Card
51857	2024-08-06	CUST-1099	Paypal
51858	2024-08-22	CUST-1099	Credit Card
51859	2024-08-30	CUST-1099	Debit Card
51860	2024-09-12	CUST-1099	Cash
51861	2024-09-17	CUST-1099	Credit Card
51862	2024-09-18	CUST-1099	Credit Card
51863	2024-10-12	CUST-1099	Paypal
51864	2024-10-17	CUST-1099	Credit Card
51865	2024-10-18	CUST-1099	Cash
51866	2024-11-08	CUST-1099	Debit Card
51867	2024-11-10	CUST-1099	Credit Card
51868	2024-11-16	CUST-1099	Debit Card
51869	2024-11-19	CUST-1099	Credit Card
51870	2024-11-20	CUST-1099	Cash
51871	2024-11-23	CUST-1099	Cash
51872	2024-11-23	CUST-1099	Credit Card
51873	2024-11-23	CUST-1099	Debit Card
51874	2024-11-24	CUST-1099	Credit Card
51875	2024-11-30	CUST-1099	Credit Card
51876	2024-12-04	CUST-1099	Cash
51877	2024-12-04	CUST-1099	Credit Card
51878	2024-12-06	CUST-1099	Credit Card
51879	2024-12-08	CUST-1099	Credit Card
51880	2024-12-11	CUST-1099	Credit Card
51881	2024-12-13	CUST-1099	Debit Card
51882	2024-12-16	CUST-1099	Debit Card
51883	2024-12-17	CUST-1099	Debit Card
51884	2024-12-21	CUST-1099	Credit Card
51885	2024-12-21	CUST-1099	Debit Card
51886	2024-12-23	CUST-1099	Cash
51887	2024-12-29	CUST-1099	Credit Card
51888	2025-01-03	CUST-1099	Cash
51889	2025-01-04	CUST-1099	Credit Card
51890	2025-01-08	CUST-1099	Credit Card
51891	2025-01-25	CUST-1099	Credit Card
51892	2025-01-28	CUST-1099	Cash
51893	2025-01-28	CUST-1099	Debit Card
51894	2025-02-01	CUST-1099	Credit Card
51895	2025-02-01	CUST-1099	Debit Card
51896	2025-02-04	CUST-1099	Paypal
51897	2025-02-23	CUST-1099	Debit Card
51898	2025-02-24	CUST-1099	Credit Card
51899	2025-03-11	CUST-1099	Credit Card
51900	2025-03-12	CUST-1099	Credit Card
51901	2025-03-17	CUST-1099	Credit Card
51902	2025-03-24	CUST-1099	Credit Card
51903	2025-04-02	CUST-1099	Paypal
51904	2025-05-03	CUST-1099	Paypal
51905	2025-05-05	CUST-1099	Paypal
51906	2025-05-10	CUST-1099	Cash
51907	2025-05-12	CUST-1099	Debit Card
51908	2025-05-20	CUST-1099	Cash
51909	2025-05-30	CUST-1099	Credit Card
51910	2025-06-21	CUST-1099	Paypal
51911	2025-07-03	CUST-1099	Cash
51912	2025-07-10	CUST-1099	Debit Card
51913	2025-07-13	CUST-1099	Credit Card
51914	2025-07-17	CUST-1099	Credit Card
51915	2025-07-28	CUST-1099	Credit Card
51916	2025-08-02	CUST-1099	Cash
51917	2025-08-03	CUST-1099	Cash
51918	2025-08-15	CUST-1099	Paypal
51919	2025-08-17	CUST-1099	Credit Card
51920	2025-08-22	CUST-1099	Cash
51921	2025-08-30	CUST-1099	Paypal
51922	2025-09-04	CUST-1099	Credit Card
51923	2025-09-12	CUST-1099	Credit Card
51924	2025-09-19	CUST-1099	Credit Card
51925	2025-09-24	CUST-1099	Cash
51926	2025-09-27	CUST-1099	Credit Card
51927	2025-09-29	CUST-1099	Credit Card
51928	2025-09-30	CUST-1099	Debit Card
51929	2025-10-01	CUST-1099	Credit Card
51930	2025-10-03	CUST-1099	Credit Card
51931	2025-10-09	CUST-1099	Debit Card
51932	2025-10-18	CUST-1099	Cash
51933	2025-10-19	CUST-1099	Credit Card
51934	2025-10-23	CUST-1099	Debit Card
51935	2025-10-25	CUST-1099	Credit Card
51936	2025-10-29	CUST-1099	Credit Card
51937	2025-11-02	CUST-1099	Debit Card
51938	2025-11-05	CUST-1099	Credit Card
51939	2025-11-09	CUST-1099	Credit Card
51940	2025-11-13	CUST-1099	Paypal
51941	2025-11-20	CUST-1099	Debit Card
51942	2025-11-22	CUST-1099	Debit Card
51943	2025-11-24	CUST-1099	Credit Card
51944	2025-12-02	CUST-1099	Credit Card
51945	2025-12-03	CUST-1099	Cash
51946	2025-12-12	CUST-1099	Cash
51947	2025-12-16	CUST-1099	Credit Card
51948	2025-12-18	CUST-1099	Paypal
51949	2025-12-24	CUST-1099	Debit Card
51950	2025-12-27	CUST-1099	Cash
51951	2025-12-27	CUST-1099	Credit Card
51952	2025-12-27	CUST-1099	Debit Card
51953	2025-12-28	CUST-1099	Credit Card
51954	2025-12-29	CUST-1099	Cash
51955	2025-12-29	CUST-1099	Credit Card
51956	2025-12-29	CUST-1099	Debit Card
51957	2025-12-30	CUST-1099	Debit Card
51958	2024-01-07	CUST-1100	Credit Card
51959	2024-01-09	CUST-1100	Cash
51960	2024-03-08	CUST-1100	Debit Card
51961	2024-05-21	CUST-1100	Paypal
51962	2024-08-10	CUST-1100	Credit Card
51963	2024-11-01	CUST-1100	Credit Card
51964	2024-11-05	CUST-1100	Credit Card
51965	2024-12-08	CUST-1100	Credit Card
51966	2024-12-19	CUST-1100	Debit Card
51967	2025-01-02	CUST-1100	Debit Card
51968	2025-02-22	CUST-1100	Debit Card
51969	2025-07-02	CUST-1100	Paypal
51970	2025-08-14	CUST-1100	Cash
51971	2025-08-18	CUST-1100	Credit Card
51972	2025-11-12	CUST-1100	Credit Card
51973	2025-11-20	CUST-1100	Paypal
51974	2025-12-27	CUST-1100	Credit Card
51975	2024-01-01	CUST-1101	Credit Card
51976	2024-02-16	CUST-1101	Paypal
51977	2024-03-18	CUST-1101	Credit Card
51978	2024-04-26	CUST-1101	Paypal
51979	2024-12-22	CUST-1101	Credit Card
51980	2025-02-08	CUST-1101	Credit Card
51981	2025-02-21	CUST-1101	Debit Card
51982	2025-03-15	CUST-1101	Debit Card
51983	2025-03-17	CUST-1101	Debit Card
51984	2025-04-01	CUST-1101	Debit Card
51985	2025-04-24	CUST-1101	Debit Card
51986	2025-04-29	CUST-1101	Paypal
51987	2025-06-04	CUST-1101	Credit Card
51988	2025-06-07	CUST-1101	Credit Card
51989	2025-06-19	CUST-1101	Debit Card
51990	2025-07-05	CUST-1101	Cash
51991	2025-07-31	CUST-1101	Credit Card
51992	2025-09-14	CUST-1101	Credit Card
51993	2025-09-28	CUST-1101	Debit Card
51994	2025-11-17	CUST-1101	Paypal
51995	2025-11-28	CUST-1101	Debit Card
51996	2025-12-30	CUST-1101	Paypal
51997	2024-01-01	CUST-1102	Credit Card
51998	2024-02-12	CUST-1102	Cash
51999	2024-10-03	CUST-1102	Debit Card
52000	2024-12-07	CUST-1102	Credit Card
52001	2024-12-20	CUST-1102	Paypal
52002	2024-12-27	CUST-1102	Debit Card
52003	2025-01-20	CUST-1102	Cash
52004	2025-03-13	CUST-1102	Debit Card
52005	2025-11-08	CUST-1102	Debit Card
52006	2025-12-03	CUST-1102	Debit Card
52007	2024-02-13	CUST-1103	Credit Card
52008	2024-03-16	CUST-1103	Credit Card
52009	2024-03-25	CUST-1103	Cash
52010	2024-03-30	CUST-1103	Credit Card
52011	2024-04-02	CUST-1103	Paypal
52012	2024-05-11	CUST-1103	Cash
52013	2024-06-09	CUST-1103	Credit Card
52014	2024-06-09	CUST-1103	Debit Card
52015	2024-07-05	CUST-1103	Cash
52016	2024-10-17	CUST-1103	Credit Card
52017	2024-12-10	CUST-1103	Debit Card
52018	2024-12-15	CUST-1103	Credit Card
52019	2024-12-19	CUST-1103	Credit Card
52020	2024-12-22	CUST-1103	Credit Card
52021	2025-02-24	CUST-1103	Debit Card
52022	2025-04-09	CUST-1103	Credit Card
52023	2025-04-16	CUST-1103	Cash
52024	2025-04-23	CUST-1103	Cash
52025	2025-05-10	CUST-1103	Cash
52026	2025-06-27	CUST-1103	Debit Card
52027	2025-07-06	CUST-1103	Credit Card
52028	2025-07-15	CUST-1103	Credit Card
52029	2025-10-04	CUST-1103	Debit Card
52030	2025-10-07	CUST-1103	Credit Card
52031	2025-11-02	CUST-1103	Debit Card
52032	2025-11-06	CUST-1103	Credit Card
52033	2025-11-18	CUST-1103	Credit Card
52034	2025-12-08	CUST-1103	Credit Card
52035	2024-04-18	CUST-1104	Debit Card
52036	2024-04-28	CUST-1104	Cash
52037	2024-05-12	CUST-1104	Cash
52038	2024-09-15	CUST-1104	Cash
52039	2024-12-05	CUST-1104	Credit Card
52040	2024-12-07	CUST-1104	Paypal
52041	2024-12-15	CUST-1104	Credit Card
52042	2025-01-28	CUST-1104	Debit Card
52043	2025-03-16	CUST-1104	Paypal
52044	2025-04-02	CUST-1104	Credit Card
52045	2025-05-31	CUST-1104	Paypal
52046	2025-08-07	CUST-1104	Cash
52047	2025-08-20	CUST-1104	Debit Card
52048	2025-09-16	CUST-1104	Credit Card
52049	2025-10-29	CUST-1104	Paypal
52050	2025-12-23	CUST-1104	Cash
52051	2024-02-02	CUST-1105	Credit Card
52052	2024-02-05	CUST-1105	Credit Card
52053	2024-04-20	CUST-1105	Credit Card
52054	2024-04-24	CUST-1105	Credit Card
52055	2024-05-11	CUST-1105	Debit Card
52056	2024-05-11	CUST-1105	Paypal
52057	2024-05-13	CUST-1105	Cash
52058	2024-05-13	CUST-1105	Credit Card
52059	2024-05-17	CUST-1105	Paypal
52060	2024-05-28	CUST-1105	Paypal
52061	2024-06-12	CUST-1105	Credit Card
52062	2024-06-15	CUST-1105	Paypal
52063	2024-06-22	CUST-1105	Paypal
52064	2024-07-07	CUST-1105	Credit Card
52065	2024-07-16	CUST-1105	Cash
52066	2024-07-28	CUST-1105	Cash
52067	2024-08-06	CUST-1105	Credit Card
52068	2024-08-21	CUST-1105	Debit Card
52069	2024-09-14	CUST-1105	Debit Card
52070	2024-10-16	CUST-1105	Cash
52071	2024-10-22	CUST-1105	Debit Card
52072	2024-11-08	CUST-1105	Debit Card
52073	2024-11-18	CUST-1105	Credit Card
52074	2024-12-01	CUST-1105	Paypal
52075	2024-12-02	CUST-1105	Debit Card
52076	2024-12-11	CUST-1105	Cash
52077	2024-12-16	CUST-1105	Paypal
52078	2024-12-18	CUST-1105	Paypal
52079	2024-12-20	CUST-1105	Debit Card
52080	2024-12-23	CUST-1105	Cash
52081	2025-01-21	CUST-1105	Debit Card
52082	2025-01-31	CUST-1105	Debit Card
52083	2025-02-11	CUST-1105	Credit Card
52084	2025-02-14	CUST-1105	Debit Card
52085	2025-02-15	CUST-1105	Paypal
52086	2025-03-03	CUST-1105	Credit Card
52087	2025-03-03	CUST-1105	Debit Card
52088	2025-03-03	CUST-1105	Paypal
52089	2025-03-14	CUST-1105	Debit Card
52090	2025-04-09	CUST-1105	Paypal
52091	2025-06-05	CUST-1105	Debit Card
52092	2025-06-17	CUST-1105	Credit Card
52093	2025-06-24	CUST-1105	Paypal
52094	2025-07-12	CUST-1105	Credit Card
52095	2025-07-15	CUST-1105	Debit Card
52096	2025-07-27	CUST-1105	Credit Card
52097	2025-08-27	CUST-1105	Credit Card
52098	2025-10-13	CUST-1105	Credit Card
52099	2025-11-13	CUST-1105	Debit Card
52100	2025-11-20	CUST-1105	Paypal
52101	2025-11-23	CUST-1105	Credit Card
52102	2025-12-11	CUST-1105	Debit Card
52103	2024-08-06	CUST-1106	Credit Card
52104	2024-08-17	CUST-1106	Paypal
52105	2025-01-25	CUST-1106	Debit Card
52106	2025-03-15	CUST-1106	Credit Card
52107	2025-11-13	CUST-1106	Debit Card
52108	2024-01-15	CUST-1107	Paypal
52109	2024-07-11	CUST-1107	Credit Card
52110	2024-08-20	CUST-1107	Credit Card
52111	2024-08-20	CUST-1107	Debit Card
52112	2024-11-10	CUST-1107	Debit Card
52113	2024-12-06	CUST-1107	Paypal
52114	2025-02-10	CUST-1107	Debit Card
52115	2025-03-13	CUST-1107	Debit Card
52116	2025-03-16	CUST-1107	Paypal
52117	2025-08-26	CUST-1107	Paypal
52118	2025-09-21	CUST-1107	Credit Card
52119	2024-01-21	CUST-1108	Debit Card
52120	2024-07-27	CUST-1108	Paypal
52121	2025-03-25	CUST-1108	Paypal
52122	2025-06-18	CUST-1108	Debit Card
52123	2025-07-07	CUST-1108	Debit Card
52124	2025-09-22	CUST-1108	Cash
52125	2025-11-04	CUST-1108	Credit Card
52126	2024-01-26	CUST-1109	Debit Card
52127	2024-02-09	CUST-1109	Credit Card
52128	2024-03-25	CUST-1109	Debit Card
52129	2024-04-13	CUST-1109	Debit Card
52130	2024-06-01	CUST-1109	Paypal
52131	2024-06-28	CUST-1109	Paypal
52132	2024-07-01	CUST-1109	Credit Card
52133	2024-07-29	CUST-1109	Credit Card
52134	2024-08-22	CUST-1109	Debit Card
52135	2024-09-05	CUST-1109	Cash
52136	2024-09-20	CUST-1109	Credit Card
52137	2024-10-08	CUST-1109	Credit Card
52138	2024-11-23	CUST-1109	Cash
52139	2024-12-11	CUST-1109	Credit Card
52140	2024-12-26	CUST-1109	Credit Card
52141	2025-02-01	CUST-1109	Credit Card
52142	2025-03-03	CUST-1109	Cash
52143	2025-04-14	CUST-1109	Debit Card
52144	2025-04-22	CUST-1109	Credit Card
52145	2025-07-11	CUST-1109	Credit Card
52146	2025-08-13	CUST-1109	Paypal
52147	2025-10-15	CUST-1109	Credit Card
52148	2025-10-27	CUST-1109	Cash
52149	2025-11-07	CUST-1109	Debit Card
52150	2024-01-09	CUST-1110	Debit Card
52151	2024-01-29	CUST-1110	Credit Card
52152	2024-02-09	CUST-1110	Credit Card
52153	2024-02-11	CUST-1110	Debit Card
52154	2024-03-18	CUST-1110	Debit Card
52155	2024-04-01	CUST-1110	Credit Card
52156	2024-04-24	CUST-1110	Cash
52157	2024-05-06	CUST-1110	Credit Card
52158	2024-05-29	CUST-1110	Paypal
52159	2024-06-04	CUST-1110	Debit Card
52160	2024-08-08	CUST-1110	Debit Card
52161	2024-08-13	CUST-1110	Debit Card
52162	2024-09-04	CUST-1110	Cash
52163	2024-09-14	CUST-1110	Credit Card
52164	2024-10-09	CUST-1110	Debit Card
52165	2024-10-10	CUST-1110	Cash
52166	2024-10-20	CUST-1110	Debit Card
52167	2024-10-23	CUST-1110	Cash
52168	2024-11-07	CUST-1110	Debit Card
52169	2024-11-22	CUST-1110	Credit Card
52170	2024-12-11	CUST-1110	Credit Card
52171	2025-01-05	CUST-1110	Cash
52172	2025-01-21	CUST-1110	Debit Card
52173	2025-01-25	CUST-1110	Debit Card
52174	2025-02-23	CUST-1110	Credit Card
52175	2025-03-03	CUST-1110	Credit Card
52176	2025-03-18	CUST-1110	Cash
52177	2025-03-18	CUST-1110	Debit Card
52178	2025-03-28	CUST-1110	Credit Card
52179	2025-04-10	CUST-1110	Cash
52180	2025-05-18	CUST-1110	Credit Card
52181	2025-05-23	CUST-1110	Credit Card
52182	2025-06-23	CUST-1110	Credit Card
52183	2025-07-09	CUST-1110	Credit Card
52184	2025-07-12	CUST-1110	Credit Card
52185	2025-07-31	CUST-1110	Paypal
52186	2025-08-21	CUST-1110	Credit Card
52187	2025-09-20	CUST-1110	Debit Card
52188	2025-10-02	CUST-1110	Credit Card
52189	2025-10-26	CUST-1110	Credit Card
52190	2025-10-28	CUST-1110	Cash
52191	2025-11-05	CUST-1110	Paypal
52192	2025-11-08	CUST-1110	Credit Card
52193	2025-11-10	CUST-1110	Debit Card
52194	2025-11-10	CUST-1110	Paypal
52195	2025-11-20	CUST-1110	Credit Card
52196	2025-11-24	CUST-1110	Cash
52197	2025-12-05	CUST-1110	Credit Card
52198	2025-12-05	CUST-1110	Debit Card
52199	2025-12-12	CUST-1110	Credit Card
52200	2025-12-18	CUST-1110	Debit Card
52201	2024-05-14	CUST-1111	Credit Card
52202	2024-07-03	CUST-1111	Credit Card
52203	2024-10-05	CUST-1111	Paypal
52204	2024-11-19	CUST-1111	Paypal
52205	2024-12-03	CUST-1111	Credit Card
52206	2024-12-24	CUST-1111	Paypal
52207	2025-06-22	CUST-1111	Debit Card
52208	2025-11-06	CUST-1111	Debit Card
52209	2025-11-07	CUST-1111	Debit Card
52210	2025-12-04	CUST-1111	Cash
52211	2024-04-08	CUST-1112	Cash
52212	2024-05-14	CUST-1112	Debit Card
52213	2024-05-22	CUST-1112	Paypal
52214	2024-07-29	CUST-1112	Paypal
52215	2024-08-09	CUST-1112	Credit Card
52216	2024-10-06	CUST-1112	Credit Card
52217	2024-12-07	CUST-1112	Debit Card
52218	2024-12-20	CUST-1112	Credit Card
52219	2025-01-13	CUST-1112	Credit Card
52220	2025-02-24	CUST-1112	Credit Card
52221	2025-06-19	CUST-1112	Credit Card
52222	2025-07-21	CUST-1112	Paypal
52223	2025-11-21	CUST-1112	Paypal
52224	2024-01-27	CUST-1113	Credit Card
52225	2024-06-06	CUST-1113	Debit Card
52226	2024-06-11	CUST-1113	Credit Card
52227	2024-06-26	CUST-1113	Credit Card
52228	2024-06-26	CUST-1113	Debit Card
52229	2024-09-15	CUST-1113	Debit Card
52230	2025-07-26	CUST-1113	Credit Card
52231	2025-08-24	CUST-1113	Credit Card
52232	2025-09-17	CUST-1113	Credit Card
52233	2024-03-10	CUST-1114	Paypal
52234	2024-04-13	CUST-1114	Debit Card
52235	2024-05-08	CUST-1114	Credit Card
52236	2024-11-20	CUST-1114	Cash
52237	2024-11-22	CUST-1114	Cash
52238	2025-01-30	CUST-1114	Credit Card
52239	2025-02-15	CUST-1114	Paypal
52240	2025-02-20	CUST-1114	Credit Card
52241	2025-05-02	CUST-1114	Paypal
52242	2025-05-03	CUST-1114	Debit Card
52243	2025-09-26	CUST-1114	Credit Card
52244	2025-12-11	CUST-1114	Credit Card
52245	2024-01-03	CUST-1115	Paypal
52246	2024-01-06	CUST-1115	Debit Card
52247	2024-01-23	CUST-1115	Debit Card
52248	2024-02-23	CUST-1115	Debit Card
52249	2024-02-29	CUST-1115	Paypal
52250	2024-03-01	CUST-1115	Debit Card
52251	2024-04-04	CUST-1115	Debit Card
52252	2024-04-29	CUST-1115	Credit Card
52253	2024-06-29	CUST-1115	Paypal
52254	2024-07-13	CUST-1115	Debit Card
52255	2024-07-22	CUST-1115	Debit Card
52256	2024-08-15	CUST-1115	Credit Card
52257	2024-09-09	CUST-1115	Credit Card
52258	2024-10-22	CUST-1115	Credit Card
52259	2024-11-12	CUST-1115	Credit Card
52260	2024-11-15	CUST-1115	Cash
52261	2024-11-19	CUST-1115	Paypal
52262	2024-11-22	CUST-1115	Credit Card
52263	2024-12-19	CUST-1115	Credit Card
52264	2024-12-31	CUST-1115	Cash
52265	2025-01-11	CUST-1115	Paypal
52266	2025-01-29	CUST-1115	Cash
52267	2025-02-01	CUST-1115	Debit Card
52268	2025-02-13	CUST-1115	Debit Card
52269	2025-03-01	CUST-1115	Paypal
52270	2025-03-14	CUST-1115	Debit Card
52271	2025-03-27	CUST-1115	Debit Card
52272	2025-04-22	CUST-1115	Credit Card
52273	2025-04-29	CUST-1115	Credit Card
52274	2025-05-17	CUST-1115	Debit Card
52275	2025-06-01	CUST-1115	Credit Card
52276	2025-06-19	CUST-1115	Paypal
52277	2025-06-26	CUST-1115	Credit Card
52278	2025-07-12	CUST-1115	Credit Card
52279	2025-07-30	CUST-1115	Credit Card
52280	2025-07-31	CUST-1115	Debit Card
52281	2025-08-20	CUST-1115	Debit Card
52282	2025-09-25	CUST-1115	Credit Card
52283	2025-10-02	CUST-1115	Debit Card
52284	2025-10-05	CUST-1115	Paypal
52285	2025-10-07	CUST-1115	Debit Card
52286	2025-10-25	CUST-1115	Debit Card
52287	2025-12-16	CUST-1115	Paypal
52288	2025-12-17	CUST-1115	Paypal
52289	2025-12-18	CUST-1115	Credit Card
52290	2025-12-26	CUST-1115	Debit Card
52291	2024-08-02	CUST-1117	Debit Card
52292	2024-08-18	CUST-1117	Credit Card
52293	2024-08-20	CUST-1117	Paypal
52294	2024-09-25	CUST-1117	Paypal
52295	2025-02-28	CUST-1117	Debit Card
52296	2025-08-29	CUST-1117	Debit Card
52297	2025-12-08	CUST-1117	Credit Card
52298	2024-03-02	CUST-1119	Paypal
52299	2025-01-22	CUST-1119	Credit Card
52300	2024-02-18	CUST-1120	Debit Card
52301	2024-05-04	CUST-1120	Credit Card
52302	2024-09-10	CUST-1120	Debit Card
52303	2025-01-27	CUST-1120	Credit Card
52304	2025-02-20	CUST-1120	Debit Card
52305	2025-04-15	CUST-1120	Credit Card
52306	2025-08-12	CUST-1120	Debit Card
52307	2025-08-20	CUST-1120	Credit Card
52308	2024-04-19	CUST-1121	Cash
52309	2025-04-22	CUST-1121	Cash
52310	2025-07-01	CUST-1121	Paypal
52311	2024-02-15	CUST-1122	Debit Card
52312	2024-03-17	CUST-1122	Cash
52313	2024-08-19	CUST-1122	Credit Card
52314	2025-01-23	CUST-1122	Cash
52315	2025-02-21	CUST-1122	Debit Card
52316	2025-03-26	CUST-1122	Cash
52317	2025-05-13	CUST-1122	Credit Card
52318	2025-05-19	CUST-1122	Debit Card
52319	2025-06-11	CUST-1122	Paypal
52320	2025-07-22	CUST-1122	Credit Card
52321	2025-10-27	CUST-1122	Debit Card
52322	2025-10-31	CUST-1122	Credit Card
52323	2024-02-23	CUST-1123	Credit Card
52324	2024-02-25	CUST-1123	Debit Card
52325	2024-04-02	CUST-1123	Debit Card
52326	2024-05-06	CUST-1123	Credit Card
52327	2024-06-18	CUST-1123	Cash
52328	2024-08-11	CUST-1123	Debit Card
52329	2024-08-17	CUST-1123	Paypal
52330	2024-09-04	CUST-1123	Debit Card
52331	2024-09-08	CUST-1123	Debit Card
52332	2024-09-19	CUST-1123	Credit Card
52333	2024-11-01	CUST-1123	Cash
52334	2024-11-07	CUST-1123	Debit Card
52335	2024-12-08	CUST-1123	Credit Card
52336	2024-12-17	CUST-1123	Cash
52337	2025-01-14	CUST-1123	Credit Card
52338	2025-01-19	CUST-1123	Paypal
52339	2025-03-29	CUST-1123	Paypal
52340	2025-04-07	CUST-1123	Cash
52341	2025-05-09	CUST-1123	Debit Card
52342	2025-05-10	CUST-1123	Credit Card
52343	2025-05-13	CUST-1123	Credit Card
52344	2025-06-05	CUST-1123	Credit Card
52345	2025-06-18	CUST-1123	Cash
52346	2025-06-22	CUST-1123	Paypal
52347	2025-06-27	CUST-1123	Debit Card
52348	2025-07-26	CUST-1123	Credit Card
52349	2025-08-21	CUST-1123	Credit Card
52350	2025-09-07	CUST-1123	Cash
52351	2025-09-08	CUST-1123	Credit Card
52352	2025-09-13	CUST-1123	Credit Card
52353	2025-09-16	CUST-1123	Debit Card
52354	2025-09-27	CUST-1123	Credit Card
52355	2025-09-30	CUST-1123	Debit Card
52356	2025-10-05	CUST-1123	Credit Card
52357	2025-10-07	CUST-1123	Debit Card
52358	2025-10-12	CUST-1123	Credit Card
52359	2025-11-01	CUST-1123	Debit Card
52360	2025-11-04	CUST-1123	Debit Card
52361	2025-11-11	CUST-1123	Credit Card
52362	2025-12-01	CUST-1123	Credit Card
52363	2025-12-18	CUST-1123	Credit Card
52364	2024-02-27	CUST-1124	Credit Card
52365	2024-12-23	CUST-1124	Cash
52366	2025-03-20	CUST-1124	Credit Card
52367	2025-07-09	CUST-1124	Credit Card
52368	2025-12-17	CUST-1124	Cash
52369	2024-05-01	CUST-1125	Debit Card
52370	2024-06-16	CUST-1125	Debit Card
52371	2024-10-03	CUST-1125	Debit Card
52372	2024-12-18	CUST-1125	Debit Card
52373	2024-05-11	CUST-1126	Credit Card
52374	2024-08-14	CUST-1126	Debit Card
52375	2024-11-15	CUST-1126	Credit Card
52376	2025-04-28	CUST-1126	Credit Card
52377	2025-05-01	CUST-1126	Credit Card
52378	2025-05-26	CUST-1126	Credit Card
52379	2025-08-30	CUST-1126	Cash
52380	2025-09-01	CUST-1126	Paypal
52381	2024-02-13	CUST-1127	Cash
52382	2024-06-02	CUST-1127	Paypal
52383	2024-06-09	CUST-1127	Cash
52384	2024-08-14	CUST-1127	Credit Card
52385	2024-08-15	CUST-1127	Paypal
52386	2024-09-16	CUST-1127	Paypal
52387	2024-11-14	CUST-1127	Credit Card
52388	2024-11-14	CUST-1127	Paypal
52389	2024-11-23	CUST-1127	Credit Card
52390	2024-12-20	CUST-1127	Paypal
52391	2024-12-28	CUST-1127	Debit Card
52392	2025-03-05	CUST-1127	Cash
52393	2025-03-10	CUST-1127	Paypal
52394	2025-04-04	CUST-1127	Debit Card
52395	2025-04-11	CUST-1127	Credit Card
52396	2025-04-27	CUST-1127	Credit Card
52397	2025-05-14	CUST-1127	Credit Card
52398	2025-05-15	CUST-1127	Cash
52399	2025-06-23	CUST-1127	Debit Card
52400	2025-06-30	CUST-1127	Paypal
52401	2025-07-27	CUST-1127	Debit Card
52402	2025-09-11	CUST-1127	Credit Card
52403	2025-09-13	CUST-1127	Credit Card
52404	2025-11-18	CUST-1127	Credit Card
52405	2025-12-01	CUST-1127	Credit Card
52406	2025-12-08	CUST-1127	Debit Card
52407	2025-12-10	CUST-1127	Credit Card
52408	2025-12-19	CUST-1127	Paypal
52409	2025-12-27	CUST-1127	Debit Card
52410	2025-12-31	CUST-1127	Paypal
52411	2024-03-07	CUST-1128	Paypal
52412	2024-06-28	CUST-1128	Debit Card
52413	2025-03-31	CUST-1128	Debit Card
52414	2025-07-26	CUST-1128	Credit Card
52415	2025-07-31	CUST-1128	Debit Card
52416	2025-10-18	CUST-1128	Cash
52417	2024-01-17	CUST-1129	Paypal
52418	2024-11-03	CUST-1129	Cash
52419	2024-11-23	CUST-1129	Debit Card
52420	2024-11-24	CUST-1129	Credit Card
52421	2024-12-13	CUST-1129	Credit Card
52422	2025-10-28	CUST-1129	Cash
52423	2025-11-09	CUST-1129	Debit Card
52424	2024-03-23	CUST-1130	Paypal
52425	2024-04-10	CUST-1130	Cash
52426	2024-04-16	CUST-1130	Credit Card
52427	2024-04-29	CUST-1130	Cash
52428	2024-05-19	CUST-1130	Credit Card
52429	2024-09-06	CUST-1130	Paypal
52430	2024-09-26	CUST-1130	Credit Card
52431	2024-09-30	CUST-1130	Credit Card
52432	2024-10-22	CUST-1130	Cash
52433	2024-11-14	CUST-1130	Paypal
52434	2024-12-29	CUST-1130	Debit Card
52435	2025-02-20	CUST-1130	Debit Card
52436	2025-02-26	CUST-1130	Credit Card
52437	2025-04-04	CUST-1130	Credit Card
52438	2025-04-14	CUST-1130	Debit Card
52439	2025-05-07	CUST-1130	Credit Card
52440	2025-05-23	CUST-1130	Credit Card
52441	2025-08-01	CUST-1130	Credit Card
52442	2025-08-17	CUST-1130	Credit Card
52443	2025-10-30	CUST-1130	Credit Card
52444	2025-11-01	CUST-1130	Credit Card
52445	2024-01-05	CUST-1131	Debit Card
52446	2024-06-03	CUST-1131	Debit Card
52447	2024-08-30	CUST-1131	Paypal
52448	2024-11-01	CUST-1131	Credit Card
52449	2024-12-09	CUST-1131	Debit Card
52450	2024-12-17	CUST-1131	Cash
52451	2024-12-26	CUST-1131	Credit Card
52452	2025-03-19	CUST-1131	Debit Card
52453	2025-07-30	CUST-1131	Credit Card
52454	2025-11-03	CUST-1131	Paypal
52455	2025-11-09	CUST-1131	Credit Card
52456	2025-12-07	CUST-1131	Debit Card
52457	2024-01-30	CUST-1132	Debit Card
52458	2024-02-21	CUST-1132	Debit Card
52459	2024-04-21	CUST-1132	Cash
52460	2024-05-31	CUST-1132	Credit Card
52461	2024-06-04	CUST-1132	Credit Card
52462	2024-06-28	CUST-1132	Credit Card
52463	2024-07-03	CUST-1132	Debit Card
52464	2024-07-27	CUST-1132	Credit Card
52465	2024-08-06	CUST-1132	Debit Card
52466	2024-10-12	CUST-1132	Credit Card
52467	2024-10-29	CUST-1132	Paypal
52468	2024-12-03	CUST-1132	Credit Card
52469	2025-01-14	CUST-1132	Credit Card
52470	2025-02-07	CUST-1132	Paypal
52471	2025-04-15	CUST-1132	Paypal
52472	2025-05-04	CUST-1132	Debit Card
52473	2025-05-20	CUST-1132	Debit Card
52474	2025-05-24	CUST-1132	Credit Card
52475	2025-06-13	CUST-1132	Credit Card
52476	2025-07-03	CUST-1132	Debit Card
52477	2025-08-14	CUST-1132	Paypal
52478	2025-10-27	CUST-1132	Debit Card
52479	2025-11-02	CUST-1132	Paypal
52480	2025-11-23	CUST-1132	Paypal
52481	2025-11-26	CUST-1132	Cash
52482	2025-12-03	CUST-1132	Paypal
52483	2025-12-06	CUST-1132	Credit Card
52484	2025-12-23	CUST-1132	Debit Card
52485	2024-01-26	CUST-1133	Debit Card
52486	2024-07-07	CUST-1133	Credit Card
52487	2024-07-24	CUST-1133	Credit Card
52488	2024-08-29	CUST-1133	Debit Card
52489	2024-10-03	CUST-1133	Debit Card
52490	2024-10-30	CUST-1133	Debit Card
52491	2024-12-27	CUST-1133	Paypal
52492	2025-01-02	CUST-1133	Debit Card
52493	2025-01-27	CUST-1133	Debit Card
52494	2025-02-05	CUST-1133	Credit Card
52495	2025-02-17	CUST-1133	Credit Card
52496	2025-02-28	CUST-1133	Credit Card
52497	2025-03-25	CUST-1133	Cash
52498	2025-03-27	CUST-1133	Credit Card
52499	2025-04-23	CUST-1133	Credit Card
52500	2025-11-05	CUST-1133	Debit Card
52501	2025-11-21	CUST-1133	Debit Card
52502	2025-11-26	CUST-1133	Credit Card
52503	2025-12-04	CUST-1133	Credit Card
52504	2025-12-11	CUST-1133	Debit Card
52505	2025-12-31	CUST-1133	Credit Card
52506	2024-02-16	CUST-1134	Cash
52507	2024-03-24	CUST-1134	Debit Card
52508	2024-05-15	CUST-1134	Debit Card
52509	2024-06-29	CUST-1134	Credit Card
52510	2024-08-14	CUST-1134	Debit Card
52511	2024-08-23	CUST-1134	Cash
52512	2024-11-03	CUST-1134	Debit Card
52513	2024-11-16	CUST-1134	Debit Card
52514	2024-12-23	CUST-1134	Debit Card
52515	2025-03-31	CUST-1134	Credit Card
52516	2025-05-14	CUST-1134	Credit Card
52517	2025-06-09	CUST-1134	Credit Card
52518	2025-06-14	CUST-1134	Paypal
52519	2025-06-17	CUST-1134	Paypal
52520	2025-07-08	CUST-1134	Cash
52521	2025-07-11	CUST-1134	Debit Card
52522	2025-08-13	CUST-1134	Credit Card
52523	2025-09-17	CUST-1134	Paypal
52524	2025-10-14	CUST-1134	Cash
52525	2025-10-29	CUST-1134	Credit Card
52526	2025-11-07	CUST-1134	Debit Card
52527	2025-11-26	CUST-1134	Credit Card
52528	2025-12-06	CUST-1134	Debit Card
52529	2024-02-23	CUST-1135	Cash
52530	2024-08-06	CUST-1135	Credit Card
52531	2024-12-21	CUST-1135	Credit Card
52532	2025-03-21	CUST-1135	Debit Card
52533	2025-11-21	CUST-1135	Credit Card
52534	2024-08-13	CUST-1136	Debit Card
52535	2024-08-31	CUST-1136	Debit Card
52536	2024-09-27	CUST-1136	Credit Card
52537	2024-09-30	CUST-1136	Paypal
52538	2025-08-16	CUST-1136	Debit Card
52539	2025-08-19	CUST-1136	Credit Card
52540	2025-09-11	CUST-1136	Cash
52541	2025-11-02	CUST-1136	Paypal
52542	2025-12-21	CUST-1136	Debit Card
52543	2025-12-30	CUST-1136	Paypal
52544	2024-04-28	CUST-1137	Credit Card
52545	2024-08-12	CUST-1137	Credit Card
52546	2025-06-07	CUST-1137	Debit Card
52547	2025-07-14	CUST-1137	Cash
52548	2024-02-25	CUST-1138	Paypal
52549	2024-06-07	CUST-1138	Paypal
52550	2025-05-06	CUST-1138	Debit Card
52551	2025-06-02	CUST-1138	Debit Card
52552	2025-07-04	CUST-1138	Debit Card
52553	2025-10-09	CUST-1138	Credit Card
52554	2024-04-18	CUST-1139	Debit Card
52555	2024-10-25	CUST-1139	Debit Card
52556	2024-01-28	CUST-1140	Debit Card
52557	2024-02-28	CUST-1140	Credit Card
52558	2024-03-05	CUST-1140	Paypal
52559	2024-04-12	CUST-1140	Credit Card
52560	2024-06-10	CUST-1140	Paypal
52561	2024-06-22	CUST-1140	Credit Card
52562	2024-06-30	CUST-1140	Credit Card
52563	2024-07-19	CUST-1140	Paypal
52564	2024-07-27	CUST-1140	Cash
52565	2024-09-19	CUST-1140	Debit Card
52566	2024-12-15	CUST-1140	Debit Card
52567	2025-04-08	CUST-1140	Credit Card
52568	2025-05-06	CUST-1140	Credit Card
52569	2025-06-03	CUST-1140	Credit Card
52570	2025-07-13	CUST-1140	Paypal
52571	2025-07-17	CUST-1140	Paypal
52572	2025-09-05	CUST-1140	Cash
52573	2025-11-06	CUST-1140	Paypal
52574	2025-11-10	CUST-1140	Cash
52575	2025-11-21	CUST-1140	Credit Card
52576	2025-11-27	CUST-1140	Credit Card
52577	2025-12-03	CUST-1140	Debit Card
52578	2025-12-04	CUST-1140	Debit Card
52579	2024-07-18	CUST-1141	Credit Card
52580	2024-12-08	CUST-1141	Debit Card
52581	2024-12-23	CUST-1141	Paypal
52582	2025-09-21	CUST-1141	Debit Card
52583	2025-07-20	CUST-1142	Credit Card
52584	2024-01-16	CUST-1143	Credit Card
52585	2024-04-17	CUST-1143	Credit Card
52586	2024-10-27	CUST-1143	Debit Card
52587	2025-07-29	CUST-1143	Cash
52588	2025-11-24	CUST-1143	Debit Card
52589	2024-02-03	CUST-1144	Cash
52590	2024-02-12	CUST-1144	Credit Card
52591	2024-03-03	CUST-1144	Debit Card
52592	2024-05-02	CUST-1144	Credit Card
52593	2024-05-07	CUST-1144	Credit Card
52594	2024-05-13	CUST-1144	Credit Card
52595	2024-06-03	CUST-1144	Cash
52596	2024-06-29	CUST-1144	Debit Card
52597	2024-07-06	CUST-1144	Paypal
52598	2024-08-23	CUST-1144	Debit Card
52599	2024-09-15	CUST-1144	Paypal
52600	2024-09-19	CUST-1144	Cash
52601	2024-10-08	CUST-1144	Credit Card
52602	2024-11-04	CUST-1144	Credit Card
52603	2024-11-11	CUST-1144	Debit Card
52604	2024-12-01	CUST-1144	Credit Card
52605	2024-12-19	CUST-1144	Credit Card
52606	2024-12-26	CUST-1144	Cash
52607	2024-12-28	CUST-1144	Credit Card
52608	2025-05-15	CUST-1144	Credit Card
52609	2025-05-29	CUST-1144	Credit Card
52610	2025-05-31	CUST-1144	Paypal
52611	2025-06-02	CUST-1144	Credit Card
52612	2025-07-17	CUST-1144	Credit Card
52613	2025-08-18	CUST-1144	Debit Card
52614	2025-08-23	CUST-1144	Debit Card
52615	2025-10-07	CUST-1144	Cash
52616	2025-10-09	CUST-1144	Credit Card
52617	2025-10-22	CUST-1144	Credit Card
52618	2025-10-22	CUST-1144	Debit Card
52619	2025-10-25	CUST-1144	Cash
52620	2025-11-04	CUST-1144	Credit Card
52621	2025-11-13	CUST-1144	Credit Card
52622	2025-11-30	CUST-1144	Debit Card
52623	2025-12-13	CUST-1144	Debit Card
52624	2025-12-31	CUST-1144	Cash
52625	2025-06-01	CUST-1145	Debit Card
52626	2025-01-26	CUST-1146	Paypal
52627	2024-03-29	CUST-1147	Cash
52628	2024-08-15	CUST-1147	Debit Card
52629	2024-11-19	CUST-1147	Debit Card
52630	2024-11-22	CUST-1147	Debit Card
52631	2024-12-12	CUST-1147	Debit Card
52632	2025-04-19	CUST-1147	Debit Card
52633	2025-12-03	CUST-1147	Debit Card
52634	2025-12-22	CUST-1147	Debit Card
52635	2025-12-24	CUST-1147	Credit Card
52636	2024-02-28	CUST-1148	Paypal
52637	2024-03-03	CUST-1148	Credit Card
52638	2024-03-15	CUST-1148	Debit Card
52639	2024-03-21	CUST-1148	Credit Card
52640	2024-03-27	CUST-1148	Debit Card
52641	2024-04-11	CUST-1148	Credit Card
52642	2024-05-03	CUST-1148	Credit Card
52643	2024-05-15	CUST-1148	Credit Card
52644	2024-06-27	CUST-1148	Paypal
52645	2024-07-01	CUST-1148	Cash
52646	2024-07-14	CUST-1148	Cash
52647	2024-07-18	CUST-1148	Debit Card
52648	2024-08-01	CUST-1148	Cash
52649	2024-08-01	CUST-1148	Debit Card
52650	2024-08-31	CUST-1148	Cash
52651	2024-10-06	CUST-1148	Cash
52652	2024-10-07	CUST-1148	Cash
52653	2024-10-10	CUST-1148	Credit Card
52654	2024-11-01	CUST-1148	Credit Card
52655	2024-12-02	CUST-1148	Credit Card
52656	2024-12-16	CUST-1148	Credit Card
52657	2025-01-07	CUST-1148	Cash
52658	2025-01-13	CUST-1148	Credit Card
52659	2025-01-25	CUST-1148	Debit Card
52660	2025-04-03	CUST-1148	Debit Card
52661	2025-05-02	CUST-1148	Credit Card
52662	2025-05-09	CUST-1148	Debit Card
52663	2025-06-03	CUST-1148	Cash
52664	2025-06-05	CUST-1148	Debit Card
52665	2025-06-06	CUST-1148	Credit Card
52666	2025-06-10	CUST-1148	Debit Card
52667	2025-06-11	CUST-1148	Cash
52668	2025-06-27	CUST-1148	Credit Card
52669	2025-07-21	CUST-1148	Credit Card
52670	2025-08-10	CUST-1148	Cash
52671	2025-08-12	CUST-1148	Credit Card
52672	2025-08-25	CUST-1148	Debit Card
52673	2025-09-08	CUST-1148	Debit Card
52674	2025-10-27	CUST-1148	Debit Card
52675	2025-10-28	CUST-1148	Debit Card
52676	2025-11-08	CUST-1148	Debit Card
52677	2025-11-14	CUST-1148	Credit Card
52678	2025-11-16	CUST-1148	Credit Card
52679	2025-11-19	CUST-1148	Cash
52680	2025-11-20	CUST-1148	Debit Card
52681	2025-11-30	CUST-1148	Credit Card
52682	2025-12-25	CUST-1148	Credit Card
52683	2024-02-21	CUST-1149	Cash
52684	2024-03-19	CUST-1149	Paypal
52685	2024-07-24	CUST-1149	Credit Card
52686	2024-09-14	CUST-1149	Cash
52687	2024-09-24	CUST-1149	Credit Card
52688	2024-10-01	CUST-1149	Cash
52689	2024-11-03	CUST-1149	Credit Card
52690	2025-03-10	CUST-1149	Debit Card
52691	2025-04-26	CUST-1149	Debit Card
52692	2024-02-13	CUST-1150	Paypal
52693	2024-02-25	CUST-1150	Cash
52694	2024-04-23	CUST-1150	Debit Card
52695	2024-05-15	CUST-1150	Cash
52696	2024-06-23	CUST-1150	Credit Card
52697	2024-06-26	CUST-1150	Debit Card
52698	2024-08-24	CUST-1150	Credit Card
52699	2024-10-26	CUST-1150	Credit Card
52700	2024-10-27	CUST-1150	Debit Card
52701	2024-11-02	CUST-1150	Credit Card
52702	2024-11-26	CUST-1150	Debit Card
52703	2025-01-16	CUST-1150	Debit Card
52704	2025-02-12	CUST-1150	Debit Card
52705	2025-04-16	CUST-1150	Paypal
52706	2025-04-27	CUST-1150	Debit Card
52707	2025-06-28	CUST-1150	Debit Card
52708	2025-09-06	CUST-1150	Debit Card
52709	2025-10-26	CUST-1150	Credit Card
52710	2025-12-14	CUST-1150	Cash
52711	2025-12-17	CUST-1150	Debit Card
52712	2025-12-23	CUST-1150	Debit Card
52713	2025-12-28	CUST-1150	Credit Card
52714	2025-03-01	CUST-1151	Debit Card
52715	2025-10-13	CUST-1151	Credit Card
52716	2025-11-13	CUST-1151	Cash
52717	2024-06-20	CUST-1152	Debit Card
52718	2024-10-28	CUST-1152	Credit Card
52719	2024-11-13	CUST-1152	Cash
52720	2024-12-06	CUST-1152	Paypal
52721	2025-05-14	CUST-1152	Debit Card
52722	2024-02-02	CUST-1153	Debit Card
52723	2024-05-02	CUST-1153	Cash
52724	2024-11-05	CUST-1153	Debit Card
52725	2024-12-03	CUST-1153	Debit Card
52726	2024-12-07	CUST-1153	Paypal
52727	2025-01-25	CUST-1153	Paypal
52728	2025-02-13	CUST-1153	Credit Card
52729	2025-04-20	CUST-1153	Paypal
52730	2025-06-05	CUST-1153	Debit Card
52731	2025-10-17	CUST-1153	Credit Card
52732	2025-11-22	CUST-1153	Debit Card
52733	2024-03-26	CUST-1154	Debit Card
52734	2024-04-26	CUST-1154	Paypal
52735	2024-05-29	CUST-1154	Debit Card
52736	2024-08-12	CUST-1154	Credit Card
52737	2024-08-16	CUST-1154	Debit Card
52738	2024-08-22	CUST-1154	Debit Card
52739	2024-09-06	CUST-1154	Debit Card
52740	2024-11-10	CUST-1154	Debit Card
52741	2025-04-19	CUST-1154	Paypal
52742	2025-05-14	CUST-1154	Credit Card
52743	2025-06-12	CUST-1154	Cash
52744	2025-07-15	CUST-1154	Cash
52745	2025-10-22	CUST-1154	Credit Card
52746	2025-11-06	CUST-1154	Debit Card
52747	2025-11-11	CUST-1154	Credit Card
52748	2024-04-14	CUST-1155	Paypal
52749	2024-06-19	CUST-1155	Cash
52750	2024-07-07	CUST-1155	Debit Card
52751	2024-07-21	CUST-1155	Credit Card
52752	2024-07-27	CUST-1155	Debit Card
52753	2024-07-29	CUST-1155	Debit Card
52754	2024-08-08	CUST-1155	Credit Card
52755	2024-10-19	CUST-1155	Cash
52756	2024-10-19	CUST-1155	Debit Card
52757	2024-12-10	CUST-1155	Debit Card
52758	2024-12-14	CUST-1155	Credit Card
52759	2025-06-14	CUST-1155	Debit Card
52760	2025-10-22	CUST-1155	Paypal
52761	2025-10-26	CUST-1155	Credit Card
52762	2025-12-13	CUST-1155	Debit Card
52763	2025-12-14	CUST-1155	Debit Card
52764	2024-05-27	CUST-1156	Debit Card
52765	2024-06-15	CUST-1156	Debit Card
52766	2024-12-09	CUST-1156	Cash
52767	2025-02-26	CUST-1156	Credit Card
52768	2025-06-15	CUST-1156	Cash
52769	2025-07-03	CUST-1156	Debit Card
52770	2025-08-19	CUST-1156	Credit Card
52771	2025-08-30	CUST-1156	Credit Card
52772	2025-10-22	CUST-1156	Credit Card
52773	2025-11-11	CUST-1156	Credit Card
52774	2024-04-21	CUST-1157	Paypal
52775	2024-07-18	CUST-1157	Credit Card
52776	2024-11-15	CUST-1157	Cash
52777	2024-12-21	CUST-1157	Debit Card
52778	2025-01-05	CUST-1157	Paypal
52779	2025-02-19	CUST-1157	Debit Card
52780	2025-03-02	CUST-1157	Cash
52781	2025-04-01	CUST-1157	Paypal
52782	2025-06-05	CUST-1157	Paypal
52783	2025-07-11	CUST-1157	Debit Card
52784	2025-12-10	CUST-1157	Credit Card
52785	2025-12-27	CUST-1157	Credit Card
52786	2025-12-30	CUST-1157	Credit Card
52787	2024-04-23	CUST-1158	Debit Card
52788	2024-06-09	CUST-1158	Credit Card
52789	2024-06-27	CUST-1158	Cash
52790	2024-11-22	CUST-1158	Credit Card
52791	2024-12-09	CUST-1158	Debit Card
52792	2025-02-25	CUST-1158	Debit Card
52793	2025-04-19	CUST-1158	Debit Card
52794	2025-05-05	CUST-1158	Cash
52795	2025-05-16	CUST-1158	Paypal
52796	2025-05-30	CUST-1158	Debit Card
52797	2025-07-20	CUST-1158	Credit Card
52798	2025-09-18	CUST-1158	Paypal
52799	2025-10-10	CUST-1158	Credit Card
52800	2025-10-21	CUST-1158	Debit Card
52801	2025-11-01	CUST-1158	Cash
52802	2025-11-20	CUST-1158	Credit Card
52803	2025-12-17	CUST-1158	Debit Card
52804	2024-01-02	CUST-1159	Debit Card
52805	2024-01-16	CUST-1159	Credit Card
52806	2024-01-25	CUST-1159	Paypal
52807	2024-03-13	CUST-1159	Debit Card
52808	2024-06-07	CUST-1159	Debit Card
52809	2024-07-06	CUST-1159	Paypal
52810	2024-07-07	CUST-1159	Credit Card
52811	2024-08-12	CUST-1159	Paypal
52812	2024-09-08	CUST-1159	Paypal
52813	2024-11-05	CUST-1159	Debit Card
52814	2024-11-14	CUST-1159	Paypal
52815	2024-11-18	CUST-1159	Debit Card
52816	2025-02-11	CUST-1159	Paypal
52817	2025-02-14	CUST-1159	Credit Card
52818	2025-03-27	CUST-1159	Debit Card
52819	2025-04-25	CUST-1159	Credit Card
52820	2025-06-27	CUST-1159	Debit Card
52821	2025-08-24	CUST-1159	Credit Card
52822	2025-09-24	CUST-1159	Paypal
52823	2025-11-04	CUST-1159	Debit Card
52824	2025-11-27	CUST-1159	Debit Card
52825	2025-12-21	CUST-1159	Paypal
52826	2024-04-20	CUST-1160	Debit Card
52827	2024-05-21	CUST-1160	Paypal
52828	2024-06-05	CUST-1160	Debit Card
52829	2024-06-17	CUST-1160	Debit Card
52830	2024-08-14	CUST-1160	Paypal
52831	2024-10-14	CUST-1160	Credit Card
52832	2024-11-07	CUST-1160	Paypal
52833	2024-11-11	CUST-1160	Debit Card
52834	2024-11-18	CUST-1160	Paypal
52835	2024-11-27	CUST-1160	Credit Card
52836	2024-12-17	CUST-1160	Credit Card
52837	2025-01-30	CUST-1160	Debit Card
52838	2025-03-25	CUST-1160	Cash
52839	2025-03-25	CUST-1160	Debit Card
52840	2025-04-18	CUST-1160	Paypal
52841	2025-05-03	CUST-1160	Credit Card
52842	2025-05-25	CUST-1160	Paypal
52843	2025-06-23	CUST-1160	Paypal
52844	2025-07-07	CUST-1160	Paypal
52845	2025-07-17	CUST-1160	Debit Card
52846	2025-07-19	CUST-1160	Debit Card
52847	2025-08-19	CUST-1160	Debit Card
52848	2025-10-17	CUST-1160	Debit Card
52849	2025-10-19	CUST-1160	Credit Card
52850	2025-10-20	CUST-1160	Credit Card
52851	2025-11-25	CUST-1160	Debit Card
52852	2025-12-19	CUST-1160	Credit Card
52853	2025-10-19	CUST-1161	Debit Card
52854	2025-11-29	CUST-1161	Debit Card
52855	2024-01-31	CUST-1163	Credit Card
52856	2024-03-11	CUST-1163	Credit Card
52857	2024-03-25	CUST-1163	Cash
52858	2024-04-29	CUST-1163	Debit Card
52859	2024-05-24	CUST-1163	Debit Card
52860	2024-09-23	CUST-1163	Debit Card
52861	2024-09-29	CUST-1163	Credit Card
52862	2024-09-30	CUST-1163	Credit Card
52863	2024-11-12	CUST-1163	Debit Card
52864	2024-11-19	CUST-1163	Debit Card
52865	2024-11-20	CUST-1163	Credit Card
52866	2024-11-23	CUST-1163	Credit Card
52867	2024-12-07	CUST-1163	Cash
52868	2024-12-11	CUST-1163	Paypal
52869	2025-02-06	CUST-1163	Cash
52870	2025-02-22	CUST-1163	Cash
52871	2025-02-25	CUST-1163	Cash
52872	2025-02-25	CUST-1163	Credit Card
52873	2025-03-13	CUST-1163	Credit Card
52874	2025-03-17	CUST-1163	Credit Card
52875	2025-04-19	CUST-1163	Debit Card
52876	2025-04-21	CUST-1163	Debit Card
52877	2025-05-18	CUST-1163	Credit Card
52878	2025-06-11	CUST-1163	Credit Card
52879	2025-06-17	CUST-1163	Credit Card
52880	2025-07-11	CUST-1163	Credit Card
52881	2025-08-03	CUST-1163	Credit Card
52882	2025-08-17	CUST-1163	Credit Card
52883	2025-08-21	CUST-1163	Cash
52884	2025-09-03	CUST-1163	Paypal
52885	2025-10-30	CUST-1163	Credit Card
52886	2025-11-20	CUST-1163	Credit Card
52887	2025-11-26	CUST-1163	Cash
52888	2025-12-01	CUST-1163	Cash
52889	2025-12-07	CUST-1163	Paypal
52890	2025-12-15	CUST-1163	Credit Card
52891	2025-12-20	CUST-1163	Paypal
52892	2025-12-24	CUST-1163	Credit Card
52893	2025-12-25	CUST-1163	Credit Card
52894	2025-12-29	CUST-1163	Credit Card
52895	2024-01-22	CUST-1164	Credit Card
52896	2024-02-20	CUST-1164	Credit Card
52897	2024-02-22	CUST-1164	Debit Card
52898	2024-02-26	CUST-1164	Paypal
52899	2024-03-06	CUST-1164	Credit Card
52900	2024-03-11	CUST-1164	Credit Card
52901	2024-03-19	CUST-1164	Paypal
52902	2024-03-23	CUST-1164	Credit Card
52903	2024-03-26	CUST-1164	Credit Card
52904	2024-04-19	CUST-1164	Cash
52905	2024-04-26	CUST-1164	Debit Card
52906	2024-05-19	CUST-1164	Debit Card
52907	2024-05-24	CUST-1164	Cash
52908	2024-06-06	CUST-1164	Debit Card
52909	2024-06-08	CUST-1164	Debit Card
52910	2024-06-12	CUST-1164	Paypal
52911	2024-07-15	CUST-1164	Debit Card
52912	2024-08-12	CUST-1164	Cash
52913	2024-08-13	CUST-1164	Credit Card
52914	2024-08-17	CUST-1164	Cash
52915	2024-08-25	CUST-1164	Debit Card
52916	2024-10-03	CUST-1164	Credit Card
52917	2024-10-09	CUST-1164	Credit Card
52918	2024-10-13	CUST-1164	Debit Card
52919	2024-10-26	CUST-1164	Credit Card
52920	2024-11-10	CUST-1164	Credit Card
52921	2024-11-15	CUST-1164	Debit Card
52922	2025-01-07	CUST-1164	Credit Card
52923	2025-03-08	CUST-1164	Paypal
52924	2025-03-17	CUST-1164	Debit Card
52925	2025-06-15	CUST-1164	Debit Card
52926	2025-07-31	CUST-1164	Credit Card
52927	2025-08-12	CUST-1164	Credit Card
52928	2025-08-18	CUST-1164	Cash
52929	2025-09-02	CUST-1164	Cash
52930	2025-09-07	CUST-1164	Cash
52931	2025-09-11	CUST-1164	Debit Card
52932	2025-09-21	CUST-1164	Debit Card
52933	2025-10-09	CUST-1164	Debit Card
52934	2025-10-14	CUST-1164	Cash
52935	2025-10-21	CUST-1164	Credit Card
52936	2025-10-28	CUST-1164	Cash
52937	2025-11-05	CUST-1164	Debit Card
52938	2025-11-10	CUST-1164	Cash
52939	2025-11-21	CUST-1164	Credit Card
52940	2025-11-22	CUST-1164	Credit Card
52941	2025-12-09	CUST-1164	Credit Card
52942	2025-12-14	CUST-1164	Credit Card
52943	2025-12-26	CUST-1164	Credit Card
52944	2024-06-13	CUST-1165	Credit Card
52945	2024-06-27	CUST-1165	Credit Card
52946	2025-10-30	CUST-1165	Debit Card
52947	2025-11-01	CUST-1165	Credit Card
52948	2024-02-10	CUST-1167	Paypal
52949	2024-04-18	CUST-1167	Credit Card
52950	2024-06-15	CUST-1167	Debit Card
52951	2024-06-18	CUST-1167	Paypal
52952	2024-07-22	CUST-1167	Debit Card
52953	2024-07-28	CUST-1167	Credit Card
52954	2024-09-03	CUST-1167	Paypal
52955	2024-12-23	CUST-1167	Credit Card
52956	2025-05-17	CUST-1167	Debit Card
52957	2025-06-05	CUST-1167	Paypal
52958	2025-06-21	CUST-1167	Debit Card
52959	2025-06-27	CUST-1167	Credit Card
52960	2025-08-02	CUST-1167	Credit Card
52961	2025-08-21	CUST-1167	Credit Card
52962	2025-11-05	CUST-1167	Credit Card
52963	2024-01-08	CUST-1168	Credit Card
52964	2024-02-09	CUST-1168	Cash
52965	2024-03-14	CUST-1168	Debit Card
52966	2024-05-17	CUST-1168	Paypal
52967	2024-05-22	CUST-1168	Debit Card
52968	2024-05-24	CUST-1168	Credit Card
52969	2024-05-25	CUST-1168	Credit Card
52970	2024-06-11	CUST-1168	Debit Card
52971	2024-07-15	CUST-1168	Credit Card
52972	2024-07-19	CUST-1168	Debit Card
52973	2024-08-10	CUST-1168	Paypal
52974	2024-08-14	CUST-1168	Debit Card
52975	2024-09-15	CUST-1168	Debit Card
52976	2024-10-02	CUST-1168	Cash
52977	2024-10-06	CUST-1168	Credit Card
52978	2024-10-09	CUST-1168	Debit Card
52979	2024-10-21	CUST-1168	Credit Card
52980	2024-11-09	CUST-1168	Cash
52981	2024-12-23	CUST-1168	Credit Card
52982	2025-01-02	CUST-1168	Debit Card
52983	2025-01-23	CUST-1168	Credit Card
52984	2025-01-28	CUST-1168	Credit Card
52985	2025-02-02	CUST-1168	Paypal
52986	2025-02-20	CUST-1168	Credit Card
52987	2025-04-20	CUST-1168	Cash
52988	2025-05-03	CUST-1168	Credit Card
52989	2025-05-08	CUST-1168	Paypal
52990	2025-05-10	CUST-1168	Credit Card
52991	2025-05-13	CUST-1168	Debit Card
52992	2025-05-14	CUST-1168	Debit Card
52993	2025-05-26	CUST-1168	Debit Card
52994	2025-07-13	CUST-1168	Debit Card
52995	2025-09-30	CUST-1168	Debit Card
52996	2025-10-02	CUST-1168	Credit Card
52997	2025-10-09	CUST-1168	Credit Card
52998	2025-10-13	CUST-1168	Credit Card
52999	2025-11-15	CUST-1168	Cash
53000	2025-11-22	CUST-1168	Paypal
53001	2025-12-23	CUST-1168	Paypal
53002	2024-01-14	CUST-1169	Credit Card
53003	2024-02-07	CUST-1169	Debit Card
53004	2024-03-02	CUST-1169	Debit Card
53005	2024-04-19	CUST-1169	Paypal
53006	2024-04-24	CUST-1169	Credit Card
53007	2024-05-17	CUST-1169	Paypal
53008	2024-05-23	CUST-1169	Debit Card
53009	2024-05-26	CUST-1169	Credit Card
53010	2024-07-01	CUST-1169	Debit Card
53011	2024-07-27	CUST-1169	Debit Card
53012	2024-08-09	CUST-1169	Credit Card
53013	2024-08-13	CUST-1169	Debit Card
53014	2024-08-18	CUST-1169	Cash
53015	2024-08-20	CUST-1169	Debit Card
53016	2024-09-05	CUST-1169	Paypal
53017	2024-09-08	CUST-1169	Credit Card
53018	2024-09-11	CUST-1169	Credit Card
53019	2024-09-13	CUST-1169	Paypal
53020	2024-09-14	CUST-1169	Paypal
53021	2024-09-19	CUST-1169	Credit Card
53022	2024-09-24	CUST-1169	Debit Card
53023	2024-09-26	CUST-1169	Cash
53024	2024-10-28	CUST-1169	Paypal
53025	2024-11-01	CUST-1169	Credit Card
53026	2024-11-09	CUST-1169	Cash
53027	2024-11-14	CUST-1169	Debit Card
53028	2024-11-20	CUST-1169	Credit Card
53029	2024-11-22	CUST-1169	Credit Card
53030	2024-11-29	CUST-1169	Cash
53031	2024-12-03	CUST-1169	Debit Card
53032	2024-12-06	CUST-1169	Credit Card
53033	2024-12-09	CUST-1169	Credit Card
53034	2024-12-18	CUST-1169	Credit Card
53035	2024-12-20	CUST-1169	Debit Card
53036	2024-12-26	CUST-1169	Credit Card
53037	2025-01-12	CUST-1169	Debit Card
53038	2025-01-22	CUST-1169	Debit Card
53039	2025-02-04	CUST-1169	Credit Card
53040	2025-02-17	CUST-1169	Credit Card
53041	2025-02-20	CUST-1169	Credit Card
53042	2025-03-11	CUST-1169	Debit Card
53043	2025-03-15	CUST-1169	Cash
53044	2025-03-17	CUST-1169	Credit Card
53045	2025-04-17	CUST-1169	Credit Card
53046	2025-05-04	CUST-1169	Credit Card
53047	2025-05-06	CUST-1169	Cash
53048	2025-05-09	CUST-1169	Cash
53049	2025-05-11	CUST-1169	Paypal
53050	2025-05-24	CUST-1169	Paypal
53051	2025-06-14	CUST-1169	Cash
53052	2025-07-17	CUST-1169	Paypal
53053	2025-08-03	CUST-1169	Debit Card
53054	2025-08-08	CUST-1169	Cash
53055	2025-08-15	CUST-1169	Credit Card
53056	2025-08-20	CUST-1169	Cash
53057	2025-08-28	CUST-1169	Paypal
53058	2025-09-12	CUST-1169	Credit Card
53059	2025-09-15	CUST-1169	Cash
53060	2025-09-27	CUST-1169	Cash
53061	2025-09-28	CUST-1169	Credit Card
53062	2025-10-04	CUST-1169	Debit Card
53063	2025-10-07	CUST-1169	Paypal
53064	2025-10-19	CUST-1169	Paypal
53065	2025-11-04	CUST-1169	Credit Card
53066	2025-11-14	CUST-1169	Debit Card
53067	2025-11-15	CUST-1169	Debit Card
53068	2025-11-17	CUST-1169	Debit Card
53069	2025-11-18	CUST-1169	Credit Card
53070	2025-12-02	CUST-1169	Credit Card
53071	2025-12-03	CUST-1169	Cash
53072	2025-12-04	CUST-1169	Credit Card
53073	2025-12-04	CUST-1169	Debit Card
53074	2025-12-15	CUST-1169	Paypal
53075	2025-12-18	CUST-1169	Credit Card
53076	2025-12-21	CUST-1169	Credit Card
53077	2025-12-25	CUST-1169	Debit Card
53078	2025-12-27	CUST-1169	Cash
53079	2025-12-29	CUST-1169	Credit Card
53080	2024-01-26	CUST-1170	Debit Card
53081	2024-03-21	CUST-1170	Debit Card
53082	2024-03-24	CUST-1170	Debit Card
53083	2024-04-11	CUST-1170	Credit Card
53084	2024-05-19	CUST-1170	Debit Card
53085	2024-06-21	CUST-1170	Debit Card
53086	2024-06-26	CUST-1170	Debit Card
53087	2024-07-29	CUST-1170	Credit Card
53088	2024-08-03	CUST-1170	Paypal
53089	2024-08-11	CUST-1170	Debit Card
53090	2024-09-12	CUST-1170	Debit Card
53091	2024-10-27	CUST-1170	Debit Card
53092	2024-12-19	CUST-1170	Debit Card
53093	2025-03-04	CUST-1170	Debit Card
53094	2025-03-29	CUST-1170	Cash
53095	2025-07-13	CUST-1170	Debit Card
53096	2025-10-02	CUST-1170	Debit Card
53097	2025-10-30	CUST-1170	Credit Card
53098	2025-11-01	CUST-1170	Debit Card
53099	2024-06-20	CUST-1171	Cash
53100	2024-08-05	CUST-1171	Debit Card
53101	2024-11-28	CUST-1171	Credit Card
53102	2024-12-01	CUST-1171	Credit Card
53103	2024-12-18	CUST-1171	Credit Card
53104	2024-12-25	CUST-1171	Paypal
53105	2025-04-30	CUST-1171	Debit Card
53106	2025-10-04	CUST-1171	Cash
53107	2025-10-05	CUST-1171	Debit Card
53108	2024-04-03	CUST-1172	Credit Card
53109	2024-05-01	CUST-1172	Debit Card
53110	2025-12-11	CUST-1172	Credit Card
53111	2024-04-04	CUST-1173	Credit Card
53112	2024-04-13	CUST-1173	Credit Card
53113	2024-05-26	CUST-1173	Credit Card
53114	2024-08-22	CUST-1173	Debit Card
53115	2024-08-29	CUST-1173	Debit Card
53116	2024-10-21	CUST-1173	Credit Card
53117	2024-11-24	CUST-1173	Debit Card
53118	2025-03-20	CUST-1173	Credit Card
53119	2025-07-02	CUST-1173	Debit Card
53120	2025-10-25	CUST-1173	Paypal
53121	2025-12-28	CUST-1173	Paypal
53122	2024-02-22	CUST-1174	Credit Card
53123	2024-06-26	CUST-1174	Cash
53124	2024-12-15	CUST-1174	Debit Card
53125	2025-03-07	CUST-1174	Paypal
53126	2025-04-14	CUST-1174	Paypal
53127	2025-08-03	CUST-1174	Debit Card
53128	2025-08-11	CUST-1174	Paypal
53129	2025-11-19	CUST-1174	Debit Card
53130	2025-11-24	CUST-1174	Credit Card
53131	2025-03-17	CUST-1175	Cash
53132	2025-06-22	CUST-1175	Credit Card
53133	2025-10-31	CUST-1175	Credit Card
53134	2024-02-05	CUST-1176	Credit Card
53135	2024-02-11	CUST-1176	Debit Card
53136	2024-03-09	CUST-1176	Credit Card
53137	2024-03-12	CUST-1176	Cash
53138	2024-03-12	CUST-1176	Debit Card
53139	2024-04-12	CUST-1176	Cash
53140	2024-04-20	CUST-1176	Debit Card
53141	2024-04-21	CUST-1176	Cash
53142	2024-05-12	CUST-1176	Paypal
53143	2024-05-19	CUST-1176	Credit Card
53144	2024-05-22	CUST-1176	Credit Card
53145	2024-05-28	CUST-1176	Credit Card
53146	2024-06-12	CUST-1176	Debit Card
53147	2024-06-15	CUST-1176	Debit Card
53148	2024-06-18	CUST-1176	Cash
53149	2024-06-19	CUST-1176	Credit Card
53150	2024-06-25	CUST-1176	Cash
53151	2024-07-04	CUST-1176	Credit Card
53152	2024-07-19	CUST-1176	Debit Card
53153	2024-08-11	CUST-1176	Paypal
53154	2024-08-12	CUST-1176	Cash
53155	2024-08-14	CUST-1176	Debit Card
53156	2024-08-22	CUST-1176	Cash
53157	2024-08-23	CUST-1176	Paypal
53158	2024-08-29	CUST-1176	Credit Card
53159	2024-09-15	CUST-1176	Debit Card
53160	2024-09-21	CUST-1176	Credit Card
53161	2024-09-30	CUST-1176	Debit Card
53162	2024-10-02	CUST-1176	Paypal
53163	2024-10-05	CUST-1176	Debit Card
53164	2024-10-12	CUST-1176	Credit Card
53165	2024-10-14	CUST-1176	Debit Card
53166	2024-10-22	CUST-1176	Debit Card
53167	2024-10-30	CUST-1176	Cash
53168	2024-10-31	CUST-1176	Paypal
53169	2024-11-01	CUST-1176	Debit Card
53170	2024-11-06	CUST-1176	Cash
53171	2024-11-19	CUST-1176	Credit Card
53172	2024-12-02	CUST-1176	Credit Card
53173	2024-12-10	CUST-1176	Debit Card
53174	2024-12-18	CUST-1176	Debit Card
53175	2024-12-20	CUST-1176	Credit Card
53176	2024-12-20	CUST-1176	Debit Card
53177	2024-12-21	CUST-1176	Debit Card
53178	2024-12-29	CUST-1176	Cash
53179	2025-01-16	CUST-1176	Credit Card
53180	2025-01-31	CUST-1176	Cash
53181	2025-01-31	CUST-1176	Debit Card
53182	2025-02-04	CUST-1176	Debit Card
53183	2025-02-05	CUST-1176	Credit Card
53184	2025-02-09	CUST-1176	Debit Card
53185	2025-02-13	CUST-1176	Credit Card
53186	2025-02-22	CUST-1176	Debit Card
53187	2025-02-27	CUST-1176	Credit Card
53188	2025-03-13	CUST-1176	Credit Card
53189	2025-03-19	CUST-1176	Credit Card
53190	2025-03-24	CUST-1176	Credit Card
53191	2025-04-15	CUST-1176	Credit Card
53192	2025-04-18	CUST-1176	Credit Card
53193	2025-04-18	CUST-1176	Debit Card
53194	2025-04-25	CUST-1176	Debit Card
53195	2025-04-29	CUST-1176	Credit Card
53196	2025-05-02	CUST-1176	Debit Card
53197	2025-05-10	CUST-1176	Credit Card
53198	2025-05-14	CUST-1176	Cash
53199	2025-05-31	CUST-1176	Credit Card
53200	2025-06-10	CUST-1176	Paypal
53201	2025-06-12	CUST-1176	Credit Card
53202	2025-06-14	CUST-1176	Credit Card
53203	2025-07-13	CUST-1176	Debit Card
53204	2025-07-28	CUST-1176	Credit Card
53205	2025-07-28	CUST-1176	Debit Card
53206	2025-08-06	CUST-1176	Credit Card
53207	2025-08-16	CUST-1176	Credit Card
53208	2025-08-16	CUST-1176	Debit Card
53209	2025-08-21	CUST-1176	Credit Card
53210	2025-08-22	CUST-1176	Credit Card
53211	2025-08-27	CUST-1176	Credit Card
53212	2025-09-27	CUST-1176	Credit Card
53213	2025-09-28	CUST-1176	Credit Card
53214	2025-09-28	CUST-1176	Debit Card
53215	2025-09-29	CUST-1176	Debit Card
53216	2025-10-01	CUST-1176	Debit Card
53217	2025-10-02	CUST-1176	Debit Card
53218	2025-10-07	CUST-1176	Credit Card
53219	2025-10-09	CUST-1176	Debit Card
53220	2025-10-24	CUST-1176	Cash
53221	2025-11-05	CUST-1176	Cash
53222	2025-11-09	CUST-1176	Cash
53223	2025-11-09	CUST-1176	Debit Card
53224	2025-11-28	CUST-1176	Debit Card
53225	2025-12-20	CUST-1176	Credit Card
53226	2025-12-28	CUST-1176	Debit Card
53227	2024-01-06	CUST-1177	Debit Card
53228	2024-01-26	CUST-1177	Debit Card
53229	2024-03-14	CUST-1177	Paypal
53230	2024-03-16	CUST-1177	Cash
53231	2024-03-19	CUST-1177	Paypal
53232	2024-04-01	CUST-1177	Debit Card
53233	2024-04-03	CUST-1177	Cash
53234	2024-04-17	CUST-1177	Debit Card
53235	2024-04-22	CUST-1177	Credit Card
53236	2024-04-23	CUST-1177	Cash
53237	2024-04-30	CUST-1177	Credit Card
53238	2024-05-23	CUST-1177	Credit Card
53239	2024-06-13	CUST-1177	Debit Card
53240	2024-06-23	CUST-1177	Credit Card
53241	2024-07-03	CUST-1177	Cash
53242	2024-07-03	CUST-1177	Credit Card
53243	2024-07-12	CUST-1177	Debit Card
53244	2024-07-20	CUST-1177	Debit Card
53245	2024-08-02	CUST-1177	Cash
53246	2024-08-04	CUST-1177	Cash
53247	2024-08-06	CUST-1177	Cash
53248	2024-08-16	CUST-1177	Credit Card
53249	2024-08-28	CUST-1177	Credit Card
53250	2024-09-08	CUST-1177	Credit Card
53251	2024-09-09	CUST-1177	Debit Card
53252	2024-09-18	CUST-1177	Credit Card
53253	2024-09-22	CUST-1177	Credit Card
53254	2024-09-27	CUST-1177	Credit Card
53255	2024-10-10	CUST-1177	Credit Card
53256	2024-10-14	CUST-1177	Credit Card
53257	2024-10-26	CUST-1177	Paypal
53258	2024-10-28	CUST-1177	Paypal
53259	2024-11-05	CUST-1177	Credit Card
53260	2024-11-05	CUST-1177	Paypal
53261	2024-11-20	CUST-1177	Credit Card
53262	2024-12-06	CUST-1177	Debit Card
53263	2024-12-07	CUST-1177	Debit Card
53264	2024-12-10	CUST-1177	Credit Card
53265	2025-01-09	CUST-1177	Debit Card
53266	2025-01-23	CUST-1177	Paypal
53267	2025-02-14	CUST-1177	Credit Card
53268	2025-03-18	CUST-1177	Credit Card
53269	2025-03-18	CUST-1177	Debit Card
53270	2025-03-31	CUST-1177	Cash
53271	2025-04-05	CUST-1177	Paypal
53272	2025-04-17	CUST-1177	Cash
53273	2025-04-17	CUST-1177	Debit Card
53274	2025-05-07	CUST-1177	Credit Card
53275	2025-06-01	CUST-1177	Paypal
53276	2025-06-03	CUST-1177	Debit Card
53277	2025-06-05	CUST-1177	Credit Card
53278	2025-06-07	CUST-1177	Credit Card
53279	2025-06-18	CUST-1177	Debit Card
53280	2025-07-10	CUST-1177	Cash
53281	2025-07-11	CUST-1177	Paypal
53282	2025-07-26	CUST-1177	Debit Card
53283	2025-08-16	CUST-1177	Credit Card
53284	2025-08-17	CUST-1177	Cash
53285	2025-10-04	CUST-1177	Credit Card
53286	2025-10-05	CUST-1177	Cash
53287	2025-10-05	CUST-1177	Paypal
53288	2025-10-07	CUST-1177	Credit Card
53289	2025-10-13	CUST-1177	Debit Card
53290	2025-10-16	CUST-1177	Credit Card
53291	2025-10-17	CUST-1177	Paypal
53292	2025-10-19	CUST-1177	Cash
53293	2025-10-28	CUST-1177	Credit Card
53294	2025-11-06	CUST-1177	Debit Card
53295	2025-11-27	CUST-1177	Debit Card
53296	2025-12-04	CUST-1177	Credit Card
53297	2025-12-05	CUST-1177	Debit Card
53298	2025-12-31	CUST-1177	Debit Card
53299	2024-03-04	CUST-1178	Paypal
53300	2024-04-06	CUST-1178	Paypal
53301	2024-04-10	CUST-1178	Credit Card
53302	2024-04-28	CUST-1178	Cash
53303	2024-05-09	CUST-1178	Credit Card
53304	2024-05-18	CUST-1178	Cash
53305	2024-05-18	CUST-1178	Credit Card
53306	2024-05-24	CUST-1178	Credit Card
53307	2024-06-03	CUST-1178	Credit Card
53308	2024-06-19	CUST-1178	Debit Card
53309	2024-07-06	CUST-1178	Cash
53310	2024-08-13	CUST-1178	Credit Card
53311	2024-08-23	CUST-1178	Debit Card
53312	2024-09-08	CUST-1178	Paypal
53313	2024-09-27	CUST-1178	Credit Card
53314	2024-10-25	CUST-1178	Paypal
53315	2024-10-30	CUST-1178	Credit Card
53316	2024-11-04	CUST-1178	Cash
53317	2024-11-28	CUST-1178	Paypal
53318	2024-12-09	CUST-1178	Credit Card
53319	2024-12-12	CUST-1178	Paypal
53320	2024-12-21	CUST-1178	Credit Card
53321	2024-12-24	CUST-1178	Credit Card
53322	2024-12-28	CUST-1178	Debit Card
53323	2025-01-19	CUST-1178	Cash
53324	2025-02-03	CUST-1178	Credit Card
53325	2025-02-06	CUST-1178	Cash
53326	2025-02-14	CUST-1178	Credit Card
53327	2025-03-06	CUST-1178	Credit Card
53328	2025-04-30	CUST-1178	Debit Card
53329	2025-05-18	CUST-1178	Credit Card
53330	2025-05-28	CUST-1178	Debit Card
53331	2025-06-17	CUST-1178	Paypal
53332	2025-07-01	CUST-1178	Credit Card
53333	2025-07-19	CUST-1178	Cash
53334	2025-07-25	CUST-1178	Debit Card
53335	2025-08-06	CUST-1178	Credit Card
53336	2025-08-30	CUST-1178	Credit Card
53337	2025-09-01	CUST-1178	Credit Card
53338	2025-09-04	CUST-1178	Credit Card
53339	2025-09-18	CUST-1178	Debit Card
53340	2025-09-29	CUST-1178	Credit Card
53341	2025-10-25	CUST-1178	Debit Card
53342	2025-11-09	CUST-1178	Paypal
53343	2025-11-16	CUST-1178	Credit Card
53344	2025-11-23	CUST-1178	Debit Card
53345	2025-12-01	CUST-1178	Cash
53346	2025-12-22	CUST-1178	Credit Card
53347	2024-02-05	CUST-1179	Credit Card
53348	2024-05-27	CUST-1179	Paypal
53349	2024-09-19	CUST-1179	Debit Card
53350	2025-07-20	CUST-1179	Paypal
53351	2024-01-10	CUST-1180	Credit Card
53352	2024-02-18	CUST-1180	Credit Card
53353	2024-02-27	CUST-1180	Debit Card
53354	2024-03-04	CUST-1180	Cash
53355	2024-04-09	CUST-1180	Debit Card
53356	2024-04-15	CUST-1180	Credit Card
53357	2024-06-14	CUST-1180	Credit Card
53358	2024-08-28	CUST-1180	Paypal
53359	2024-10-17	CUST-1180	Paypal
53360	2024-10-18	CUST-1180	Paypal
53361	2024-12-02	CUST-1180	Debit Card
53362	2025-01-27	CUST-1180	Cash
53363	2025-02-28	CUST-1180	Paypal
53364	2025-04-08	CUST-1180	Credit Card
53365	2025-05-21	CUST-1180	Debit Card
53366	2025-07-22	CUST-1180	Credit Card
53367	2025-07-23	CUST-1180	Credit Card
53368	2025-08-11	CUST-1180	Cash
53369	2025-11-21	CUST-1180	Debit Card
53370	2025-11-30	CUST-1180	Credit Card
53371	2024-01-16	CUST-1181	Credit Card
53372	2024-01-23	CUST-1181	Debit Card
53373	2024-01-29	CUST-1181	Debit Card
53374	2024-02-07	CUST-1181	Paypal
53375	2024-02-16	CUST-1181	Credit Card
53376	2024-05-06	CUST-1181	Cash
53377	2024-05-15	CUST-1181	Credit Card
53378	2024-08-17	CUST-1181	Cash
53379	2024-09-04	CUST-1181	Debit Card
53380	2024-10-11	CUST-1181	Debit Card
53381	2024-12-07	CUST-1181	Credit Card
53382	2024-12-10	CUST-1181	Cash
53383	2024-12-19	CUST-1181	Credit Card
53384	2024-12-29	CUST-1181	Credit Card
53385	2025-02-18	CUST-1181	Cash
53386	2025-03-07	CUST-1181	Credit Card
53387	2025-05-07	CUST-1181	Debit Card
53388	2025-06-05	CUST-1181	Debit Card
53389	2025-06-24	CUST-1181	Debit Card
53390	2025-06-29	CUST-1181	Cash
53391	2025-07-03	CUST-1181	Credit Card
53392	2025-07-31	CUST-1181	Credit Card
53393	2025-08-10	CUST-1181	Cash
53394	2025-10-19	CUST-1181	Cash
53395	2025-12-20	CUST-1181	Cash
53396	2025-12-23	CUST-1181	Cash
53397	2025-12-25	CUST-1181	Debit Card
53398	2024-01-24	CUST-1182	Credit Card
53399	2024-05-02	CUST-1182	Credit Card
53400	2024-09-17	CUST-1182	Credit Card
53401	2024-10-10	CUST-1182	Paypal
53402	2024-11-04	CUST-1182	Debit Card
53403	2024-12-04	CUST-1182	Credit Card
53404	2024-12-16	CUST-1182	Credit Card
53405	2025-01-07	CUST-1182	Paypal
53406	2025-02-23	CUST-1182	Credit Card
53407	2025-05-02	CUST-1182	Paypal
53408	2025-05-11	CUST-1182	Debit Card
53409	2025-08-03	CUST-1182	Credit Card
53410	2025-08-17	CUST-1182	Credit Card
53411	2025-11-01	CUST-1182	Paypal
53412	2025-12-14	CUST-1182	Debit Card
53413	2025-12-19	CUST-1182	Debit Card
53414	2025-12-21	CUST-1182	Cash
53415	2024-02-20	CUST-1183	Debit Card
53416	2024-03-09	CUST-1183	Debit Card
53417	2024-03-11	CUST-1183	Debit Card
53418	2024-03-13	CUST-1183	Credit Card
53419	2024-04-15	CUST-1183	Credit Card
53420	2024-04-25	CUST-1183	Debit Card
53421	2024-04-26	CUST-1183	Paypal
53422	2024-05-24	CUST-1183	Debit Card
53423	2024-06-09	CUST-1183	Debit Card
53424	2024-06-20	CUST-1183	Credit Card
53425	2024-06-23	CUST-1183	Credit Card
53426	2024-06-25	CUST-1183	Credit Card
53427	2024-07-15	CUST-1183	Credit Card
53428	2024-07-19	CUST-1183	Credit Card
53429	2024-08-03	CUST-1183	Cash
53430	2024-08-14	CUST-1183	Credit Card
53431	2024-10-03	CUST-1183	Debit Card
53432	2024-10-09	CUST-1183	Debit Card
53433	2024-10-10	CUST-1183	Cash
53434	2024-10-16	CUST-1183	Debit Card
53435	2024-10-24	CUST-1183	Credit Card
53436	2024-10-27	CUST-1183	Debit Card
53437	2024-12-02	CUST-1183	Cash
53438	2024-12-28	CUST-1183	Debit Card
53439	2025-01-29	CUST-1183	Cash
53440	2025-02-13	CUST-1183	Debit Card
53441	2025-03-17	CUST-1183	Debit Card
53442	2025-03-18	CUST-1183	Paypal
53443	2025-03-19	CUST-1183	Credit Card
53444	2025-04-04	CUST-1183	Credit Card
53445	2025-04-08	CUST-1183	Debit Card
53446	2025-04-14	CUST-1183	Debit Card
53447	2025-04-19	CUST-1183	Debit Card
53448	2025-05-14	CUST-1183	Credit Card
53449	2025-06-03	CUST-1183	Cash
53450	2025-06-19	CUST-1183	Credit Card
53451	2025-06-25	CUST-1183	Debit Card
53452	2025-08-20	CUST-1183	Credit Card
53453	2025-08-24	CUST-1183	Paypal
53454	2025-08-29	CUST-1183	Credit Card
53455	2025-09-09	CUST-1183	Credit Card
53456	2025-09-29	CUST-1183	Credit Card
53457	2025-10-05	CUST-1183	Cash
53458	2025-11-07	CUST-1183	Debit Card
53459	2025-12-06	CUST-1183	Paypal
53460	2025-12-07	CUST-1183	Credit Card
53461	2024-02-03	CUST-1184	Credit Card
53462	2024-02-21	CUST-1184	Cash
53463	2024-05-28	CUST-1184	Credit Card
53464	2024-06-04	CUST-1184	Credit Card
53465	2024-07-08	CUST-1184	Credit Card
53466	2024-07-25	CUST-1184	Paypal
53467	2024-08-12	CUST-1184	Credit Card
53468	2024-08-28	CUST-1184	Debit Card
53469	2024-10-24	CUST-1184	Cash
53470	2024-11-01	CUST-1184	Credit Card
53471	2024-11-12	CUST-1184	Debit Card
53472	2024-11-18	CUST-1184	Credit Card
53473	2025-02-13	CUST-1184	Debit Card
53474	2025-02-23	CUST-1184	Debit Card
53475	2025-06-05	CUST-1184	Debit Card
53476	2025-07-11	CUST-1184	Cash
53477	2025-09-05	CUST-1184	Debit Card
53478	2025-09-26	CUST-1184	Debit Card
53479	2025-10-08	CUST-1184	Credit Card
53480	2025-10-12	CUST-1184	Cash
53481	2025-11-13	CUST-1184	Credit Card
53482	2025-12-01	CUST-1184	Cash
53483	2025-12-06	CUST-1184	Credit Card
53484	2025-12-08	CUST-1184	Debit Card
53485	2025-12-14	CUST-1184	Debit Card
53486	2024-01-20	CUST-1185	Cash
53487	2024-01-29	CUST-1185	Debit Card
53488	2024-02-03	CUST-1185	Debit Card
53489	2024-05-04	CUST-1185	Paypal
53490	2024-05-09	CUST-1185	Debit Card
53491	2024-05-11	CUST-1185	Cash
53492	2024-05-28	CUST-1185	Credit Card
53493	2024-07-17	CUST-1185	Debit Card
53494	2024-07-20	CUST-1185	Paypal
53495	2024-09-27	CUST-1185	Paypal
53496	2024-10-01	CUST-1185	Debit Card
53497	2024-11-22	CUST-1185	Debit Card
53498	2024-12-18	CUST-1185	Credit Card
53499	2024-12-27	CUST-1185	Cash
53500	2024-12-29	CUST-1185	Debit Card
53501	2025-01-06	CUST-1185	Cash
53502	2025-06-21	CUST-1185	Cash
53503	2025-08-14	CUST-1185	Debit Card
53504	2025-09-23	CUST-1185	Debit Card
53505	2025-10-03	CUST-1185	Paypal
53506	2025-11-05	CUST-1185	Paypal
53507	2025-11-09	CUST-1185	Credit Card
53508	2025-12-09	CUST-1185	Credit Card
53509	2024-01-08	CUST-1186	Credit Card
53510	2024-02-02	CUST-1186	Debit Card
53511	2024-04-02	CUST-1186	Cash
53512	2024-05-05	CUST-1186	Credit Card
53513	2024-05-07	CUST-1186	Debit Card
53514	2024-05-16	CUST-1186	Credit Card
53515	2024-06-03	CUST-1186	Paypal
53516	2024-07-11	CUST-1186	Debit Card
53517	2024-08-28	CUST-1186	Debit Card
53518	2024-09-16	CUST-1186	Credit Card
53519	2024-11-11	CUST-1186	Paypal
53520	2024-11-13	CUST-1186	Debit Card
53521	2024-12-10	CUST-1186	Credit Card
53522	2024-12-12	CUST-1186	Credit Card
53523	2024-12-13	CUST-1186	Debit Card
53524	2024-12-19	CUST-1186	Credit Card
53525	2025-01-10	CUST-1186	Cash
53526	2025-02-01	CUST-1186	Debit Card
53527	2025-03-08	CUST-1186	Credit Card
53528	2025-04-10	CUST-1186	Credit Card
53529	2025-04-19	CUST-1186	Credit Card
53530	2025-06-03	CUST-1186	Credit Card
53531	2025-07-12	CUST-1186	Paypal
53532	2025-07-16	CUST-1186	Cash
53533	2025-08-26	CUST-1186	Paypal
53534	2025-09-22	CUST-1186	Cash
53535	2025-09-28	CUST-1186	Debit Card
53536	2025-10-24	CUST-1186	Debit Card
53537	2025-10-30	CUST-1186	Debit Card
53538	2025-12-09	CUST-1186	Paypal
53539	2025-12-20	CUST-1186	Debit Card
53540	2024-04-08	CUST-1187	Paypal
53541	2024-08-10	CUST-1187	Paypal
53542	2024-08-13	CUST-1187	Debit Card
53543	2024-08-24	CUST-1187	Cash
53544	2024-10-23	CUST-1187	Debit Card
53545	2024-12-14	CUST-1187	Credit Card
53546	2025-02-23	CUST-1187	Cash
53547	2025-04-10	CUST-1187	Debit Card
53548	2025-05-05	CUST-1187	Credit Card
53549	2025-05-09	CUST-1187	Cash
53550	2025-05-14	CUST-1187	Credit Card
53551	2025-07-07	CUST-1187	Debit Card
53552	2025-08-03	CUST-1187	Paypal
53553	2025-08-07	CUST-1187	Credit Card
53554	2025-09-10	CUST-1187	Paypal
53555	2025-10-31	CUST-1187	Credit Card
53556	2025-11-03	CUST-1187	Cash
53557	2025-12-30	CUST-1187	Credit Card
53558	2024-01-14	CUST-1188	Credit Card
53559	2025-08-31	CUST-1188	Cash
53560	2024-07-05	CUST-1189	Credit Card
53561	2024-10-09	CUST-1189	Credit Card
53562	2024-12-21	CUST-1189	Debit Card
53563	2025-03-16	CUST-1189	Debit Card
53564	2025-03-28	CUST-1189	Debit Card
53565	2025-06-28	CUST-1189	Paypal
53566	2025-07-31	CUST-1189	Credit Card
53567	2025-10-12	CUST-1189	Paypal
53568	2024-06-04	CUST-1190	Debit Card
53569	2024-12-25	CUST-1190	Paypal
53570	2025-03-18	CUST-1190	Paypal
53571	2025-04-18	CUST-1190	Credit Card
53572	2025-06-14	CUST-1190	Paypal
53573	2025-07-27	CUST-1190	Credit Card
53574	2025-10-02	CUST-1190	Debit Card
53575	2024-01-06	CUST-1191	Credit Card
53576	2024-09-22	CUST-1191	Paypal
53577	2025-05-21	CUST-1191	Credit Card
53578	2025-12-11	CUST-1191	Credit Card
53579	2024-01-01	CUST-1192	Credit Card
53580	2024-01-04	CUST-1192	Credit Card
53581	2024-01-04	CUST-1192	Debit Card
53582	2024-01-18	CUST-1192	Debit Card
53583	2024-01-24	CUST-1192	Credit Card
53584	2024-01-29	CUST-1192	Debit Card
53585	2024-02-16	CUST-1192	Debit Card
53586	2024-03-02	CUST-1192	Debit Card
53587	2024-03-12	CUST-1192	Paypal
53588	2024-05-01	CUST-1192	Credit Card
53589	2024-05-07	CUST-1192	Credit Card
53590	2024-05-12	CUST-1192	Debit Card
53591	2024-05-28	CUST-1192	Credit Card
53592	2024-05-31	CUST-1192	Debit Card
53593	2024-06-02	CUST-1192	Cash
53594	2024-06-14	CUST-1192	Credit Card
53595	2024-06-22	CUST-1192	Paypal
53596	2024-07-04	CUST-1192	Debit Card
53597	2024-07-18	CUST-1192	Debit Card
53598	2024-08-27	CUST-1192	Paypal
53599	2024-09-02	CUST-1192	Debit Card
53600	2024-09-10	CUST-1192	Cash
53601	2024-09-25	CUST-1192	Debit Card
53602	2024-10-26	CUST-1192	Credit Card
53603	2024-11-12	CUST-1192	Debit Card
53604	2024-11-30	CUST-1192	Cash
53605	2024-12-02	CUST-1192	Cash
53606	2024-12-05	CUST-1192	Debit Card
53607	2024-12-07	CUST-1192	Debit Card
53608	2024-12-12	CUST-1192	Debit Card
53609	2024-12-17	CUST-1192	Paypal
53610	2024-12-23	CUST-1192	Debit Card
53611	2025-01-19	CUST-1192	Debit Card
53612	2025-02-28	CUST-1192	Cash
53613	2025-03-22	CUST-1192	Credit Card
53614	2025-03-24	CUST-1192	Credit Card
53615	2025-03-29	CUST-1192	Credit Card
53616	2025-04-26	CUST-1192	Cash
53617	2025-05-28	CUST-1192	Credit Card
53618	2025-05-29	CUST-1192	Credit Card
53619	2025-07-01	CUST-1192	Cash
53620	2025-07-16	CUST-1192	Credit Card
53621	2025-07-17	CUST-1192	Debit Card
53622	2025-07-19	CUST-1192	Paypal
53623	2025-08-22	CUST-1192	Credit Card
53624	2025-09-16	CUST-1192	Debit Card
53625	2025-10-06	CUST-1192	Cash
53626	2025-10-14	CUST-1192	Credit Card
53627	2025-10-15	CUST-1192	Debit Card
53628	2025-10-19	CUST-1192	Cash
53629	2025-10-29	CUST-1192	Credit Card
53630	2025-11-01	CUST-1192	Debit Card
53631	2025-11-05	CUST-1192	Cash
53632	2025-11-07	CUST-1192	Debit Card
53633	2025-11-09	CUST-1192	Credit Card
53634	2025-11-17	CUST-1192	Debit Card
53635	2025-11-22	CUST-1192	Debit Card
53636	2025-11-23	CUST-1192	Credit Card
53637	2025-11-26	CUST-1192	Credit Card
53638	2025-12-07	CUST-1192	Cash
53639	2025-12-22	CUST-1192	Credit Card
53640	2025-12-28	CUST-1192	Credit Card
53641	2025-12-30	CUST-1192	Debit Card
53642	2024-01-01	CUST-1193	Debit Card
53643	2024-01-18	CUST-1193	Debit Card
53644	2024-01-19	CUST-1193	Debit Card
53645	2024-02-24	CUST-1193	Debit Card
53646	2024-02-28	CUST-1193	Credit Card
53647	2024-03-03	CUST-1193	Debit Card
53648	2024-04-11	CUST-1193	Paypal
53649	2024-04-29	CUST-1193	Debit Card
53650	2024-05-14	CUST-1193	Paypal
53651	2024-05-30	CUST-1193	Credit Card
53652	2024-05-31	CUST-1193	Debit Card
53653	2024-06-03	CUST-1193	Credit Card
53654	2024-06-24	CUST-1193	Cash
53655	2024-08-09	CUST-1193	Credit Card
53656	2024-08-11	CUST-1193	Cash
53657	2024-08-16	CUST-1193	Credit Card
53658	2024-08-17	CUST-1193	Cash
53659	2024-08-20	CUST-1193	Credit Card
53660	2024-08-28	CUST-1193	Debit Card
53661	2024-09-02	CUST-1193	Debit Card
53662	2024-09-09	CUST-1193	Debit Card
53663	2024-09-27	CUST-1193	Paypal
53664	2024-09-30	CUST-1193	Credit Card
53665	2024-10-04	CUST-1193	Paypal
53666	2024-10-21	CUST-1193	Credit Card
53667	2024-11-07	CUST-1193	Credit Card
53668	2024-11-13	CUST-1193	Credit Card
53669	2024-11-27	CUST-1193	Credit Card
53670	2024-12-02	CUST-1193	Paypal
53671	2024-12-04	CUST-1193	Credit Card
53672	2024-12-08	CUST-1193	Debit Card
53673	2024-12-15	CUST-1193	Cash
53674	2024-12-27	CUST-1193	Credit Card
53675	2025-01-01	CUST-1193	Credit Card
53676	2025-01-02	CUST-1193	Paypal
53677	2025-01-03	CUST-1193	Credit Card
53678	2025-01-06	CUST-1193	Credit Card
53679	2025-01-21	CUST-1193	Paypal
53680	2025-01-30	CUST-1193	Credit Card
53681	2025-02-28	CUST-1193	Cash
53682	2025-03-01	CUST-1193	Paypal
53683	2025-03-14	CUST-1193	Paypal
53684	2025-03-19	CUST-1193	Debit Card
53685	2025-03-25	CUST-1193	Credit Card
53686	2025-03-26	CUST-1193	Paypal
53687	2025-03-31	CUST-1193	Debit Card
53688	2025-04-04	CUST-1193	Cash
53689	2025-04-12	CUST-1193	Credit Card
53690	2025-04-30	CUST-1193	Paypal
53691	2025-05-06	CUST-1193	Paypal
53692	2025-05-07	CUST-1193	Debit Card
53693	2025-05-17	CUST-1193	Debit Card
53694	2025-05-31	CUST-1193	Paypal
53695	2025-06-09	CUST-1193	Credit Card
53696	2025-06-21	CUST-1193	Debit Card
53697	2025-10-08	CUST-1193	Paypal
53698	2025-10-31	CUST-1193	Credit Card
53699	2025-11-02	CUST-1193	Paypal
53700	2025-11-05	CUST-1193	Debit Card
53701	2025-11-06	CUST-1193	Paypal
53702	2025-11-07	CUST-1193	Debit Card
53703	2025-11-09	CUST-1193	Credit Card
53704	2025-11-21	CUST-1193	Debit Card
53705	2025-11-29	CUST-1193	Credit Card
53706	2025-11-30	CUST-1193	Credit Card
53707	2025-12-13	CUST-1193	Debit Card
53708	2025-12-22	CUST-1193	Credit Card
53709	2025-12-31	CUST-1193	Debit Card
53710	2024-02-06	CUST-1194	Debit Card
53711	2024-02-09	CUST-1194	Debit Card
53712	2024-03-16	CUST-1194	Debit Card
53713	2024-03-21	CUST-1194	Paypal
53714	2024-04-05	CUST-1194	Credit Card
53715	2024-04-05	CUST-1194	Debit Card
53716	2024-04-10	CUST-1194	Paypal
53717	2024-04-12	CUST-1194	Credit Card
53718	2024-04-25	CUST-1194	Debit Card
53719	2024-05-13	CUST-1194	Credit Card
53720	2024-05-30	CUST-1194	Credit Card
53721	2024-06-08	CUST-1194	Credit Card
53722	2024-06-25	CUST-1194	Credit Card
53723	2024-07-22	CUST-1194	Credit Card
53724	2024-08-09	CUST-1194	Debit Card
53725	2024-08-25	CUST-1194	Credit Card
53726	2024-09-01	CUST-1194	Paypal
53727	2024-09-25	CUST-1194	Credit Card
53728	2024-10-11	CUST-1194	Cash
53729	2024-10-27	CUST-1194	Credit Card
53730	2024-11-04	CUST-1194	Cash
53731	2024-11-05	CUST-1194	Credit Card
53732	2024-11-20	CUST-1194	Debit Card
53733	2024-11-27	CUST-1194	Credit Card
53734	2024-11-29	CUST-1194	Credit Card
53735	2024-12-28	CUST-1194	Paypal
53736	2025-01-08	CUST-1194	Credit Card
53737	2025-01-20	CUST-1194	Credit Card
53738	2025-02-06	CUST-1194	Debit Card
53739	2025-02-22	CUST-1194	Credit Card
53740	2025-02-26	CUST-1194	Cash
53741	2025-03-16	CUST-1194	Cash
53742	2025-03-23	CUST-1194	Debit Card
53743	2025-04-06	CUST-1194	Debit Card
53744	2025-04-15	CUST-1194	Debit Card
53745	2025-05-03	CUST-1194	Paypal
53746	2025-05-09	CUST-1194	Debit Card
53747	2025-05-23	CUST-1194	Paypal
53748	2025-05-31	CUST-1194	Credit Card
53749	2025-06-01	CUST-1194	Credit Card
53750	2025-06-01	CUST-1194	Debit Card
53751	2025-06-20	CUST-1194	Debit Card
53752	2025-07-18	CUST-1194	Credit Card
53753	2025-08-31	CUST-1194	Paypal
53754	2025-10-19	CUST-1194	Credit Card
53755	2025-10-20	CUST-1194	Debit Card
53756	2025-11-05	CUST-1194	Paypal
53757	2025-11-07	CUST-1194	Credit Card
53758	2025-11-22	CUST-1194	Credit Card
53759	2025-11-22	CUST-1194	Debit Card
53760	2025-11-28	CUST-1194	Debit Card
53761	2025-11-30	CUST-1194	Credit Card
53762	2025-12-01	CUST-1194	Credit Card
53763	2025-12-07	CUST-1194	Credit Card
53764	2025-12-17	CUST-1194	Paypal
53765	2024-01-03	CUST-1195	Credit Card
53766	2024-01-13	CUST-1195	Credit Card
53767	2024-04-24	CUST-1195	Debit Card
53768	2024-04-26	CUST-1195	Paypal
53769	2024-07-07	CUST-1195	Debit Card
53770	2024-07-09	CUST-1195	Credit Card
53771	2024-10-21	CUST-1195	Credit Card
53772	2024-11-29	CUST-1195	Credit Card
53773	2025-01-21	CUST-1195	Credit Card
53774	2025-01-26	CUST-1195	Paypal
53775	2025-05-06	CUST-1195	Credit Card
53776	2025-06-21	CUST-1195	Credit Card
53777	2025-08-17	CUST-1195	Credit Card
53778	2025-09-09	CUST-1195	Credit Card
53779	2025-11-19	CUST-1195	Credit Card
53780	2025-11-20	CUST-1195	Paypal
53781	2025-12-07	CUST-1195	Debit Card
53782	2025-12-09	CUST-1195	Debit Card
53783	2024-03-04	CUST-1196	Credit Card
53784	2024-03-22	CUST-1196	Credit Card
53785	2024-04-01	CUST-1196	Debit Card
53786	2024-04-03	CUST-1196	Cash
53787	2024-04-04	CUST-1196	Credit Card
53788	2024-04-14	CUST-1196	Paypal
53789	2024-04-17	CUST-1196	Paypal
53790	2024-04-22	CUST-1196	Debit Card
53791	2024-05-05	CUST-1196	Debit Card
53792	2024-05-09	CUST-1196	Cash
53793	2024-05-10	CUST-1196	Cash
53794	2024-05-14	CUST-1196	Credit Card
53795	2024-05-16	CUST-1196	Credit Card
53796	2024-06-02	CUST-1196	Cash
53797	2024-06-04	CUST-1196	Paypal
53798	2024-06-12	CUST-1196	Cash
53799	2024-06-13	CUST-1196	Debit Card
53800	2024-06-14	CUST-1196	Credit Card
53801	2024-06-16	CUST-1196	Paypal
53802	2024-07-24	CUST-1196	Cash
53803	2024-09-04	CUST-1196	Cash
53804	2024-09-16	CUST-1196	Credit Card
53805	2024-09-23	CUST-1196	Credit Card
53806	2024-10-03	CUST-1196	Debit Card
53807	2024-10-03	CUST-1196	Paypal
53808	2024-10-05	CUST-1196	Debit Card
53809	2024-10-29	CUST-1196	Credit Card
53810	2024-11-12	CUST-1196	Credit Card
53811	2024-11-14	CUST-1196	Credit Card
53812	2024-11-19	CUST-1196	Credit Card
53813	2024-12-16	CUST-1196	Debit Card
53814	2024-12-19	CUST-1196	Paypal
53815	2024-12-23	CUST-1196	Credit Card
53816	2024-12-31	CUST-1196	Paypal
53817	2025-01-07	CUST-1196	Paypal
53818	2025-03-06	CUST-1196	Credit Card
53819	2025-03-24	CUST-1196	Paypal
53820	2025-03-25	CUST-1196	Credit Card
53821	2025-03-30	CUST-1196	Debit Card
53822	2025-04-03	CUST-1196	Debit Card
53823	2025-05-25	CUST-1196	Credit Card
53824	2025-06-03	CUST-1196	Cash
53825	2025-06-03	CUST-1196	Debit Card
53826	2025-06-11	CUST-1196	Paypal
53827	2025-06-22	CUST-1196	Cash
53828	2025-06-24	CUST-1196	Credit Card
53829	2025-07-05	CUST-1196	Paypal
53830	2025-08-26	CUST-1196	Paypal
53831	2025-09-07	CUST-1196	Debit Card
53832	2025-09-13	CUST-1196	Credit Card
53833	2025-09-19	CUST-1196	Credit Card
53834	2025-09-22	CUST-1196	Cash
53835	2025-09-23	CUST-1196	Paypal
53836	2025-10-14	CUST-1196	Debit Card
53837	2025-10-15	CUST-1196	Cash
53838	2025-10-18	CUST-1196	Credit Card
53839	2025-10-27	CUST-1196	Paypal
53840	2025-11-11	CUST-1196	Credit Card
53841	2025-11-13	CUST-1196	Credit Card
53842	2025-11-13	CUST-1196	Debit Card
53843	2025-11-28	CUST-1196	Debit Card
53844	2025-12-06	CUST-1196	Credit Card
53845	2025-12-07	CUST-1196	Debit Card
53846	2025-12-10	CUST-1196	Debit Card
53847	2025-12-16	CUST-1196	Credit Card
53848	2025-12-20	CUST-1196	Credit Card
53849	2024-02-04	CUST-1197	Cash
53850	2024-05-01	CUST-1197	Debit Card
53851	2024-06-26	CUST-1197	Debit Card
53852	2024-09-20	CUST-1197	Debit Card
53853	2024-10-11	CUST-1197	Credit Card
53854	2024-10-28	CUST-1197	Debit Card
53855	2024-12-03	CUST-1197	Credit Card
53856	2025-10-12	CUST-1197	Paypal
53857	2025-10-25	CUST-1197	Debit Card
53858	2025-11-05	CUST-1197	Credit Card
53859	2025-11-16	CUST-1197	Cash
53860	2025-12-02	CUST-1197	Credit Card
53861	2024-01-06	CUST-1198	Cash
53862	2024-03-13	CUST-1198	Cash
53863	2024-05-28	CUST-1198	Credit Card
53864	2024-05-29	CUST-1198	Cash
53865	2024-08-16	CUST-1198	Paypal
53866	2024-09-05	CUST-1198	Credit Card
53867	2024-09-14	CUST-1198	Debit Card
53868	2024-10-19	CUST-1198	Debit Card
53869	2025-06-05	CUST-1198	Credit Card
53870	2025-09-30	CUST-1198	Paypal
53871	2025-10-22	CUST-1198	Paypal
53872	2024-10-06	CUST-1199	Paypal
53873	2025-02-12	CUST-1199	Paypal
53874	2025-02-20	CUST-1199	Credit Card
53875	2025-11-05	CUST-1199	Paypal
53876	2024-01-25	CUST-1200	Debit Card
53877	2024-02-08	CUST-1200	Debit Card
53878	2024-04-12	CUST-1200	Paypal
53879	2024-04-25	CUST-1200	Cash
53880	2024-06-10	CUST-1200	Debit Card
53881	2024-08-27	CUST-1200	Credit Card
53882	2024-09-12	CUST-1200	Credit Card
53883	2024-10-24	CUST-1200	Paypal
53884	2024-11-09	CUST-1200	Debit Card
53885	2024-11-27	CUST-1200	Debit Card
53886	2024-12-11	CUST-1200	Credit Card
53887	2025-01-11	CUST-1200	Cash
53888	2025-03-24	CUST-1200	Debit Card
53889	2025-05-30	CUST-1200	Paypal
53890	2025-06-30	CUST-1200	Credit Card
53891	2025-07-26	CUST-1200	Cash
53892	2025-08-31	CUST-1200	Credit Card
53893	2025-09-03	CUST-1200	Credit Card
53894	2025-11-04	CUST-1200	Credit Card
53895	2025-11-17	CUST-1200	Credit Card
53896	2025-12-26	CUST-1200	Debit Card
53897	2024-01-11	CUST-1201	Debit Card
53898	2024-03-30	CUST-1201	Cash
53899	2024-05-01	CUST-1201	Debit Card
53900	2024-07-09	CUST-1201	Credit Card
53901	2024-11-12	CUST-1201	Credit Card
53902	2024-12-15	CUST-1201	Paypal
53903	2025-02-02	CUST-1201	Debit Card
53904	2025-04-18	CUST-1201	Credit Card
53905	2025-08-31	CUST-1201	Credit Card
53906	2025-10-03	CUST-1201	Debit Card
53907	2025-10-10	CUST-1201	Paypal
53908	2025-11-29	CUST-1201	Cash
53909	2024-01-09	CUST-1202	Debit Card
53910	2024-09-27	CUST-1202	Credit Card
53911	2024-12-15	CUST-1202	Cash
53912	2025-05-01	CUST-1202	Paypal
53913	2024-05-30	CUST-1203	Credit Card
53914	2024-06-03	CUST-1203	Paypal
53915	2024-07-08	CUST-1203	Credit Card
53916	2024-09-02	CUST-1203	Debit Card
53917	2024-11-13	CUST-1203	Debit Card
53918	2025-02-01	CUST-1203	Debit Card
53919	2025-05-27	CUST-1203	Cash
53920	2025-07-29	CUST-1203	Credit Card
53921	2025-07-30	CUST-1203	Credit Card
53922	2025-10-01	CUST-1203	Debit Card
53923	2025-12-12	CUST-1203	Debit Card
53924	2024-01-26	CUST-1204	Paypal
53925	2024-06-29	CUST-1204	Cash
53926	2024-11-16	CUST-1204	Credit Card
53927	2025-01-08	CUST-1204	Credit Card
53928	2025-01-13	CUST-1204	Credit Card
53929	2025-01-16	CUST-1204	Paypal
53930	2025-02-04	CUST-1204	Debit Card
53931	2025-02-10	CUST-1204	Credit Card
53932	2025-05-05	CUST-1204	Debit Card
53933	2025-05-24	CUST-1204	Paypal
53934	2025-07-02	CUST-1204	Paypal
53935	2025-07-17	CUST-1204	Debit Card
53936	2025-07-30	CUST-1204	Paypal
53937	2024-01-20	CUST-1205	Credit Card
53938	2024-01-28	CUST-1205	Credit Card
53939	2024-02-17	CUST-1205	Credit Card
53940	2024-03-08	CUST-1205	Debit Card
53941	2024-03-13	CUST-1205	Credit Card
53942	2024-03-27	CUST-1205	Credit Card
53943	2024-04-06	CUST-1205	Debit Card
53944	2024-05-16	CUST-1205	Debit Card
53945	2024-05-18	CUST-1205	Cash
53946	2024-06-27	CUST-1205	Credit Card
53947	2024-07-06	CUST-1205	Cash
53948	2024-08-05	CUST-1205	Credit Card
53949	2024-08-22	CUST-1205	Credit Card
53950	2024-09-07	CUST-1205	Credit Card
53951	2024-09-13	CUST-1205	Credit Card
53952	2024-10-08	CUST-1205	Credit Card
53953	2024-10-25	CUST-1205	Credit Card
53954	2024-10-27	CUST-1205	Debit Card
53955	2024-11-02	CUST-1205	Paypal
53956	2024-11-07	CUST-1205	Cash
53957	2024-11-28	CUST-1205	Credit Card
53958	2024-12-02	CUST-1205	Cash
53959	2024-12-03	CUST-1205	Cash
53960	2024-12-04	CUST-1205	Debit Card
53961	2024-12-06	CUST-1205	Cash
53962	2024-12-06	CUST-1205	Debit Card
53963	2024-12-11	CUST-1205	Debit Card
53964	2024-12-14	CUST-1205	Credit Card
53965	2025-01-22	CUST-1205	Debit Card
53966	2025-01-30	CUST-1205	Paypal
53967	2025-02-17	CUST-1205	Credit Card
53968	2025-03-14	CUST-1205	Credit Card
53969	2025-03-19	CUST-1205	Cash
53970	2025-04-01	CUST-1205	Debit Card
53971	2025-04-04	CUST-1205	Paypal
53972	2025-04-09	CUST-1205	Debit Card
53973	2025-04-13	CUST-1205	Cash
53974	2025-04-13	CUST-1205	Credit Card
53975	2025-05-09	CUST-1205	Paypal
53976	2025-05-11	CUST-1205	Credit Card
53977	2025-05-23	CUST-1205	Debit Card
53978	2025-06-02	CUST-1205	Credit Card
53979	2025-06-17	CUST-1205	Credit Card
53980	2025-06-24	CUST-1205	Credit Card
53981	2025-06-25	CUST-1205	Paypal
53982	2025-06-30	CUST-1205	Cash
53983	2025-07-02	CUST-1205	Credit Card
53984	2025-07-02	CUST-1205	Debit Card
53985	2025-07-05	CUST-1205	Debit Card
53986	2025-07-08	CUST-1205	Credit Card
53987	2025-07-20	CUST-1205	Debit Card
53988	2025-07-26	CUST-1205	Debit Card
53989	2025-07-31	CUST-1205	Debit Card
53990	2025-08-01	CUST-1205	Credit Card
53991	2025-08-08	CUST-1205	Cash
53992	2025-08-18	CUST-1205	Debit Card
53993	2025-08-29	CUST-1205	Credit Card
53994	2025-09-20	CUST-1205	Debit Card
53995	2025-10-12	CUST-1205	Credit Card
53996	2025-10-25	CUST-1205	Credit Card
53997	2025-10-28	CUST-1205	Paypal
53998	2025-11-02	CUST-1205	Cash
53999	2025-11-07	CUST-1205	Paypal
54000	2025-11-09	CUST-1205	Credit Card
54001	2025-11-11	CUST-1205	Cash
54002	2025-11-11	CUST-1205	Credit Card
54003	2025-11-14	CUST-1205	Debit Card
54004	2025-12-01	CUST-1205	Cash
54005	2025-12-02	CUST-1205	Cash
54006	2025-12-15	CUST-1205	Debit Card
54007	2025-12-17	CUST-1205	Debit Card
54008	2025-12-19	CUST-1205	Debit Card
54009	2025-12-22	CUST-1205	Debit Card
54010	2024-02-19	CUST-1206	Cash
54011	2024-03-15	CUST-1206	Credit Card
54012	2024-03-30	CUST-1206	Paypal
54013	2024-04-29	CUST-1206	Debit Card
54014	2024-05-10	CUST-1206	Cash
54015	2024-06-17	CUST-1206	Credit Card
54016	2024-06-19	CUST-1206	Paypal
54017	2024-08-11	CUST-1206	Debit Card
54018	2024-08-22	CUST-1206	Debit Card
54019	2024-09-07	CUST-1206	Debit Card
54020	2024-09-24	CUST-1206	Credit Card
54021	2024-10-04	CUST-1206	Cash
54022	2024-10-05	CUST-1206	Cash
54023	2024-10-11	CUST-1206	Credit Card
54024	2024-10-16	CUST-1206	Credit Card
54025	2024-10-20	CUST-1206	Credit Card
54026	2024-10-25	CUST-1206	Credit Card
54027	2024-11-26	CUST-1206	Credit Card
54028	2024-11-29	CUST-1206	Cash
54029	2024-12-03	CUST-1206	Paypal
54030	2024-12-14	CUST-1206	Debit Card
54031	2024-12-15	CUST-1206	Debit Card
54032	2025-01-18	CUST-1206	Credit Card
54033	2025-01-28	CUST-1206	Debit Card
54034	2025-02-05	CUST-1206	Credit Card
54035	2025-02-17	CUST-1206	Cash
54036	2025-03-03	CUST-1206	Credit Card
54037	2025-03-12	CUST-1206	Credit Card
54038	2025-04-01	CUST-1206	Debit Card
54039	2025-04-26	CUST-1206	Credit Card
54040	2025-05-02	CUST-1206	Cash
54041	2025-05-29	CUST-1206	Cash
54042	2025-06-13	CUST-1206	Cash
54043	2025-06-13	CUST-1206	Debit Card
54044	2025-08-04	CUST-1206	Paypal
54045	2025-09-13	CUST-1206	Credit Card
54046	2025-10-07	CUST-1206	Credit Card
54047	2025-10-19	CUST-1206	Credit Card
54048	2025-11-28	CUST-1206	Credit Card
54049	2024-02-19	CUST-1207	Credit Card
54050	2024-06-23	CUST-1207	Debit Card
54051	2024-07-10	CUST-1207	Credit Card
54052	2024-10-14	CUST-1207	Cash
54053	2024-10-24	CUST-1207	Credit Card
54054	2024-12-17	CUST-1207	Paypal
54055	2025-06-04	CUST-1207	Debit Card
54056	2025-06-10	CUST-1207	Credit Card
54057	2025-06-22	CUST-1207	Credit Card
54058	2025-07-23	CUST-1207	Debit Card
54059	2025-08-21	CUST-1207	Paypal
54060	2025-10-11	CUST-1207	Cash
54061	2025-10-28	CUST-1207	Credit Card
54062	2025-11-18	CUST-1207	Credit Card
54063	2024-03-24	CUST-1208	Debit Card
54064	2024-07-06	CUST-1208	Debit Card
54065	2024-09-17	CUST-1208	Cash
54066	2024-09-23	CUST-1208	Credit Card
54067	2024-11-08	CUST-1208	Debit Card
54068	2024-12-05	CUST-1208	Credit Card
54069	2024-12-28	CUST-1208	Credit Card
54070	2025-01-05	CUST-1208	Credit Card
54071	2025-01-21	CUST-1208	Debit Card
54072	2025-03-05	CUST-1208	Credit Card
54073	2025-08-22	CUST-1208	Credit Card
54074	2025-08-23	CUST-1208	Credit Card
54075	2025-08-30	CUST-1208	Debit Card
54076	2025-10-25	CUST-1208	Debit Card
54077	2025-11-08	CUST-1208	Debit Card
54078	2025-12-15	CUST-1208	Cash
54079	2025-12-22	CUST-1208	Credit Card
54080	2025-12-23	CUST-1208	Debit Card
54081	2025-12-30	CUST-1208	Credit Card
54082	2025-12-31	CUST-1208	Cash
54083	2024-01-11	CUST-1209	Credit Card
54084	2024-07-13	CUST-1209	Credit Card
54085	2024-09-07	CUST-1209	Paypal
54086	2024-10-14	CUST-1209	Debit Card
54087	2024-11-08	CUST-1209	Credit Card
54088	2025-04-29	CUST-1209	Credit Card
54089	2025-06-26	CUST-1209	Credit Card
54090	2025-07-12	CUST-1209	Credit Card
54091	2025-08-13	CUST-1209	Cash
54092	2025-09-01	CUST-1209	Credit Card
54093	2025-10-31	CUST-1209	Credit Card
54094	2025-11-20	CUST-1209	Credit Card
54095	2025-12-30	CUST-1209	Cash
54096	2024-01-05	CUST-1210	Cash
54097	2024-01-12	CUST-1210	Debit Card
54098	2024-05-28	CUST-1210	Debit Card
54099	2025-02-02	CUST-1210	Cash
54100	2025-03-23	CUST-1210	Cash
54101	2025-04-01	CUST-1210	Debit Card
54102	2025-08-10	CUST-1210	Debit Card
54103	2025-08-12	CUST-1210	Cash
54104	2025-09-21	CUST-1210	Debit Card
54105	2025-09-25	CUST-1210	Credit Card
54106	2025-10-21	CUST-1210	Debit Card
54107	2025-11-24	CUST-1210	Credit Card
54108	2024-08-22	CUST-1211	Credit Card
54109	2024-11-19	CUST-1211	Debit Card
54110	2025-07-03	CUST-1211	Credit Card
54111	2025-08-16	CUST-1211	Cash
54112	2025-10-29	CUST-1211	Credit Card
54113	2025-11-09	CUST-1211	Credit Card
54114	2025-12-05	CUST-1211	Paypal
54115	2025-12-22	CUST-1211	Cash
54116	2024-04-22	CUST-1212	Debit Card
54117	2024-06-14	CUST-1212	Cash
54118	2024-11-05	CUST-1212	Credit Card
54119	2025-01-29	CUST-1212	Cash
54120	2025-03-29	CUST-1212	Credit Card
54121	2025-04-07	CUST-1212	Credit Card
54122	2025-06-01	CUST-1212	Cash
54123	2025-06-10	CUST-1212	Debit Card
54124	2025-08-22	CUST-1212	Cash
54125	2025-08-22	CUST-1212	Debit Card
54126	2025-10-17	CUST-1212	Cash
54127	2025-12-05	CUST-1212	Paypal
54128	2025-12-06	CUST-1212	Debit Card
54129	2024-06-24	CUST-1213	Credit Card
54130	2024-07-05	CUST-1213	Credit Card
54131	2024-09-02	CUST-1213	Debit Card
54132	2024-09-16	CUST-1213	Debit Card
54133	2025-07-22	CUST-1213	Credit Card
54134	2025-09-02	CUST-1213	Paypal
54135	2025-11-25	CUST-1213	Cash
54136	2025-12-09	CUST-1213	Credit Card
54137	2025-12-18	CUST-1213	Debit Card
54138	2024-02-13	CUST-1214	Credit Card
54139	2024-03-16	CUST-1214	Credit Card
54140	2024-12-07	CUST-1214	Cash
54141	2024-02-25	CUST-1215	Debit Card
54142	2024-02-29	CUST-1215	Credit Card
54143	2024-04-05	CUST-1215	Paypal
54144	2024-04-12	CUST-1215	Debit Card
54145	2024-05-14	CUST-1215	Debit Card
54146	2024-05-27	CUST-1215	Paypal
54147	2024-05-28	CUST-1215	Credit Card
54148	2024-06-27	CUST-1215	Paypal
54149	2024-07-11	CUST-1215	Credit Card
54150	2024-08-28	CUST-1215	Credit Card
54151	2024-09-04	CUST-1215	Credit Card
54152	2024-10-25	CUST-1215	Cash
54153	2024-11-26	CUST-1215	Credit Card
54154	2024-12-29	CUST-1215	Credit Card
54155	2025-02-16	CUST-1215	Credit Card
54156	2025-03-27	CUST-1215	Credit Card
54157	2025-05-01	CUST-1215	Debit Card
54158	2025-05-11	CUST-1215	Debit Card
54159	2025-05-13	CUST-1215	Credit Card
54160	2025-06-14	CUST-1215	Credit Card
54161	2025-08-09	CUST-1215	Credit Card
54162	2025-08-14	CUST-1215	Credit Card
54163	2025-10-22	CUST-1215	Credit Card
54164	2025-12-23	CUST-1215	Credit Card
54165	2024-01-04	CUST-1216	Credit Card
54166	2024-01-12	CUST-1216	Cash
54167	2024-02-04	CUST-1216	Debit Card
54168	2024-02-25	CUST-1216	Debit Card
54169	2024-04-30	CUST-1216	Credit Card
54170	2024-05-06	CUST-1216	Paypal
54171	2024-05-08	CUST-1216	Credit Card
54172	2024-05-27	CUST-1216	Paypal
54173	2024-09-09	CUST-1216	Paypal
54174	2024-09-22	CUST-1216	Cash
54175	2024-09-30	CUST-1216	Credit Card
54176	2024-10-13	CUST-1216	Debit Card
54177	2024-11-03	CUST-1216	Paypal
54178	2024-12-03	CUST-1216	Credit Card
54179	2024-12-22	CUST-1216	Paypal
54180	2024-12-30	CUST-1216	Paypal
54181	2025-02-21	CUST-1216	Credit Card
54182	2025-07-12	CUST-1216	Debit Card
54183	2025-07-17	CUST-1216	Cash
54184	2025-11-06	CUST-1216	Credit Card
54185	2025-11-07	CUST-1216	Debit Card
54186	2025-12-10	CUST-1216	Credit Card
54187	2025-12-30	CUST-1216	Debit Card
54188	2025-08-26	CUST-1217	Debit Card
54189	2025-09-11	CUST-1217	Credit Card
54190	2024-05-27	CUST-1218	Credit Card
54191	2024-07-29	CUST-1218	Debit Card
54192	2024-09-27	CUST-1218	Paypal
54193	2024-11-15	CUST-1218	Credit Card
54194	2024-12-21	CUST-1218	Paypal
54195	2025-04-04	CUST-1218	Credit Card
54196	2025-04-23	CUST-1218	Credit Card
54197	2025-08-26	CUST-1218	Credit Card
54198	2025-10-22	CUST-1218	Debit Card
54199	2025-11-08	CUST-1218	Credit Card
54200	2024-01-05	CUST-1219	Debit Card
54201	2024-01-16	CUST-1219	Paypal
54202	2024-02-08	CUST-1219	Credit Card
54203	2024-02-16	CUST-1219	Credit Card
54204	2024-05-09	CUST-1219	Debit Card
54205	2024-05-16	CUST-1219	Credit Card
54206	2024-05-30	CUST-1219	Debit Card
54207	2024-06-08	CUST-1219	Credit Card
54208	2024-09-06	CUST-1219	Paypal
54209	2024-09-14	CUST-1219	Credit Card
54210	2024-10-08	CUST-1219	Credit Card
54211	2024-10-13	CUST-1219	Debit Card
54212	2024-10-17	CUST-1219	Cash
54213	2024-11-04	CUST-1219	Credit Card
54214	2024-11-25	CUST-1219	Cash
54215	2024-12-12	CUST-1219	Credit Card
54216	2024-12-18	CUST-1219	Cash
54217	2024-12-18	CUST-1219	Credit Card
54218	2025-01-09	CUST-1219	Debit Card
54219	2025-03-26	CUST-1219	Credit Card
54220	2025-03-26	CUST-1219	Paypal
54221	2025-03-31	CUST-1219	Debit Card
54222	2025-05-01	CUST-1219	Cash
54223	2025-05-11	CUST-1219	Credit Card
54224	2025-05-24	CUST-1219	Debit Card
54225	2025-06-16	CUST-1219	Credit Card
54226	2025-06-21	CUST-1219	Paypal
54227	2025-07-21	CUST-1219	Paypal
54228	2025-08-23	CUST-1219	Credit Card
54229	2025-09-22	CUST-1219	Credit Card
54230	2025-09-27	CUST-1219	Paypal
54231	2025-10-03	CUST-1219	Credit Card
54232	2025-10-05	CUST-1219	Paypal
54233	2025-10-25	CUST-1219	Credit Card
54234	2025-11-04	CUST-1219	Debit Card
54235	2025-11-06	CUST-1219	Credit Card
54236	2025-11-14	CUST-1219	Paypal
54237	2025-11-30	CUST-1219	Debit Card
54238	2025-12-05	CUST-1219	Debit Card
54239	2025-12-10	CUST-1219	Credit Card
54240	2025-12-19	CUST-1219	Credit Card
54241	2025-12-30	CUST-1219	Cash
54242	2024-05-04	CUST-1220	Paypal
54243	2024-05-09	CUST-1220	Debit Card
54244	2024-05-21	CUST-1220	Debit Card
54245	2024-05-25	CUST-1220	Credit Card
54246	2024-05-29	CUST-1220	Debit Card
54247	2024-06-03	CUST-1220	Credit Card
54248	2024-07-03	CUST-1220	Cash
54249	2024-07-14	CUST-1220	Debit Card
54250	2024-07-22	CUST-1220	Debit Card
54251	2024-07-27	CUST-1220	Cash
54252	2024-08-08	CUST-1220	Debit Card
54253	2024-08-27	CUST-1220	Cash
54254	2024-09-06	CUST-1220	Credit Card
54255	2024-10-05	CUST-1220	Credit Card
54256	2024-10-10	CUST-1220	Credit Card
54257	2024-11-10	CUST-1220	Debit Card
54258	2024-11-18	CUST-1220	Paypal
54259	2024-12-18	CUST-1220	Paypal
54260	2024-12-22	CUST-1220	Cash
54261	2024-12-28	CUST-1220	Debit Card
54262	2025-02-06	CUST-1220	Cash
54263	2025-02-22	CUST-1220	Debit Card
54264	2025-04-16	CUST-1220	Debit Card
54265	2025-05-24	CUST-1220	Credit Card
54266	2025-06-23	CUST-1220	Debit Card
54267	2025-06-24	CUST-1220	Credit Card
54268	2025-07-16	CUST-1220	Credit Card
54269	2025-07-21	CUST-1220	Credit Card
54270	2025-07-25	CUST-1220	Debit Card
54271	2025-07-27	CUST-1220	Debit Card
54272	2025-08-26	CUST-1220	Debit Card
54273	2025-08-31	CUST-1220	Credit Card
54274	2025-09-11	CUST-1220	Credit Card
54275	2025-09-18	CUST-1220	Cash
54276	2025-09-22	CUST-1220	Credit Card
54277	2025-09-25	CUST-1220	Cash
54278	2025-10-13	CUST-1220	Debit Card
54279	2025-10-17	CUST-1220	Credit Card
54280	2025-10-18	CUST-1220	Debit Card
54281	2025-11-03	CUST-1220	Credit Card
54282	2025-11-04	CUST-1220	Paypal
54283	2025-12-04	CUST-1220	Debit Card
54284	2025-12-11	CUST-1220	Debit Card
54285	2025-12-16	CUST-1220	Paypal
54286	2025-12-29	CUST-1220	Credit Card
54287	2024-03-05	CUST-1221	Debit Card
54288	2024-05-02	CUST-1221	Paypal
54289	2024-05-03	CUST-1221	Credit Card
54290	2024-06-17	CUST-1221	Credit Card
54291	2024-07-19	CUST-1221	Cash
54292	2024-07-27	CUST-1221	Cash
54293	2024-09-02	CUST-1221	Credit Card
54294	2024-10-15	CUST-1221	Debit Card
54295	2024-10-16	CUST-1221	Debit Card
54296	2024-10-27	CUST-1221	Debit Card
54297	2024-11-02	CUST-1221	Debit Card
54298	2024-11-14	CUST-1221	Credit Card
54299	2024-11-14	CUST-1221	Debit Card
54300	2024-11-21	CUST-1221	Credit Card
54301	2025-01-18	CUST-1221	Cash
54302	2025-01-27	CUST-1221	Credit Card
54303	2025-05-04	CUST-1221	Paypal
54304	2025-05-12	CUST-1221	Debit Card
54305	2025-05-23	CUST-1221	Credit Card
54306	2025-05-25	CUST-1221	Credit Card
54307	2025-06-20	CUST-1221	Credit Card
54308	2025-07-26	CUST-1221	Cash
54309	2025-08-13	CUST-1221	Paypal
54310	2025-09-08	CUST-1221	Credit Card
54311	2025-10-02	CUST-1221	Credit Card
54312	2025-11-18	CUST-1221	Debit Card
54313	2025-12-10	CUST-1221	Paypal
54314	2025-12-13	CUST-1221	Credit Card
54315	2025-12-14	CUST-1221	Credit Card
54316	2025-12-25	CUST-1221	Credit Card
54317	2025-12-27	CUST-1221	Credit Card
54318	2024-03-14	CUST-1222	Credit Card
54319	2024-05-29	CUST-1222	Debit Card
54320	2024-08-25	CUST-1222	Credit Card
54321	2024-09-07	CUST-1222	Credit Card
54322	2024-11-26	CUST-1222	Debit Card
54323	2025-09-26	CUST-1222	Credit Card
54324	2025-10-16	CUST-1222	Credit Card
54325	2025-11-17	CUST-1222	Debit Card
54326	2024-08-22	CUST-1223	Credit Card
54327	2024-08-26	CUST-1223	Credit Card
54328	2024-09-21	CUST-1223	Credit Card
54329	2024-11-17	CUST-1223	Paypal
54330	2025-05-23	CUST-1223	Paypal
54331	2025-11-07	CUST-1223	Credit Card
54332	2024-02-08	CUST-1224	Debit Card
54333	2024-04-04	CUST-1224	Credit Card
54334	2024-11-23	CUST-1224	Credit Card
54335	2025-01-30	CUST-1224	Paypal
54336	2025-02-01	CUST-1224	Credit Card
54337	2025-07-26	CUST-1224	Credit Card
54338	2025-11-24	CUST-1224	Debit Card
54339	2024-01-20	CUST-1225	Cash
54340	2024-03-05	CUST-1225	Debit Card
54341	2024-04-01	CUST-1225	Paypal
54342	2024-08-26	CUST-1225	Credit Card
54343	2024-09-05	CUST-1225	Credit Card
54344	2024-10-06	CUST-1225	Paypal
54345	2024-10-08	CUST-1225	Cash
54346	2024-11-27	CUST-1225	Credit Card
54347	2024-11-30	CUST-1225	Credit Card
54348	2025-04-26	CUST-1225	Credit Card
54349	2025-05-13	CUST-1225	Credit Card
54350	2025-07-08	CUST-1225	Debit Card
54351	2025-08-12	CUST-1225	Debit Card
54352	2025-09-10	CUST-1225	Credit Card
54353	2025-11-10	CUST-1225	Debit Card
54354	2025-12-12	CUST-1225	Cash
54355	2025-12-21	CUST-1225	Cash
54356	2024-01-14	CUST-1226	Debit Card
54357	2024-02-17	CUST-1226	Debit Card
54358	2024-07-21	CUST-1226	Credit Card
54359	2024-08-27	CUST-1226	Debit Card
54360	2024-09-10	CUST-1226	Credit Card
54361	2024-12-06	CUST-1226	Debit Card
54362	2024-12-14	CUST-1226	Debit Card
54363	2024-12-18	CUST-1226	Paypal
54364	2024-12-28	CUST-1226	Credit Card
54365	2025-02-14	CUST-1226	Debit Card
54366	2025-03-26	CUST-1226	Paypal
54367	2025-04-15	CUST-1226	Cash
54368	2025-07-18	CUST-1226	Cash
54369	2025-08-08	CUST-1226	Debit Card
54370	2025-08-29	CUST-1226	Cash
54371	2025-09-03	CUST-1226	Debit Card
54372	2025-11-02	CUST-1226	Paypal
54373	2025-12-13	CUST-1226	Credit Card
54374	2025-12-25	CUST-1226	Credit Card
54375	2024-01-09	CUST-1227	Debit Card
54376	2024-02-26	CUST-1227	Credit Card
54377	2024-03-07	CUST-1227	Cash
54378	2024-03-12	CUST-1227	Debit Card
54379	2024-04-07	CUST-1227	Debit Card
54380	2024-04-16	CUST-1227	Debit Card
54381	2024-04-27	CUST-1227	Debit Card
54382	2024-07-11	CUST-1227	Credit Card
54383	2024-07-19	CUST-1227	Paypal
54384	2024-08-02	CUST-1227	Paypal
54385	2024-08-05	CUST-1227	Debit Card
54386	2024-08-09	CUST-1227	Cash
54387	2024-08-26	CUST-1227	Debit Card
54388	2024-09-06	CUST-1227	Credit Card
54389	2024-10-09	CUST-1227	Paypal
54390	2024-10-29	CUST-1227	Debit Card
54391	2024-11-05	CUST-1227	Debit Card
54392	2024-11-28	CUST-1227	Debit Card
54393	2024-11-29	CUST-1227	Credit Card
54394	2024-12-03	CUST-1227	Debit Card
54395	2024-12-30	CUST-1227	Credit Card
54396	2025-05-09	CUST-1227	Credit Card
54397	2025-05-23	CUST-1227	Cash
54398	2025-05-23	CUST-1227	Debit Card
54399	2025-06-26	CUST-1227	Debit Card
54400	2025-07-08	CUST-1227	Cash
54401	2025-07-15	CUST-1227	Debit Card
54402	2025-07-29	CUST-1227	Debit Card
54403	2025-08-13	CUST-1227	Cash
54404	2025-08-26	CUST-1227	Cash
54405	2025-08-26	CUST-1227	Credit Card
54406	2025-09-24	CUST-1227	Credit Card
54407	2025-10-01	CUST-1227	Cash
54408	2025-10-08	CUST-1227	Debit Card
54409	2025-10-12	CUST-1227	Cash
54410	2025-12-01	CUST-1227	Credit Card
54411	2025-12-06	CUST-1227	Credit Card
54412	2025-12-14	CUST-1227	Debit Card
54413	2025-12-18	CUST-1227	Credit Card
54414	2025-12-19	CUST-1227	Credit Card
54415	2025-12-24	CUST-1227	Paypal
54416	2025-12-26	CUST-1227	Cash
54417	2025-12-26	CUST-1227	Debit Card
54418	2025-12-27	CUST-1227	Debit Card
54419	2024-01-18	CUST-1228	Debit Card
54420	2024-02-23	CUST-1228	Cash
54421	2024-03-03	CUST-1228	Cash
54422	2024-03-10	CUST-1228	Debit Card
54423	2024-04-03	CUST-1228	Credit Card
54424	2024-04-09	CUST-1228	Cash
54425	2024-04-16	CUST-1228	Paypal
54426	2024-05-02	CUST-1228	Debit Card
54427	2024-05-10	CUST-1228	Debit Card
54428	2024-05-19	CUST-1228	Credit Card
54429	2024-06-17	CUST-1228	Debit Card
54430	2024-06-27	CUST-1228	Paypal
54431	2024-07-06	CUST-1228	Cash
54432	2024-09-26	CUST-1228	Debit Card
54433	2024-10-11	CUST-1228	Debit Card
54434	2024-10-17	CUST-1228	Debit Card
54435	2024-11-02	CUST-1228	Cash
54436	2024-11-24	CUST-1228	Credit Card
54437	2024-12-01	CUST-1228	Credit Card
54438	2024-12-14	CUST-1228	Debit Card
54439	2025-01-24	CUST-1228	Cash
54440	2025-01-25	CUST-1228	Debit Card
54441	2025-05-06	CUST-1228	Credit Card
54442	2025-05-07	CUST-1228	Credit Card
54443	2025-07-21	CUST-1228	Credit Card
54444	2025-11-21	CUST-1228	Cash
54445	2025-12-07	CUST-1228	Credit Card
54446	2025-12-17	CUST-1228	Cash
54447	2025-12-21	CUST-1228	Debit Card
54448	2024-04-08	CUST-1229	Debit Card
54449	2024-04-18	CUST-1229	Debit Card
54450	2024-06-26	CUST-1229	Paypal
54451	2024-09-10	CUST-1229	Cash
54452	2024-10-10	CUST-1229	Credit Card
54453	2024-12-05	CUST-1229	Debit Card
54454	2025-03-11	CUST-1229	Credit Card
54455	2025-04-20	CUST-1229	Paypal
54456	2025-08-11	CUST-1229	Paypal
54457	2025-10-19	CUST-1229	Debit Card
54458	2025-12-23	CUST-1229	Paypal
54459	2025-12-27	CUST-1230	Paypal
54460	2024-03-04	CUST-1231	Cash
54461	2024-04-18	CUST-1231	Credit Card
54462	2025-11-20	CUST-1231	Credit Card
54463	2025-12-17	CUST-1231	Paypal
54464	2024-02-05	CUST-1232	Cash
54465	2024-08-30	CUST-1232	Credit Card
54466	2024-11-27	CUST-1232	Cash
54467	2024-12-10	CUST-1232	Credit Card
54468	2025-02-02	CUST-1232	Debit Card
54469	2025-04-19	CUST-1232	Credit Card
54470	2025-05-30	CUST-1232	Debit Card
54471	2025-11-10	CUST-1232	Debit Card
54472	2025-11-27	CUST-1232	Cash
54473	2025-12-27	CUST-1232	Credit Card
54474	2024-06-10	CUST-1233	Credit Card
54475	2024-08-12	CUST-1233	Credit Card
54476	2024-09-03	CUST-1233	Credit Card
54477	2024-09-09	CUST-1233	Paypal
54478	2024-10-05	CUST-1233	Credit Card
54479	2024-10-08	CUST-1233	Cash
54480	2024-11-17	CUST-1233	Debit Card
54481	2024-12-03	CUST-1233	Credit Card
54482	2024-12-31	CUST-1233	Debit Card
54483	2025-07-06	CUST-1233	Debit Card
54484	2025-09-07	CUST-1233	Paypal
54485	2025-09-16	CUST-1233	Paypal
54486	2025-09-20	CUST-1233	Credit Card
54487	2025-10-16	CUST-1233	Credit Card
54488	2025-12-22	CUST-1233	Debit Card
54489	2025-12-30	CUST-1233	Credit Card
54490	2024-05-12	CUST-1234	Cash
54491	2024-06-09	CUST-1234	Debit Card
54492	2024-12-18	CUST-1234	Cash
54493	2025-03-28	CUST-1234	Cash
54494	2025-08-12	CUST-1234	Debit Card
54495	2025-10-09	CUST-1234	Paypal
54496	2025-10-10	CUST-1234	Paypal
54497	2024-12-29	CUST-1235	Debit Card
54498	2025-01-25	CUST-1235	Paypal
54499	2025-04-16	CUST-1235	Credit Card
54500	2025-04-26	CUST-1235	Debit Card
54501	2025-05-16	CUST-1235	Paypal
54502	2025-06-14	CUST-1235	Debit Card
54503	2025-07-26	CUST-1235	Cash
54504	2025-09-18	CUST-1235	Credit Card
54505	2025-09-19	CUST-1235	Credit Card
54506	2025-11-21	CUST-1235	Credit Card
54507	2025-12-20	CUST-1235	Credit Card
54508	2024-01-04	CUST-1236	Credit Card
54509	2024-02-04	CUST-1236	Debit Card
54510	2024-05-01	CUST-1236	Credit Card
54511	2024-07-29	CUST-1236	Credit Card
54512	2024-08-17	CUST-1236	Credit Card
54513	2024-08-19	CUST-1236	Credit Card
54514	2024-08-23	CUST-1236	Credit Card
54515	2024-11-24	CUST-1236	Credit Card
54516	2025-05-08	CUST-1236	Credit Card
54517	2025-06-07	CUST-1236	Debit Card
54518	2025-09-23	CUST-1236	Cash
54519	2025-12-06	CUST-1236	Debit Card
54520	2024-05-03	CUST-1237	Debit Card
54521	2024-11-13	CUST-1237	Credit Card
54522	2025-02-09	CUST-1237	Paypal
54523	2025-08-26	CUST-1237	Debit Card
54524	2024-03-16	CUST-1238	Credit Card
54525	2024-03-20	CUST-1238	Debit Card
54526	2024-05-05	CUST-1238	Paypal
54527	2024-08-26	CUST-1238	Paypal
54528	2024-10-13	CUST-1238	Credit Card
54529	2024-12-05	CUST-1238	Debit Card
54530	2024-12-16	CUST-1238	Paypal
54531	2025-01-06	CUST-1238	Debit Card
54532	2025-01-20	CUST-1238	Credit Card
54533	2025-06-07	CUST-1238	Credit Card
54534	2025-07-25	CUST-1238	Credit Card
54535	2025-08-30	CUST-1238	Credit Card
54536	2025-09-05	CUST-1238	Credit Card
54537	2025-09-27	CUST-1238	Credit Card
54538	2025-10-20	CUST-1238	Credit Card
54539	2025-11-23	CUST-1238	Debit Card
54540	2025-12-12	CUST-1238	Debit Card
54541	2025-12-18	CUST-1238	Debit Card
54542	2024-08-12	CUST-1239	Cash
54543	2024-08-12	CUST-1239	Paypal
54544	2024-08-16	CUST-1239	Debit Card
54545	2024-08-19	CUST-1239	Cash
54546	2024-11-18	CUST-1239	Debit Card
54547	2025-09-30	CUST-1239	Credit Card
54548	2025-10-04	CUST-1239	Cash
54549	2025-10-21	CUST-1239	Credit Card
54550	2024-01-14	CUST-1240	Credit Card
54551	2024-02-05	CUST-1240	Debit Card
54552	2024-04-19	CUST-1240	Debit Card
54553	2024-04-25	CUST-1240	Credit Card
54554	2024-05-08	CUST-1240	Credit Card
54555	2024-05-27	CUST-1240	Debit Card
54556	2024-06-10	CUST-1240	Debit Card
54557	2024-07-01	CUST-1240	Credit Card
54558	2024-10-10	CUST-1240	Credit Card
54559	2024-10-30	CUST-1240	Cash
54560	2024-11-25	CUST-1240	Credit Card
54561	2024-12-13	CUST-1240	Credit Card
54562	2024-12-31	CUST-1240	Debit Card
54563	2025-03-13	CUST-1240	Debit Card
54564	2025-03-30	CUST-1240	Debit Card
54565	2025-04-28	CUST-1240	Debit Card
54566	2025-06-02	CUST-1240	Debit Card
54567	2025-06-07	CUST-1240	Cash
54568	2025-06-21	CUST-1240	Debit Card
54569	2025-08-12	CUST-1240	Credit Card
54570	2025-10-19	CUST-1240	Credit Card
54571	2025-10-31	CUST-1240	Debit Card
54572	2025-11-07	CUST-1240	Cash
54573	2024-03-27	CUST-1241	Credit Card
54574	2024-06-14	CUST-1241	Credit Card
54575	2024-07-13	CUST-1241	Credit Card
54576	2024-09-04	CUST-1241	Credit Card
54577	2024-09-18	CUST-1241	Credit Card
54578	2024-10-19	CUST-1241	Debit Card
54579	2024-11-06	CUST-1241	Debit Card
54580	2024-11-16	CUST-1241	Debit Card
54581	2025-01-16	CUST-1241	Cash
54582	2025-01-24	CUST-1241	Paypal
54583	2025-02-08	CUST-1241	Paypal
54584	2025-06-25	CUST-1241	Paypal
54585	2025-07-23	CUST-1241	Debit Card
54586	2025-08-21	CUST-1241	Paypal
54587	2025-09-14	CUST-1241	Paypal
54588	2025-10-25	CUST-1241	Credit Card
54589	2025-12-16	CUST-1241	Credit Card
54590	2024-03-07	CUST-1242	Debit Card
54591	2024-04-10	CUST-1242	Paypal
54592	2024-11-03	CUST-1242	Credit Card
54593	2024-03-12	CUST-1243	Cash
54594	2024-03-18	CUST-1243	Credit Card
54595	2024-04-09	CUST-1243	Cash
54596	2024-04-11	CUST-1243	Cash
54597	2024-04-28	CUST-1243	Cash
54598	2024-08-07	CUST-1243	Paypal
54599	2024-10-10	CUST-1243	Debit Card
54600	2025-02-23	CUST-1243	Credit Card
54601	2025-05-30	CUST-1243	Debit Card
54602	2025-07-25	CUST-1243	Cash
54603	2025-08-21	CUST-1243	Cash
54604	2025-11-04	CUST-1243	Debit Card
54605	2025-11-26	CUST-1243	Credit Card
54606	2024-02-13	CUST-1244	Credit Card
54607	2024-02-25	CUST-1244	Credit Card
54608	2024-03-13	CUST-1244	Paypal
54609	2024-03-16	CUST-1244	Cash
54610	2024-04-17	CUST-1244	Debit Card
54611	2024-05-14	CUST-1244	Debit Card
54612	2024-05-16	CUST-1244	Credit Card
54613	2024-05-21	CUST-1244	Credit Card
54614	2024-05-24	CUST-1244	Credit Card
54615	2024-06-27	CUST-1244	Credit Card
54616	2024-07-18	CUST-1244	Debit Card
54617	2024-07-27	CUST-1244	Debit Card
54618	2024-08-16	CUST-1244	Credit Card
54619	2024-08-22	CUST-1244	Paypal
54620	2024-08-27	CUST-1244	Credit Card
54621	2024-08-31	CUST-1244	Cash
54622	2024-09-10	CUST-1244	Debit Card
54623	2024-09-12	CUST-1244	Paypal
54624	2024-10-17	CUST-1244	Debit Card
54625	2024-10-23	CUST-1244	Cash
54626	2024-11-02	CUST-1244	Debit Card
54627	2024-11-06	CUST-1244	Debit Card
54628	2024-11-09	CUST-1244	Cash
54629	2024-12-13	CUST-1244	Debit Card
54630	2024-12-15	CUST-1244	Credit Card
54631	2024-12-17	CUST-1244	Debit Card
54632	2024-12-22	CUST-1244	Paypal
54633	2025-01-01	CUST-1244	Credit Card
54634	2025-02-11	CUST-1244	Credit Card
54635	2025-02-11	CUST-1244	Paypal
54636	2025-02-26	CUST-1244	Credit Card
54637	2025-04-25	CUST-1244	Debit Card
54638	2025-05-17	CUST-1244	Debit Card
54639	2025-06-03	CUST-1244	Credit Card
54640	2025-06-14	CUST-1244	Credit Card
54641	2025-06-15	CUST-1244	Debit Card
54642	2025-06-24	CUST-1244	Cash
54643	2025-07-02	CUST-1244	Debit Card
54644	2025-07-05	CUST-1244	Credit Card
54645	2025-07-05	CUST-1244	Debit Card
54646	2025-07-10	CUST-1244	Debit Card
54647	2025-07-13	CUST-1244	Cash
54648	2025-07-13	CUST-1244	Credit Card
54649	2025-07-16	CUST-1244	Debit Card
54650	2025-07-20	CUST-1244	Cash
54651	2025-07-24	CUST-1244	Credit Card
54652	2025-08-01	CUST-1244	Cash
54653	2025-09-07	CUST-1244	Paypal
54654	2025-09-14	CUST-1244	Credit Card
54655	2025-10-07	CUST-1244	Cash
54656	2025-10-07	CUST-1244	Paypal
54657	2025-10-14	CUST-1244	Debit Card
54658	2025-10-19	CUST-1244	Debit Card
54659	2025-11-08	CUST-1244	Credit Card
54660	2025-11-08	CUST-1244	Debit Card
54661	2025-11-11	CUST-1244	Credit Card
54662	2025-12-06	CUST-1244	Debit Card
54663	2025-12-21	CUST-1244	Debit Card
54664	2025-12-28	CUST-1244	Cash
54665	2024-09-13	CUST-1245	Credit Card
54666	2025-06-02	CUST-1245	Cash
54667	2024-07-12	CUST-1246	Paypal
54668	2025-11-24	CUST-1246	Paypal
54669	2024-12-22	CUST-1247	Debit Card
54670	2025-01-03	CUST-1247	Debit Card
54671	2025-04-12	CUST-1247	Credit Card
54672	2025-12-31	CUST-1247	Credit Card
54673	2024-04-22	CUST-1248	Debit Card
54674	2024-05-04	CUST-1248	Cash
54675	2024-05-15	CUST-1248	Credit Card
54676	2024-05-15	CUST-1248	Debit Card
54677	2024-05-18	CUST-1248	Debit Card
54678	2024-07-26	CUST-1248	Debit Card
54679	2024-11-26	CUST-1248	Debit Card
54680	2025-01-03	CUST-1248	Credit Card
54681	2025-04-21	CUST-1248	Debit Card
54682	2025-04-30	CUST-1248	Debit Card
54683	2025-07-21	CUST-1248	Cash
54684	2025-11-05	CUST-1248	Cash
54685	2025-12-30	CUST-1248	Cash
54686	2024-02-05	CUST-1249	Credit Card
54687	2024-09-29	CUST-1249	Credit Card
54688	2024-11-26	CUST-1249	Debit Card
54689	2025-02-06	CUST-1249	Credit Card
54690	2025-03-19	CUST-1249	Debit Card
54691	2025-07-15	CUST-1249	Credit Card
54692	2025-09-13	CUST-1249	Cash
54693	2025-09-16	CUST-1249	Credit Card
54694	2025-09-18	CUST-1249	Credit Card
54695	2025-10-17	CUST-1249	Credit Card
54696	2025-10-24	CUST-1249	Credit Card
54697	2025-11-04	CUST-1249	Cash
54698	2025-11-28	CUST-1249	Paypal
54699	2024-03-25	CUST-1250	Debit Card
54700	2024-06-08	CUST-1250	Paypal
54701	2024-11-21	CUST-1250	Debit Card
54702	2024-12-04	CUST-1250	Cash
54703	2024-12-18	CUST-1250	Credit Card
54704	2025-02-09	CUST-1250	Debit Card
54705	2025-04-02	CUST-1250	Debit Card
54706	2025-08-18	CUST-1250	Cash
54707	2025-08-28	CUST-1250	Debit Card
54708	2025-10-20	CUST-1250	Debit Card
54709	2025-11-28	CUST-1250	Paypal
54710	2024-01-02	CUST-1251	Debit Card
54711	2024-01-07	CUST-1251	Credit Card
54712	2024-01-29	CUST-1251	Debit Card
54713	2024-04-02	CUST-1251	Paypal
54714	2024-04-21	CUST-1251	Debit Card
54715	2024-05-13	CUST-1251	Debit Card
54716	2024-06-06	CUST-1251	Debit Card
54717	2024-06-14	CUST-1251	Debit Card
54718	2024-06-20	CUST-1251	Credit Card
54719	2024-07-14	CUST-1251	Debit Card
54720	2024-07-15	CUST-1251	Paypal
54721	2024-07-17	CUST-1251	Cash
54722	2024-07-21	CUST-1251	Credit Card
54723	2024-08-27	CUST-1251	Cash
54724	2024-09-12	CUST-1251	Cash
54725	2024-11-13	CUST-1251	Credit Card
54726	2024-12-10	CUST-1251	Debit Card
54727	2025-02-08	CUST-1251	Paypal
54728	2025-04-03	CUST-1251	Paypal
54729	2025-05-12	CUST-1251	Debit Card
54730	2025-05-27	CUST-1251	Credit Card
54731	2025-06-11	CUST-1251	Credit Card
54732	2025-08-04	CUST-1251	Credit Card
54733	2025-08-16	CUST-1251	Credit Card
54734	2025-09-04	CUST-1251	Credit Card
54735	2025-09-08	CUST-1251	Paypal
54736	2025-09-19	CUST-1251	Credit Card
54737	2025-10-13	CUST-1251	Debit Card
54738	2025-10-30	CUST-1251	Cash
54739	2025-11-26	CUST-1251	Credit Card
54740	2025-11-27	CUST-1251	Debit Card
54741	2025-12-01	CUST-1251	Debit Card
54742	2025-12-27	CUST-1251	Debit Card
54743	2025-12-31	CUST-1251	Debit Card
54744	2024-01-02	CUST-1253	Credit Card
54745	2024-07-19	CUST-1253	Credit Card
54746	2024-07-27	CUST-1253	Debit Card
54747	2024-08-04	CUST-1253	Credit Card
54748	2024-09-09	CUST-1253	Credit Card
54749	2024-09-29	CUST-1253	Cash
54750	2024-10-13	CUST-1253	Debit Card
54751	2024-12-14	CUST-1253	Credit Card
54752	2025-01-24	CUST-1253	Credit Card
54753	2025-02-28	CUST-1253	Debit Card
54754	2025-06-14	CUST-1253	Credit Card
54755	2025-09-01	CUST-1253	Debit Card
54756	2025-10-05	CUST-1253	Cash
54757	2025-12-19	CUST-1253	Paypal
54758	2025-12-23	CUST-1253	Credit Card
54759	2024-01-19	CUST-1254	Credit Card
54760	2024-01-30	CUST-1254	Credit Card
54761	2024-02-17	CUST-1254	Cash
54762	2024-03-03	CUST-1254	Credit Card
54763	2024-03-17	CUST-1254	Paypal
54764	2024-03-19	CUST-1254	Cash
54765	2024-04-13	CUST-1254	Cash
54766	2024-05-04	CUST-1254	Paypal
54767	2024-05-17	CUST-1254	Paypal
54768	2024-05-22	CUST-1254	Cash
54769	2024-06-24	CUST-1254	Debit Card
54770	2024-06-25	CUST-1254	Debit Card
54771	2024-07-16	CUST-1254	Cash
54772	2024-07-18	CUST-1254	Debit Card
54773	2024-08-02	CUST-1254	Cash
54774	2024-08-04	CUST-1254	Debit Card
54775	2024-08-12	CUST-1254	Credit Card
54776	2024-08-27	CUST-1254	Paypal
54777	2024-09-02	CUST-1254	Credit Card
54778	2024-09-05	CUST-1254	Debit Card
54779	2024-09-14	CUST-1254	Debit Card
54780	2024-10-05	CUST-1254	Debit Card
54781	2024-10-06	CUST-1254	Credit Card
54782	2024-10-21	CUST-1254	Paypal
54783	2024-11-18	CUST-1254	Debit Card
54784	2024-11-27	CUST-1254	Credit Card
54785	2024-12-20	CUST-1254	Credit Card
54786	2024-12-29	CUST-1254	Credit Card
54787	2024-12-31	CUST-1254	Cash
54788	2025-01-05	CUST-1254	Debit Card
54789	2025-01-10	CUST-1254	Debit Card
54790	2025-02-14	CUST-1254	Debit Card
54791	2025-02-23	CUST-1254	Debit Card
54792	2025-03-19	CUST-1254	Credit Card
54793	2025-04-20	CUST-1254	Credit Card
54794	2025-05-12	CUST-1254	Credit Card
54795	2025-05-30	CUST-1254	Credit Card
54796	2025-06-13	CUST-1254	Credit Card
54797	2025-06-25	CUST-1254	Cash
54798	2025-06-26	CUST-1254	Cash
54799	2025-07-05	CUST-1254	Credit Card
54800	2025-08-04	CUST-1254	Debit Card
54801	2025-08-22	CUST-1254	Credit Card
54802	2025-10-14	CUST-1254	Credit Card
54803	2025-10-21	CUST-1254	Cash
54804	2025-11-01	CUST-1254	Paypal
54805	2025-11-24	CUST-1254	Cash
54806	2025-11-27	CUST-1254	Credit Card
54807	2025-11-28	CUST-1254	Credit Card
54808	2025-12-07	CUST-1254	Cash
54809	2025-12-07	CUST-1254	Debit Card
54810	2025-12-15	CUST-1254	Paypal
54811	2025-12-21	CUST-1254	Credit Card
54812	2024-02-23	CUST-1255	Credit Card
54813	2024-07-13	CUST-1255	Debit Card
54814	2024-10-07	CUST-1255	Debit Card
54815	2025-09-08	CUST-1255	Paypal
54816	2025-10-28	CUST-1255	Paypal
54817	2024-02-29	CUST-1256	Paypal
54818	2024-03-27	CUST-1256	Debit Card
54819	2024-07-08	CUST-1256	Credit Card
54820	2024-08-29	CUST-1256	Credit Card
54821	2024-10-17	CUST-1256	Paypal
54822	2024-11-04	CUST-1256	Paypal
54823	2024-11-17	CUST-1256	Credit Card
54824	2024-12-22	CUST-1256	Cash
54825	2024-12-28	CUST-1256	Credit Card
54826	2025-08-28	CUST-1256	Paypal
54827	2025-10-24	CUST-1256	Credit Card
54828	2025-11-23	CUST-1256	Paypal
54829	2024-06-02	CUST-1257	Debit Card
54830	2024-12-26	CUST-1257	Debit Card
54831	2025-12-09	CUST-1257	Credit Card
54832	2024-01-12	CUST-1258	Debit Card
54833	2025-05-04	CUST-1258	Credit Card
54834	2025-08-13	CUST-1258	Credit Card
54835	2025-09-14	CUST-1258	Paypal
54836	2025-09-25	CUST-1258	Credit Card
54837	2024-02-13	CUST-1259	Debit Card
54838	2024-02-18	CUST-1259	Credit Card
54839	2024-08-10	CUST-1259	Debit Card
54840	2025-02-03	CUST-1259	Paypal
54841	2025-11-01	CUST-1259	Debit Card
54842	2025-11-30	CUST-1259	Debit Card
54843	2024-01-03	CUST-1260	Credit Card
54844	2024-02-10	CUST-1260	Paypal
54845	2024-02-20	CUST-1260	Credit Card
54846	2024-03-16	CUST-1260	Cash
54847	2024-03-25	CUST-1260	Debit Card
54848	2024-04-18	CUST-1260	Cash
54849	2024-05-06	CUST-1260	Debit Card
54850	2024-05-23	CUST-1260	Debit Card
54851	2024-06-21	CUST-1260	Cash
54852	2024-07-22	CUST-1260	Paypal
54853	2024-07-25	CUST-1260	Cash
54854	2024-07-25	CUST-1260	Paypal
54855	2024-08-14	CUST-1260	Credit Card
54856	2024-09-13	CUST-1260	Debit Card
54857	2024-10-10	CUST-1260	Credit Card
54858	2024-10-31	CUST-1260	Debit Card
54859	2024-11-26	CUST-1260	Debit Card
54860	2024-11-28	CUST-1260	Credit Card
54861	2024-11-28	CUST-1260	Debit Card
54862	2024-12-14	CUST-1260	Credit Card
54863	2024-12-24	CUST-1260	Paypal
54864	2024-12-31	CUST-1260	Paypal
54865	2025-01-21	CUST-1260	Paypal
54866	2025-02-07	CUST-1260	Paypal
54867	2025-02-24	CUST-1260	Cash
54868	2025-03-18	CUST-1260	Debit Card
54869	2025-04-29	CUST-1260	Credit Card
54870	2025-04-29	CUST-1260	Debit Card
54871	2025-05-07	CUST-1260	Credit Card
54872	2025-05-09	CUST-1260	Credit Card
54873	2025-05-28	CUST-1260	Credit Card
54874	2025-05-31	CUST-1260	Debit Card
54875	2025-07-25	CUST-1260	Debit Card
54876	2025-07-26	CUST-1260	Credit Card
54877	2025-08-30	CUST-1260	Debit Card
54878	2025-09-15	CUST-1260	Credit Card
54879	2025-09-16	CUST-1260	Debit Card
54880	2025-09-25	CUST-1260	Credit Card
54881	2025-10-10	CUST-1260	Debit Card
54882	2025-10-27	CUST-1260	Credit Card
54883	2025-11-01	CUST-1260	Credit Card
54884	2025-12-01	CUST-1260	Debit Card
54885	2024-01-02	CUST-1261	Debit Card
54886	2024-01-07	CUST-1261	Debit Card
54887	2024-01-17	CUST-1261	Paypal
54888	2024-02-12	CUST-1261	Paypal
54889	2024-02-14	CUST-1261	Cash
54890	2024-02-19	CUST-1261	Cash
54891	2024-03-07	CUST-1261	Paypal
54892	2024-03-19	CUST-1261	Credit Card
54893	2024-04-07	CUST-1261	Credit Card
54894	2024-04-15	CUST-1261	Credit Card
54895	2024-05-15	CUST-1261	Debit Card
54896	2024-05-25	CUST-1261	Paypal
54897	2024-05-27	CUST-1261	Debit Card
54898	2024-05-29	CUST-1261	Cash
54899	2024-05-31	CUST-1261	Debit Card
54900	2024-06-21	CUST-1261	Debit Card
54901	2024-06-27	CUST-1261	Cash
54902	2024-07-03	CUST-1261	Credit Card
54903	2024-07-26	CUST-1261	Credit Card
54904	2024-08-07	CUST-1261	Debit Card
54905	2024-08-17	CUST-1261	Debit Card
54906	2024-09-01	CUST-1261	Credit Card
54907	2024-09-05	CUST-1261	Credit Card
54908	2024-09-13	CUST-1261	Credit Card
54909	2024-09-16	CUST-1261	Cash
54910	2024-09-18	CUST-1261	Paypal
54911	2024-10-02	CUST-1261	Paypal
54912	2024-10-03	CUST-1261	Credit Card
54913	2024-10-17	CUST-1261	Cash
54914	2024-11-02	CUST-1261	Debit Card
54915	2024-11-17	CUST-1261	Credit Card
54916	2024-12-01	CUST-1261	Debit Card
54917	2024-12-03	CUST-1261	Debit Card
54918	2024-12-04	CUST-1261	Debit Card
54919	2024-12-06	CUST-1261	Credit Card
54920	2024-12-08	CUST-1261	Credit Card
54921	2024-12-11	CUST-1261	Paypal
54922	2024-12-14	CUST-1261	Cash
54923	2024-12-21	CUST-1261	Credit Card
54924	2024-12-27	CUST-1261	Debit Card
54925	2025-01-22	CUST-1261	Paypal
54926	2025-02-06	CUST-1261	Debit Card
54927	2025-02-26	CUST-1261	Credit Card
54928	2025-03-19	CUST-1261	Debit Card
54929	2025-03-21	CUST-1261	Credit Card
54930	2025-04-14	CUST-1261	Paypal
54931	2025-04-16	CUST-1261	Paypal
54932	2025-04-18	CUST-1261	Cash
54933	2025-04-26	CUST-1261	Cash
54934	2025-05-05	CUST-1261	Debit Card
54935	2025-05-18	CUST-1261	Credit Card
54936	2025-05-19	CUST-1261	Debit Card
54937	2025-05-29	CUST-1261	Credit Card
54938	2025-06-04	CUST-1261	Debit Card
54939	2025-06-23	CUST-1261	Credit Card
54940	2025-07-07	CUST-1261	Credit Card
54941	2025-07-11	CUST-1261	Credit Card
54942	2025-07-15	CUST-1261	Cash
54943	2025-08-02	CUST-1261	Cash
54944	2025-08-18	CUST-1261	Paypal
54945	2025-08-25	CUST-1261	Cash
54946	2025-09-16	CUST-1261	Debit Card
54947	2025-10-04	CUST-1261	Debit Card
54948	2025-10-08	CUST-1261	Debit Card
54949	2025-10-21	CUST-1261	Debit Card
54950	2025-11-13	CUST-1261	Debit Card
54951	2025-11-19	CUST-1261	Credit Card
54952	2025-11-23	CUST-1261	Cash
54953	2025-12-03	CUST-1261	Credit Card
54954	2025-12-05	CUST-1261	Debit Card
54955	2025-12-08	CUST-1261	Debit Card
54956	2025-12-09	CUST-1261	Credit Card
54957	2025-12-10	CUST-1261	Debit Card
54958	2025-12-14	CUST-1261	Credit Card
54959	2025-12-15	CUST-1261	Cash
54960	2025-12-28	CUST-1261	Debit Card
54961	2025-12-31	CUST-1261	Credit Card
54962	2024-05-11	CUST-1262	Credit Card
54963	2024-10-05	CUST-1262	Debit Card
54964	2024-12-09	CUST-1262	Debit Card
54965	2025-04-20	CUST-1262	Debit Card
54966	2025-04-24	CUST-1262	Credit Card
54967	2025-06-27	CUST-1262	Credit Card
54968	2025-09-02	CUST-1262	Cash
54969	2024-01-05	CUST-1263	Paypal
54970	2024-01-12	CUST-1263	Credit Card
54971	2024-02-08	CUST-1263	Credit Card
54972	2024-02-10	CUST-1263	Cash
54973	2024-02-14	CUST-1263	Debit Card
54974	2024-02-27	CUST-1263	Credit Card
54975	2024-03-01	CUST-1263	Paypal
54976	2024-03-09	CUST-1263	Cash
54977	2024-03-19	CUST-1263	Credit Card
54978	2024-04-08	CUST-1263	Credit Card
54979	2024-04-16	CUST-1263	Credit Card
54980	2024-04-24	CUST-1263	Debit Card
54981	2024-04-25	CUST-1263	Paypal
54982	2024-05-25	CUST-1263	Debit Card
54983	2024-05-29	CUST-1263	Credit Card
54984	2024-06-07	CUST-1263	Credit Card
54985	2024-06-24	CUST-1263	Debit Card
54986	2024-06-27	CUST-1263	Paypal
54987	2024-07-01	CUST-1263	Cash
54988	2024-07-29	CUST-1263	Paypal
54989	2024-09-04	CUST-1263	Debit Card
54990	2024-09-06	CUST-1263	Credit Card
54991	2024-09-15	CUST-1263	Cash
54992	2024-09-17	CUST-1263	Cash
54993	2024-09-22	CUST-1263	Debit Card
54994	2024-09-24	CUST-1263	Credit Card
54995	2024-10-07	CUST-1263	Cash
54996	2024-10-07	CUST-1263	Credit Card
54997	2024-10-18	CUST-1263	Debit Card
54998	2024-10-20	CUST-1263	Debit Card
54999	2024-10-23	CUST-1263	Cash
55000	2024-10-25	CUST-1263	Paypal
55001	2024-10-28	CUST-1263	Credit Card
55002	2024-10-28	CUST-1263	Paypal
55003	2024-11-16	CUST-1263	Credit Card
55004	2024-12-04	CUST-1263	Debit Card
55005	2024-12-10	CUST-1263	Credit Card
55006	2024-12-16	CUST-1263	Debit Card
55007	2024-12-21	CUST-1263	Debit Card
55008	2024-12-25	CUST-1263	Credit Card
55009	2025-01-05	CUST-1263	Debit Card
55010	2025-01-06	CUST-1263	Paypal
55011	2025-01-11	CUST-1263	Credit Card
55012	2025-01-23	CUST-1263	Cash
55013	2025-01-27	CUST-1263	Paypal
55014	2025-02-01	CUST-1263	Paypal
55015	2025-02-02	CUST-1263	Credit Card
55016	2025-02-22	CUST-1263	Debit Card
55017	2025-02-26	CUST-1263	Debit Card
55018	2025-02-26	CUST-1263	Paypal
55019	2025-03-25	CUST-1263	Debit Card
55020	2025-03-26	CUST-1263	Paypal
55021	2025-04-11	CUST-1263	Cash
55022	2025-04-15	CUST-1263	Credit Card
55023	2025-04-21	CUST-1263	Debit Card
55024	2025-04-22	CUST-1263	Paypal
55025	2025-04-24	CUST-1263	Paypal
55026	2025-05-02	CUST-1263	Debit Card
55027	2025-05-09	CUST-1263	Cash
55028	2025-05-15	CUST-1263	Cash
55029	2025-05-25	CUST-1263	Credit Card
55030	2025-05-26	CUST-1263	Credit Card
55031	2025-05-26	CUST-1263	Paypal
55032	2025-06-03	CUST-1263	Debit Card
55033	2025-07-04	CUST-1263	Credit Card
55034	2025-08-06	CUST-1263	Credit Card
55035	2025-08-20	CUST-1263	Credit Card
55036	2025-08-24	CUST-1263	Debit Card
55037	2025-08-25	CUST-1263	Debit Card
55038	2025-09-10	CUST-1263	Debit Card
55039	2025-09-16	CUST-1263	Debit Card
55040	2025-09-17	CUST-1263	Paypal
55041	2025-09-20	CUST-1263	Credit Card
55042	2025-09-27	CUST-1263	Credit Card
55043	2025-10-03	CUST-1263	Debit Card
55044	2025-10-12	CUST-1263	Credit Card
55045	2025-10-21	CUST-1263	Credit Card
55046	2025-11-21	CUST-1263	Credit Card
55047	2025-11-24	CUST-1263	Debit Card
55048	2025-11-30	CUST-1263	Debit Card
55049	2025-12-13	CUST-1263	Debit Card
55050	2025-12-15	CUST-1263	Credit Card
55051	2025-12-19	CUST-1263	Paypal
55052	2025-12-28	CUST-1263	Credit Card
55053	2024-02-26	CUST-1264	Credit Card
55054	2024-03-16	CUST-1264	Debit Card
55055	2024-04-20	CUST-1264	Cash
55056	2024-05-25	CUST-1264	Credit Card
55057	2024-07-05	CUST-1264	Debit Card
55058	2024-07-22	CUST-1264	Credit Card
55059	2024-09-11	CUST-1264	Cash
55060	2025-01-09	CUST-1264	Debit Card
55061	2025-05-05	CUST-1264	Credit Card
55062	2025-12-11	CUST-1264	Debit Card
55063	2025-12-11	CUST-1264	Paypal
55064	2025-12-29	CUST-1264	Debit Card
55065	2024-01-14	CUST-1265	Credit Card
55066	2024-01-17	CUST-1265	Credit Card
55067	2024-02-03	CUST-1265	Credit Card
55068	2024-02-07	CUST-1265	Credit Card
55069	2024-02-07	CUST-1265	Debit Card
55070	2024-02-12	CUST-1265	Credit Card
55071	2024-02-29	CUST-1265	Debit Card
55072	2024-04-09	CUST-1265	Cash
55073	2024-04-21	CUST-1265	Cash
55074	2024-04-26	CUST-1265	Credit Card
55075	2024-05-16	CUST-1265	Cash
55076	2024-05-19	CUST-1265	Credit Card
55077	2024-05-31	CUST-1265	Credit Card
55078	2024-06-13	CUST-1265	Debit Card
55079	2024-06-15	CUST-1265	Paypal
55080	2024-07-04	CUST-1265	Credit Card
55081	2024-07-22	CUST-1265	Credit Card
55082	2024-08-09	CUST-1265	Credit Card
55083	2024-08-24	CUST-1265	Credit Card
55084	2024-08-27	CUST-1265	Cash
55085	2024-09-17	CUST-1265	Credit Card
55086	2024-09-20	CUST-1265	Credit Card
55087	2024-10-17	CUST-1265	Debit Card
55088	2024-11-03	CUST-1265	Paypal
55089	2024-12-12	CUST-1265	Debit Card
55090	2024-12-16	CUST-1265	Debit Card
55091	2024-12-19	CUST-1265	Debit Card
55092	2024-12-21	CUST-1265	Debit Card
55093	2024-12-22	CUST-1265	Credit Card
55094	2024-12-22	CUST-1265	Debit Card
55095	2024-12-24	CUST-1265	Credit Card
55096	2024-12-26	CUST-1265	Credit Card
55097	2024-12-30	CUST-1265	Credit Card
55098	2024-12-31	CUST-1265	Credit Card
55099	2025-03-14	CUST-1265	Cash
55100	2025-03-21	CUST-1265	Paypal
55101	2025-03-25	CUST-1265	Debit Card
55102	2025-04-05	CUST-1265	Credit Card
55103	2025-04-10	CUST-1265	Credit Card
55104	2025-04-23	CUST-1265	Credit Card
55105	2025-05-16	CUST-1265	Cash
55106	2025-05-23	CUST-1265	Cash
55107	2025-06-03	CUST-1265	Credit Card
55108	2025-06-18	CUST-1265	Credit Card
55109	2025-07-03	CUST-1265	Credit Card
55110	2025-07-21	CUST-1265	Debit Card
55111	2025-07-24	CUST-1265	Paypal
55112	2025-07-28	CUST-1265	Debit Card
55113	2025-08-07	CUST-1265	Cash
55114	2025-08-13	CUST-1265	Credit Card
55115	2025-08-13	CUST-1265	Debit Card
55116	2025-08-21	CUST-1265	Credit Card
55117	2025-08-25	CUST-1265	Paypal
55118	2025-08-31	CUST-1265	Credit Card
55119	2025-09-07	CUST-1265	Credit Card
55120	2025-09-20	CUST-1265	Paypal
55121	2025-10-06	CUST-1265	Paypal
55122	2025-10-08	CUST-1265	Cash
55123	2025-11-01	CUST-1265	Cash
55124	2025-11-05	CUST-1265	Cash
55125	2025-11-05	CUST-1265	Debit Card
55126	2025-12-04	CUST-1265	Debit Card
55127	2025-12-16	CUST-1265	Credit Card
55128	2025-12-26	CUST-1265	Debit Card
55129	2024-02-05	CUST-1266	Paypal
55130	2024-02-06	CUST-1266	Cash
55131	2024-08-09	CUST-1266	Cash
55132	2024-12-21	CUST-1266	Credit Card
55133	2025-01-09	CUST-1266	Credit Card
55134	2025-01-24	CUST-1266	Credit Card
55135	2025-03-09	CUST-1266	Credit Card
55136	2025-04-16	CUST-1266	Credit Card
55137	2024-08-05	CUST-1267	Debit Card
55138	2024-09-05	CUST-1267	Cash
55139	2024-10-16	CUST-1267	Debit Card
55140	2024-12-21	CUST-1267	Credit Card
55141	2025-01-07	CUST-1267	Debit Card
55142	2025-02-17	CUST-1267	Cash
55143	2025-02-20	CUST-1267	Credit Card
55144	2025-04-12	CUST-1267	Cash
55145	2025-05-02	CUST-1267	Debit Card
55146	2025-06-19	CUST-1267	Cash
55147	2025-08-01	CUST-1267	Credit Card
55148	2025-08-19	CUST-1267	Credit Card
55149	2025-08-27	CUST-1267	Credit Card
55150	2025-11-19	CUST-1267	Paypal
55151	2025-12-23	CUST-1267	Paypal
55152	2024-01-23	CUST-1268	Cash
55153	2024-02-26	CUST-1268	Credit Card
55154	2024-05-18	CUST-1268	Credit Card
55155	2024-06-06	CUST-1268	Credit Card
55156	2024-11-02	CUST-1268	Paypal
55157	2025-04-13	CUST-1268	Debit Card
55158	2025-04-23	CUST-1268	Credit Card
55159	2025-06-09	CUST-1268	Credit Card
55160	2025-09-13	CUST-1268	Debit Card
55161	2025-10-24	CUST-1268	Debit Card
55162	2025-12-26	CUST-1268	Credit Card
55163	2024-01-02	CUST-1269	Debit Card
55164	2024-01-12	CUST-1269	Debit Card
55165	2024-01-13	CUST-1269	Credit Card
55166	2024-01-14	CUST-1269	Credit Card
55167	2024-01-19	CUST-1269	Debit Card
55168	2024-01-22	CUST-1269	Cash
55169	2024-01-28	CUST-1269	Cash
55170	2024-01-28	CUST-1269	Debit Card
55171	2024-01-31	CUST-1269	Cash
55172	2024-02-03	CUST-1269	Credit Card
55173	2024-02-13	CUST-1269	Credit Card
55174	2024-02-14	CUST-1269	Paypal
55175	2024-02-18	CUST-1269	Debit Card
55176	2024-02-22	CUST-1269	Credit Card
55177	2024-02-22	CUST-1269	Debit Card
55178	2024-02-26	CUST-1269	Debit Card
55179	2024-02-27	CUST-1269	Credit Card
55180	2024-03-01	CUST-1269	Debit Card
55181	2024-03-03	CUST-1269	Cash
55182	2024-03-04	CUST-1269	Debit Card
55183	2024-03-09	CUST-1269	Debit Card
55184	2024-03-10	CUST-1269	Debit Card
55185	2024-03-11	CUST-1269	Cash
55186	2024-03-12	CUST-1269	Debit Card
55187	2024-03-14	CUST-1269	Credit Card
55188	2024-03-15	CUST-1269	Credit Card
55189	2024-03-15	CUST-1269	Paypal
55190	2024-03-17	CUST-1269	Credit Card
55191	2024-03-19	CUST-1269	Credit Card
55192	2024-03-29	CUST-1269	Credit Card
55193	2024-03-30	CUST-1269	Credit Card
55194	2024-04-06	CUST-1269	Credit Card
55195	2024-04-07	CUST-1269	Credit Card
55196	2024-04-09	CUST-1269	Paypal
55197	2024-04-11	CUST-1269	Cash
55198	2024-04-11	CUST-1269	Credit Card
55199	2024-04-12	CUST-1269	Debit Card
55200	2024-04-14	CUST-1269	Cash
55201	2024-04-16	CUST-1269	Debit Card
55202	2024-04-19	CUST-1269	Credit Card
55203	2024-04-24	CUST-1269	Credit Card
55204	2024-05-04	CUST-1269	Credit Card
55205	2024-05-08	CUST-1269	Credit Card
55206	2024-05-13	CUST-1269	Credit Card
55207	2024-05-16	CUST-1269	Cash
55208	2024-05-21	CUST-1269	Cash
55209	2024-05-22	CUST-1269	Paypal
55210	2024-05-24	CUST-1269	Cash
55211	2024-05-26	CUST-1269	Credit Card
55212	2024-05-29	CUST-1269	Debit Card
55213	2024-05-30	CUST-1269	Debit Card
55214	2024-06-10	CUST-1269	Cash
55215	2024-06-14	CUST-1269	Debit Card
55216	2024-06-21	CUST-1269	Debit Card
55217	2024-06-23	CUST-1269	Debit Card
55218	2024-06-24	CUST-1269	Credit Card
55219	2024-06-25	CUST-1269	Credit Card
55220	2024-06-26	CUST-1269	Debit Card
55221	2024-06-27	CUST-1269	Debit Card
55222	2024-06-28	CUST-1269	Credit Card
55223	2024-06-28	CUST-1269	Debit Card
55224	2024-07-03	CUST-1269	Paypal
55225	2024-07-06	CUST-1269	Debit Card
55226	2024-07-15	CUST-1269	Credit Card
55227	2024-07-19	CUST-1269	Credit Card
55228	2024-07-19	CUST-1269	Debit Card
55229	2024-07-22	CUST-1269	Debit Card
55230	2024-07-22	CUST-1269	Paypal
55231	2024-07-23	CUST-1269	Debit Card
55232	2024-07-29	CUST-1269	Credit Card
55233	2024-07-31	CUST-1269	Credit Card
55234	2024-08-04	CUST-1269	Cash
55235	2024-08-05	CUST-1269	Credit Card
55236	2024-08-07	CUST-1269	Credit Card
55237	2024-08-08	CUST-1269	Debit Card
55238	2024-08-13	CUST-1269	Debit Card
55239	2024-08-17	CUST-1269	Cash
55240	2024-08-20	CUST-1269	Credit Card
55241	2024-08-30	CUST-1269	Debit Card
55242	2024-09-02	CUST-1269	Credit Card
55243	2024-09-03	CUST-1269	Debit Card
55244	2024-09-08	CUST-1269	Debit Card
55245	2024-09-10	CUST-1269	Paypal
55246	2024-09-22	CUST-1269	Debit Card
55247	2024-09-26	CUST-1269	Credit Card
55248	2024-10-01	CUST-1269	Debit Card
55249	2024-10-04	CUST-1269	Cash
55250	2024-10-07	CUST-1269	Debit Card
55251	2024-10-09	CUST-1269	Credit Card
55252	2024-10-09	CUST-1269	Debit Card
55253	2024-10-12	CUST-1269	Credit Card
55254	2024-10-17	CUST-1269	Credit Card
55255	2024-10-22	CUST-1269	Cash
55256	2024-10-25	CUST-1269	Credit Card
55257	2024-10-25	CUST-1269	Debit Card
55258	2024-10-26	CUST-1269	Debit Card
55259	2024-10-31	CUST-1269	Cash
55260	2024-11-04	CUST-1269	Debit Card
55261	2024-11-12	CUST-1269	Debit Card
55262	2024-11-12	CUST-1269	Paypal
55263	2024-11-13	CUST-1269	Paypal
55264	2024-11-14	CUST-1269	Debit Card
55265	2024-11-15	CUST-1269	Credit Card
55266	2024-11-15	CUST-1269	Debit Card
55267	2024-11-23	CUST-1269	Cash
55268	2024-11-24	CUST-1269	Credit Card
55269	2024-11-27	CUST-1269	Credit Card
55270	2024-11-27	CUST-1269	Debit Card
55271	2024-11-29	CUST-1269	Debit Card
55272	2024-12-01	CUST-1269	Paypal
55273	2024-12-03	CUST-1269	Debit Card
55274	2024-12-04	CUST-1269	Credit Card
55275	2024-12-10	CUST-1269	Debit Card
55276	2024-12-11	CUST-1269	Credit Card
55277	2024-12-12	CUST-1269	Cash
55278	2024-12-12	CUST-1269	Debit Card
55279	2024-12-13	CUST-1269	Credit Card
55280	2024-12-15	CUST-1269	Credit Card
55281	2024-12-16	CUST-1269	Paypal
55282	2024-12-18	CUST-1269	Paypal
55283	2024-12-19	CUST-1269	Debit Card
55284	2024-12-20	CUST-1269	Credit Card
55285	2024-12-22	CUST-1269	Paypal
55286	2024-12-24	CUST-1269	Debit Card
55287	2024-12-26	CUST-1269	Paypal
55288	2024-12-29	CUST-1269	Cash
55289	2024-12-29	CUST-1269	Credit Card
55290	2025-01-01	CUST-1269	Credit Card
55291	2025-01-02	CUST-1269	Credit Card
55292	2025-01-05	CUST-1269	Cash
55293	2025-01-05	CUST-1269	Credit Card
55294	2025-01-12	CUST-1269	Paypal
55295	2025-01-17	CUST-1269	Credit Card
55296	2025-01-22	CUST-1269	Credit Card
55297	2025-01-22	CUST-1269	Paypal
55298	2025-01-24	CUST-1269	Credit Card
55299	2025-01-25	CUST-1269	Debit Card
55300	2025-01-31	CUST-1269	Credit Card
55301	2025-02-03	CUST-1269	Debit Card
55302	2025-02-07	CUST-1269	Credit Card
55303	2025-02-08	CUST-1269	Debit Card
55304	2025-02-14	CUST-1269	Debit Card
55305	2025-02-16	CUST-1269	Credit Card
55306	2025-02-18	CUST-1269	Paypal
55307	2025-02-21	CUST-1269	Credit Card
55308	2025-02-24	CUST-1269	Debit Card
55309	2025-02-27	CUST-1269	Debit Card
55310	2025-03-03	CUST-1269	Credit Card
55311	2025-03-04	CUST-1269	Debit Card
55312	2025-03-13	CUST-1269	Credit Card
55313	2025-03-18	CUST-1269	Cash
55314	2025-03-20	CUST-1269	Credit Card
55315	2025-03-27	CUST-1269	Paypal
55316	2025-03-31	CUST-1269	Debit Card
55317	2025-04-03	CUST-1269	Debit Card
55318	2025-04-07	CUST-1269	Paypal
55319	2025-04-12	CUST-1269	Cash
55320	2025-04-22	CUST-1269	Debit Card
55321	2025-04-23	CUST-1269	Cash
55322	2025-04-25	CUST-1269	Credit Card
55323	2025-05-01	CUST-1269	Credit Card
55324	2025-05-01	CUST-1269	Debit Card
55325	2025-05-06	CUST-1269	Credit Card
55326	2025-05-08	CUST-1269	Cash
55327	2025-05-08	CUST-1269	Credit Card
55328	2025-05-11	CUST-1269	Debit Card
55329	2025-05-12	CUST-1269	Debit Card
55330	2025-05-15	CUST-1269	Credit Card
55331	2025-05-18	CUST-1269	Debit Card
55332	2025-05-23	CUST-1269	Paypal
55333	2025-05-25	CUST-1269	Debit Card
55334	2025-05-26	CUST-1269	Credit Card
55335	2025-05-30	CUST-1269	Debit Card
55336	2025-05-30	CUST-1269	Paypal
55337	2025-06-02	CUST-1269	Debit Card
55338	2025-06-05	CUST-1269	Debit Card
55339	2025-06-08	CUST-1269	Cash
55340	2025-06-12	CUST-1269	Debit Card
55341	2025-06-16	CUST-1269	Paypal
55342	2025-06-21	CUST-1269	Cash
55343	2025-06-22	CUST-1269	Cash
55344	2025-06-24	CUST-1269	Cash
55345	2025-06-24	CUST-1269	Paypal
55346	2025-06-30	CUST-1269	Credit Card
55347	2025-07-07	CUST-1269	Credit Card
55348	2025-07-12	CUST-1269	Credit Card
55349	2025-07-16	CUST-1269	Debit Card
55350	2025-07-21	CUST-1269	Debit Card
55351	2025-07-24	CUST-1269	Credit Card
55352	2025-07-26	CUST-1269	Paypal
55353	2025-08-03	CUST-1269	Debit Card
55354	2025-08-06	CUST-1269	Credit Card
55355	2025-08-08	CUST-1269	Credit Card
55356	2025-08-12	CUST-1269	Credit Card
55357	2025-08-14	CUST-1269	Cash
55358	2025-08-19	CUST-1269	Debit Card
55359	2025-08-20	CUST-1269	Paypal
55360	2025-08-22	CUST-1269	Credit Card
55361	2025-08-22	CUST-1269	Debit Card
55362	2025-08-24	CUST-1269	Credit Card
55363	2025-08-24	CUST-1269	Debit Card
55364	2025-08-25	CUST-1269	Paypal
55365	2025-09-05	CUST-1269	Credit Card
55366	2025-09-10	CUST-1269	Debit Card
55367	2025-09-12	CUST-1269	Paypal
55368	2025-09-14	CUST-1269	Debit Card
55369	2025-09-15	CUST-1269	Debit Card
55370	2025-09-18	CUST-1269	Debit Card
55371	2025-09-19	CUST-1269	Credit Card
55372	2025-09-23	CUST-1269	Cash
55373	2025-09-23	CUST-1269	Credit Card
55374	2025-09-27	CUST-1269	Debit Card
55375	2025-09-30	CUST-1269	Paypal
55376	2025-10-01	CUST-1269	Paypal
55377	2025-10-03	CUST-1269	Credit Card
55378	2025-10-05	CUST-1269	Cash
55379	2025-10-13	CUST-1269	Credit Card
55380	2025-10-16	CUST-1269	Debit Card
55381	2025-10-18	CUST-1269	Debit Card
55382	2025-10-23	CUST-1269	Credit Card
55383	2025-10-23	CUST-1269	Paypal
55384	2025-10-24	CUST-1269	Credit Card
55385	2025-10-25	CUST-1269	Credit Card
55386	2025-10-28	CUST-1269	Credit Card
55387	2025-10-29	CUST-1269	Debit Card
55388	2025-10-30	CUST-1269	Debit Card
55389	2025-10-31	CUST-1269	Credit Card
55390	2025-11-01	CUST-1269	Debit Card
55391	2025-11-04	CUST-1269	Credit Card
55392	2025-11-05	CUST-1269	Cash
55393	2025-11-05	CUST-1269	Credit Card
55394	2025-11-06	CUST-1269	Credit Card
55395	2025-11-07	CUST-1269	Credit Card
55396	2025-11-08	CUST-1269	Paypal
55397	2025-11-11	CUST-1269	Credit Card
55398	2025-11-13	CUST-1269	Credit Card
55399	2025-11-21	CUST-1269	Credit Card
55400	2025-11-26	CUST-1269	Credit Card
55401	2025-11-28	CUST-1269	Credit Card
55402	2025-11-28	CUST-1269	Debit Card
55403	2025-11-28	CUST-1269	Paypal
55404	2025-11-29	CUST-1269	Credit Card
55405	2025-12-01	CUST-1269	Credit Card
55406	2025-12-02	CUST-1269	Credit Card
55407	2025-12-04	CUST-1269	Paypal
55408	2025-12-06	CUST-1269	Paypal
55409	2025-12-10	CUST-1269	Cash
55410	2025-12-10	CUST-1269	Credit Card
55411	2025-12-10	CUST-1269	Paypal
55412	2025-12-11	CUST-1269	Cash
55413	2025-12-11	CUST-1269	Debit Card
55414	2025-12-13	CUST-1269	Debit Card
55415	2025-12-14	CUST-1269	Debit Card
55416	2025-12-17	CUST-1269	Paypal
55417	2025-12-18	CUST-1269	Debit Card
55418	2025-12-20	CUST-1269	Credit Card
55419	2025-12-21	CUST-1269	Credit Card
55420	2025-12-23	CUST-1269	Credit Card
55421	2025-12-27	CUST-1269	Credit Card
55422	2025-12-29	CUST-1269	Credit Card
55423	2025-12-30	CUST-1269	Credit Card
55424	2025-12-31	CUST-1269	Credit Card
55425	2024-01-28	CUST-1270	Credit Card
55426	2024-02-18	CUST-1270	Cash
55427	2024-03-01	CUST-1270	Credit Card
55428	2024-03-24	CUST-1270	Credit Card
55429	2024-04-06	CUST-1270	Credit Card
55430	2024-06-02	CUST-1270	Debit Card
55431	2024-06-30	CUST-1270	Paypal
55432	2024-07-14	CUST-1270	Debit Card
55433	2024-07-20	CUST-1270	Debit Card
55434	2024-10-12	CUST-1270	Debit Card
55435	2024-10-15	CUST-1270	Paypal
55436	2024-12-14	CUST-1270	Debit Card
55437	2024-12-30	CUST-1270	Debit Card
55438	2025-01-18	CUST-1270	Credit Card
55439	2025-01-24	CUST-1270	Credit Card
55440	2025-02-26	CUST-1270	Debit Card
55441	2025-03-22	CUST-1270	Cash
55442	2025-03-27	CUST-1270	Credit Card
55443	2025-04-05	CUST-1270	Credit Card
55444	2025-04-07	CUST-1270	Debit Card
55445	2025-04-26	CUST-1270	Credit Card
55446	2025-08-09	CUST-1270	Credit Card
55447	2025-08-16	CUST-1270	Credit Card
55448	2025-08-22	CUST-1270	Credit Card
55449	2025-09-23	CUST-1270	Cash
55450	2025-10-15	CUST-1270	Cash
55451	2025-11-06	CUST-1270	Cash
55452	2025-11-13	CUST-1270	Paypal
55453	2025-11-30	CUST-1270	Cash
55454	2025-12-10	CUST-1270	Cash
55455	2024-04-05	CUST-1271	Credit Card
55456	2024-11-02	CUST-1271	Debit Card
55457	2024-12-07	CUST-1271	Credit Card
55458	2024-01-05	CUST-1272	Debit Card
55459	2024-01-14	CUST-1272	Credit Card
55460	2024-01-25	CUST-1272	Credit Card
55461	2024-03-09	CUST-1272	Cash
55462	2024-06-09	CUST-1272	Credit Card
55463	2024-06-12	CUST-1272	Debit Card
55464	2024-07-13	CUST-1272	Cash
55465	2024-07-14	CUST-1272	Debit Card
55466	2024-08-05	CUST-1272	Cash
55467	2024-08-23	CUST-1272	Paypal
55468	2024-10-08	CUST-1272	Credit Card
55469	2024-10-19	CUST-1272	Credit Card
55470	2024-11-01	CUST-1272	Cash
55471	2024-11-14	CUST-1272	Credit Card
55472	2024-11-18	CUST-1272	Credit Card
55473	2024-11-22	CUST-1272	Paypal
55474	2024-11-30	CUST-1272	Credit Card
55475	2025-03-01	CUST-1272	Paypal
55476	2025-03-02	CUST-1272	Credit Card
55477	2025-03-20	CUST-1272	Credit Card
55478	2025-04-16	CUST-1272	Credit Card
55479	2025-04-21	CUST-1272	Debit Card
55480	2025-05-05	CUST-1272	Credit Card
55481	2025-06-05	CUST-1272	Credit Card
55482	2025-06-06	CUST-1272	Credit Card
55483	2025-06-19	CUST-1272	Debit Card
55484	2025-07-02	CUST-1272	Debit Card
55485	2025-08-20	CUST-1272	Paypal
55486	2025-08-31	CUST-1272	Debit Card
55487	2025-10-17	CUST-1272	Cash
55488	2025-10-21	CUST-1272	Paypal
55489	2025-12-07	CUST-1272	Credit Card
55490	2024-06-17	CUST-1273	Debit Card
55491	2024-10-31	CUST-1273	Credit Card
55492	2025-02-27	CUST-1273	Credit Card
55493	2025-04-06	CUST-1273	Cash
55494	2025-10-03	CUST-1273	Debit Card
55495	2025-11-19	CUST-1273	Credit Card
55496	2024-01-03	CUST-1274	Credit Card
55497	2024-01-16	CUST-1274	Paypal
55498	2024-03-05	CUST-1274	Debit Card
55499	2024-10-24	CUST-1274	Debit Card
55500	2024-11-11	CUST-1274	Paypal
55501	2024-11-15	CUST-1274	Paypal
55502	2025-06-27	CUST-1274	Paypal
55503	2025-07-03	CUST-1274	Debit Card
55504	2025-07-29	CUST-1274	Debit Card
55505	2025-07-30	CUST-1274	Cash
55506	2025-10-27	CUST-1274	Credit Card
55507	2024-01-31	CUST-1275	Credit Card
55508	2024-02-12	CUST-1275	Credit Card
55509	2024-03-06	CUST-1275	Credit Card
55510	2024-03-25	CUST-1275	Debit Card
55511	2024-03-31	CUST-1275	Cash
55512	2024-04-17	CUST-1275	Debit Card
55513	2024-06-25	CUST-1275	Credit Card
55514	2024-08-03	CUST-1275	Credit Card
55515	2024-08-12	CUST-1275	Cash
55516	2024-08-31	CUST-1275	Paypal
55517	2024-09-13	CUST-1275	Debit Card
55518	2024-11-14	CUST-1275	Debit Card
55519	2024-12-06	CUST-1275	Paypal
55520	2024-12-08	CUST-1275	Debit Card
55521	2024-12-21	CUST-1275	Debit Card
55522	2025-01-07	CUST-1275	Paypal
55523	2025-02-15	CUST-1275	Credit Card
55524	2025-03-10	CUST-1275	Debit Card
55525	2025-03-23	CUST-1275	Credit Card
55526	2025-03-29	CUST-1275	Debit Card
55527	2025-04-25	CUST-1275	Credit Card
55528	2025-04-29	CUST-1275	Credit Card
55529	2025-05-20	CUST-1275	Credit Card
55530	2025-05-26	CUST-1275	Paypal
55531	2025-06-03	CUST-1275	Debit Card
55532	2025-06-08	CUST-1275	Credit Card
55533	2025-06-12	CUST-1275	Credit Card
55534	2025-07-14	CUST-1275	Paypal
55535	2025-08-05	CUST-1275	Cash
55536	2025-09-11	CUST-1275	Credit Card
55537	2025-11-07	CUST-1275	Credit Card
55538	2025-11-08	CUST-1275	Debit Card
55539	2025-11-24	CUST-1275	Cash
55540	2025-11-28	CUST-1275	Cash
55541	2025-12-08	CUST-1275	Debit Card
55542	2025-12-14	CUST-1275	Credit Card
55543	2025-12-30	CUST-1275	Credit Card
55544	2024-01-01	CUST-1276	Debit Card
55545	2024-06-11	CUST-1276	Debit Card
55546	2024-08-15	CUST-1276	Credit Card
55547	2024-10-07	CUST-1276	Credit Card
55548	2024-10-18	CUST-1276	Paypal
55549	2025-03-09	CUST-1276	Cash
55550	2025-03-16	CUST-1276	Credit Card
55551	2025-04-29	CUST-1276	Credit Card
55552	2025-11-07	CUST-1276	Credit Card
55553	2024-02-20	CUST-1277	Credit Card
55554	2024-03-06	CUST-1277	Debit Card
55555	2024-03-29	CUST-1277	Debit Card
55556	2024-05-07	CUST-1277	Debit Card
55557	2024-05-28	CUST-1277	Credit Card
55558	2024-06-28	CUST-1277	Paypal
55559	2024-07-13	CUST-1277	Debit Card
55560	2024-07-22	CUST-1277	Credit Card
55561	2024-08-12	CUST-1277	Credit Card
55562	2024-10-02	CUST-1277	Debit Card
55563	2024-10-19	CUST-1277	Debit Card
55564	2024-10-28	CUST-1277	Debit Card
55565	2024-11-08	CUST-1277	Debit Card
55566	2024-11-20	CUST-1277	Paypal
55567	2024-12-08	CUST-1277	Debit Card
55568	2024-12-11	CUST-1277	Paypal
55569	2025-07-19	CUST-1277	Debit Card
55570	2025-08-09	CUST-1277	Credit Card
55571	2025-08-22	CUST-1277	Debit Card
55572	2025-10-11	CUST-1277	Debit Card
55573	2025-11-03	CUST-1277	Credit Card
55574	2025-12-25	CUST-1277	Debit Card
55575	2024-03-10	CUST-1278	Debit Card
55576	2024-03-16	CUST-1278	Paypal
55577	2024-04-08	CUST-1278	Debit Card
55578	2024-05-18	CUST-1278	Credit Card
55579	2024-06-29	CUST-1278	Credit Card
55580	2024-10-18	CUST-1278	Credit Card
55581	2024-12-19	CUST-1278	Credit Card
55582	2024-12-31	CUST-1278	Credit Card
55583	2025-04-22	CUST-1278	Debit Card
55584	2025-05-23	CUST-1278	Debit Card
55585	2025-07-04	CUST-1278	Paypal
55586	2025-07-28	CUST-1278	Debit Card
55587	2025-09-20	CUST-1278	Cash
55588	2025-10-06	CUST-1278	Credit Card
55589	2025-12-06	CUST-1278	Credit Card
55590	2025-12-16	CUST-1278	Credit Card
55591	2024-01-22	CUST-1279	Credit Card
55592	2024-02-13	CUST-1279	Credit Card
55593	2024-02-29	CUST-1279	Credit Card
55594	2024-04-15	CUST-1279	Credit Card
55595	2024-10-10	CUST-1279	Credit Card
55596	2024-10-13	CUST-1279	Paypal
55597	2024-10-18	CUST-1279	Debit Card
55598	2024-10-25	CUST-1279	Debit Card
55599	2024-11-08	CUST-1279	Credit Card
55600	2025-01-01	CUST-1279	Credit Card
55601	2025-01-08	CUST-1279	Debit Card
55602	2025-01-09	CUST-1279	Credit Card
55603	2025-02-25	CUST-1279	Credit Card
55604	2025-04-04	CUST-1279	Debit Card
55605	2025-04-11	CUST-1279	Cash
55606	2025-04-14	CUST-1279	Credit Card
55607	2025-04-20	CUST-1279	Credit Card
55608	2025-07-27	CUST-1279	Credit Card
55609	2025-09-09	CUST-1279	Debit Card
55610	2025-11-08	CUST-1279	Paypal
55611	2025-11-27	CUST-1279	Debit Card
55612	2024-02-21	CUST-1280	Cash
55613	2024-05-05	CUST-1280	Debit Card
55614	2024-05-31	CUST-1280	Credit Card
55615	2024-07-15	CUST-1280	Credit Card
55616	2024-07-28	CUST-1280	Paypal
55617	2024-08-09	CUST-1280	Paypal
55618	2024-08-14	CUST-1280	Debit Card
55619	2024-09-11	CUST-1280	Credit Card
55620	2024-09-20	CUST-1280	Credit Card
55621	2024-12-05	CUST-1280	Credit Card
55622	2024-12-16	CUST-1280	Credit Card
55623	2024-12-16	CUST-1280	Debit Card
55624	2025-01-14	CUST-1280	Cash
55625	2025-02-09	CUST-1280	Debit Card
55626	2025-05-18	CUST-1280	Credit Card
55627	2025-06-24	CUST-1280	Debit Card
55628	2025-08-05	CUST-1280	Debit Card
55629	2025-09-02	CUST-1280	Debit Card
55630	2025-09-29	CUST-1280	Paypal
55631	2025-10-02	CUST-1280	Debit Card
55632	2025-10-16	CUST-1280	Paypal
55633	2025-11-07	CUST-1280	Credit Card
55634	2025-11-11	CUST-1281	Debit Card
55635	2024-04-09	CUST-1282	Paypal
55636	2024-06-04	CUST-1282	Credit Card
55637	2024-06-07	CUST-1282	Cash
55638	2024-06-10	CUST-1282	Cash
55639	2024-06-16	CUST-1282	Credit Card
55640	2024-07-08	CUST-1282	Debit Card
55641	2024-08-05	CUST-1282	Cash
55642	2024-08-15	CUST-1282	Credit Card
55643	2024-10-23	CUST-1282	Credit Card
55644	2024-11-09	CUST-1282	Debit Card
55645	2024-11-11	CUST-1282	Paypal
55646	2024-12-11	CUST-1282	Debit Card
55647	2024-12-29	CUST-1282	Debit Card
55648	2025-03-12	CUST-1282	Cash
55649	2025-05-02	CUST-1282	Credit Card
55650	2025-05-11	CUST-1282	Credit Card
55651	2025-09-19	CUST-1282	Cash
55652	2025-10-14	CUST-1282	Debit Card
55653	2025-11-16	CUST-1282	Credit Card
55654	2025-11-23	CUST-1282	Credit Card
55655	2025-12-12	CUST-1282	Paypal
55656	2025-12-16	CUST-1282	Cash
55657	2025-12-27	CUST-1282	Debit Card
55658	2024-01-29	CUST-1283	Debit Card
55659	2025-03-25	CUST-1283	Credit Card
55660	2024-11-10	CUST-1284	Debit Card
55661	2025-03-23	CUST-1284	Credit Card
55662	2025-09-19	CUST-1284	Paypal
55663	2024-05-02	CUST-1285	Debit Card
55664	2024-05-07	CUST-1285	Cash
55665	2024-08-10	CUST-1285	Paypal
55666	2024-11-09	CUST-1285	Debit Card
55667	2024-12-06	CUST-1285	Debit Card
55668	2024-12-23	CUST-1285	Cash
55669	2025-01-26	CUST-1285	Credit Card
55670	2025-02-22	CUST-1285	Cash
55671	2025-05-21	CUST-1285	Paypal
55672	2025-09-14	CUST-1285	Debit Card
55673	2025-10-26	CUST-1285	Debit Card
55674	2025-11-23	CUST-1285	Cash
55675	2025-12-10	CUST-1285	Credit Card
55676	2025-12-26	CUST-1285	Debit Card
55677	2024-05-03	CUST-1286	Paypal
55678	2024-06-15	CUST-1286	Credit Card
55679	2024-07-02	CUST-1286	Cash
55680	2024-08-16	CUST-1286	Credit Card
55681	2024-09-08	CUST-1286	Credit Card
55682	2024-09-21	CUST-1286	Cash
55683	2024-12-09	CUST-1286	Cash
55684	2024-12-12	CUST-1286	Debit Card
55685	2024-12-25	CUST-1286	Credit Card
55686	2025-01-05	CUST-1286	Credit Card
55687	2025-08-04	CUST-1286	Cash
55688	2025-08-16	CUST-1286	Credit Card
55689	2025-08-18	CUST-1286	Cash
55690	2025-09-13	CUST-1286	Credit Card
55691	2025-10-22	CUST-1286	Cash
55692	2025-10-24	CUST-1286	Paypal
55693	2025-11-24	CUST-1286	Paypal
55694	2024-02-12	CUST-1287	Paypal
55695	2024-09-04	CUST-1287	Credit Card
55696	2024-11-13	CUST-1287	Debit Card
55697	2024-11-21	CUST-1287	Cash
55698	2025-01-21	CUST-1287	Credit Card
55699	2025-03-13	CUST-1287	Cash
55700	2025-04-24	CUST-1287	Credit Card
55701	2024-02-14	CUST-1288	Debit Card
55702	2024-03-30	CUST-1288	Credit Card
55703	2024-05-10	CUST-1288	Credit Card
55704	2024-05-26	CUST-1288	Debit Card
55705	2024-07-04	CUST-1288	Credit Card
55706	2024-07-07	CUST-1288	Paypal
55707	2024-07-27	CUST-1288	Credit Card
55708	2024-08-25	CUST-1288	Cash
55709	2024-09-05	CUST-1288	Credit Card
55710	2024-09-26	CUST-1288	Credit Card
55711	2024-11-02	CUST-1288	Debit Card
55712	2025-01-31	CUST-1288	Debit Card
55713	2025-03-12	CUST-1288	Cash
55714	2025-04-03	CUST-1288	Debit Card
55715	2025-06-08	CUST-1288	Credit Card
55716	2025-06-14	CUST-1288	Debit Card
55717	2025-06-27	CUST-1288	Debit Card
55718	2025-08-15	CUST-1288	Debit Card
55719	2025-08-20	CUST-1288	Credit Card
55720	2025-08-29	CUST-1288	Paypal
55721	2025-09-29	CUST-1288	Credit Card
55722	2025-12-01	CUST-1288	Paypal
55723	2025-12-04	CUST-1288	Cash
55724	2024-05-02	CUST-1289	Debit Card
55725	2024-05-24	CUST-1289	Paypal
55726	2025-07-16	CUST-1289	Debit Card
55727	2024-04-12	CUST-1290	Cash
55728	2024-06-13	CUST-1290	Cash
55729	2024-08-30	CUST-1290	Credit Card
55730	2024-11-14	CUST-1290	Cash
55731	2025-03-23	CUST-1290	Credit Card
55732	2025-07-08	CUST-1290	Credit Card
55733	2024-01-13	CUST-1291	Credit Card
55734	2024-03-23	CUST-1291	Cash
55735	2024-03-25	CUST-1291	Cash
55736	2024-05-16	CUST-1291	Cash
55737	2024-08-05	CUST-1291	Paypal
55738	2024-09-26	CUST-1291	Credit Card
55739	2024-11-20	CUST-1291	Cash
55740	2025-02-17	CUST-1291	Credit Card
55741	2025-06-19	CUST-1291	Paypal
55742	2024-03-15	CUST-1292	Paypal
55743	2024-06-15	CUST-1292	Debit Card
55744	2024-07-01	CUST-1292	Credit Card
55745	2024-08-28	CUST-1292	Credit Card
55746	2024-09-06	CUST-1292	Paypal
55747	2024-11-25	CUST-1292	Credit Card
55748	2025-04-09	CUST-1292	Credit Card
55749	2025-07-30	CUST-1292	Debit Card
55750	2025-11-11	CUST-1292	Credit Card
55751	2025-11-13	CUST-1292	Credit Card
55752	2024-02-03	CUST-1293	Debit Card
55753	2024-03-04	CUST-1293	Credit Card
55754	2024-09-29	CUST-1293	Debit Card
55755	2024-10-13	CUST-1293	Cash
55756	2024-12-12	CUST-1293	Credit Card
55757	2025-02-10	CUST-1293	Cash
55758	2025-05-04	CUST-1293	Debit Card
55759	2025-06-29	CUST-1293	Credit Card
55760	2025-07-19	CUST-1293	Credit Card
55761	2025-08-06	CUST-1293	Debit Card
55762	2025-08-17	CUST-1293	Paypal
55763	2025-08-22	CUST-1293	Credit Card
55764	2025-11-02	CUST-1293	Credit Card
55765	2025-11-06	CUST-1293	Paypal
55766	2025-12-17	CUST-1293	Paypal
55767	2024-07-17	CUST-1294	Credit Card
55768	2024-11-03	CUST-1294	Debit Card
55769	2025-05-07	CUST-1294	Credit Card
55770	2025-09-09	CUST-1294	Credit Card
55771	2024-01-15	CUST-1295	Credit Card
55772	2024-01-21	CUST-1295	Debit Card
55773	2024-02-06	CUST-1295	Debit Card
55774	2024-02-19	CUST-1295	Cash
55775	2024-02-20	CUST-1295	Debit Card
55776	2024-05-26	CUST-1295	Paypal
55777	2024-05-30	CUST-1295	Debit Card
55778	2024-09-16	CUST-1295	Credit Card
55779	2024-09-29	CUST-1295	Credit Card
55780	2024-11-09	CUST-1295	Debit Card
55781	2024-11-22	CUST-1295	Cash
55782	2024-12-23	CUST-1295	Cash
55783	2024-12-25	CUST-1295	Paypal
55784	2024-12-31	CUST-1295	Credit Card
55785	2025-01-17	CUST-1295	Credit Card
55786	2025-02-18	CUST-1295	Debit Card
55787	2025-04-03	CUST-1295	Debit Card
55788	2025-08-09	CUST-1295	Debit Card
55789	2025-08-13	CUST-1295	Cash
55790	2025-09-11	CUST-1295	Debit Card
55791	2025-11-04	CUST-1295	Credit Card
55792	2025-11-21	CUST-1295	Credit Card
55793	2025-11-24	CUST-1295	Credit Card
55794	2025-11-25	CUST-1295	Cash
55795	2025-12-13	CUST-1295	Debit Card
55796	2025-12-21	CUST-1295	Credit Card
55797	2024-02-03	CUST-1296	Credit Card
55798	2024-05-06	CUST-1296	Debit Card
55799	2025-02-14	CUST-1296	Paypal
55800	2025-03-29	CUST-1296	Debit Card
55801	2025-06-21	CUST-1296	Credit Card
55802	2025-08-11	CUST-1296	Cash
55803	2025-11-15	CUST-1296	Debit Card
55804	2025-11-18	CUST-1296	Cash
55805	2024-02-13	CUST-1297	Credit Card
55806	2025-03-03	CUST-1297	Paypal
55807	2024-03-11	CUST-1298	Credit Card
55808	2024-12-28	CUST-1298	Paypal
55809	2025-03-16	CUST-1298	Credit Card
55810	2025-03-20	CUST-1298	Credit Card
55811	2024-01-12	CUST-1299	Credit Card
55812	2024-04-08	CUST-1299	Credit Card
55813	2024-05-03	CUST-1299	Credit Card
55814	2024-05-30	CUST-1299	Credit Card
55815	2024-06-26	CUST-1299	Credit Card
55816	2024-10-20	CUST-1299	Cash
55817	2024-11-22	CUST-1299	Credit Card
55818	2024-12-03	CUST-1299	Debit Card
55819	2025-03-29	CUST-1299	Credit Card
55820	2025-07-21	CUST-1299	Credit Card
55821	2025-09-22	CUST-1299	Credit Card
55822	2025-10-03	CUST-1299	Debit Card
55823	2025-10-04	CUST-1299	Credit Card
55824	2025-10-14	CUST-1299	Credit Card
55825	2025-11-23	CUST-1299	Paypal
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (product_id, product_name, category_id, list_price) FROM stdin;
1	Air Fryer	3	110.16
2	Blender	3	69.82
3	Bookcase	2	129.86
4	Cookware Set	3	150.05
5	Headphones	5	90.30
6	Jacket	1	95.00
7	Jeans	1	59.79
8	Laptop	5	754.04
9	Notebook Pack	4	12.00
10	Office Chair	2	180.65
11	Pen Set	4	8.97
12	Printer Paper	4	25.04
13	Smartphone	5	521.13
14	Smartwatch	5	210.51
15	Sneakers	1	80.07
16	Sofa	2	639.68
17	Standing Desk	2	418.10
18	Stapler	4	15.07
19	T-Shirt	1	21.98
20	Tablet	5	330.67
\.


--
-- Data for Name: regions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.regions (region_id, region_name) FROM stdin;
1	Central
2	East
3	North
4	South
5	West
\.


--
-- Name: categories categories_category_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_category_name_key UNIQUE (category_name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (category_id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (item_id);


--
-- Name: order_items order_items_source_line_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_source_line_id_key UNIQUE (source_line_id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- Name: products products_product_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_product_name_key UNIQUE (product_name);


--
-- Name: regions regions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.regions
    ADD CONSTRAINT regions_pkey PRIMARY KEY (region_id);


--
-- Name: regions regions_region_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.regions
    ADD CONSTRAINT regions_region_name_key UNIQUE (region_name);


--
-- Name: idx_customers_region; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_region ON public.customers USING btree (region_id);


--
-- Name: idx_items_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_order ON public.order_items USING btree (order_id);


--
-- Name: idx_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_product ON public.order_items USING btree (product_id);


--
-- Name: idx_orders_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_customer ON public.orders USING btree (customer_id);


--
-- Name: idx_orders_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_date ON public.orders USING btree (order_date);


--
-- Name: idx_products_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_category ON public.products USING btree (category_id);


--
-- Name: customers customers_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.regions(region_id);


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id);


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(category_id);


--
-- PostgreSQL database dump complete
--

\unrestrict O8i12dvruRpM8Gr43k6MZ0Cv8hbWX5ehTwaXFMjOEs4nWVn3Z5t88sbbSu5Dc1M

