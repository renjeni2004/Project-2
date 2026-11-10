# Executive Sales Report - Business Intelligence Dashboard

**Data source:** PostgreSQL database `salesdb` (views `vw_sales_detail`, `vw_monthly_revenue`, `vw_product_performance`, `vw_category_yearly`)  
**Period:** 01 Jan 2024 - 31 Dec 2025

## 1. Headline KPIs

| KPI | Value | How it is defined |
|---|---|---|
| Total revenue | $1,520,264 | SUM of line revenue (quantity x price x (1 - discount)) |
| Orders | 5,825 | Distinct order_id |
| Customers | 292 | Distinct customer_id |
| Average order value | $261 | Revenue / orders |
| Units sold | 13,116 | SUM of quantity |
| Revenue growth 2024 to 2025 | +4.6% | Year-over-year change |

## 2. Revenue analysis

- Best month: **2024-12** ($101,432); weakest: **2024-01** ($34,749).
- Q4 contributes **33.5%** of revenue: clear holiday-season seasonality.

| Category | Revenue (last year) | YoY growth |
|---|---|---|
| Home & Kitchen | $65,650 | -3.2% |
| Furniture | $172,763 | +2.9% |
| Technology | $416,679 | +5.5% |
| Office Supplies | $45,788 | +6.7% |
| Clothing | $76,236 | +9.6% |

## 3. Product performance

| Rank | Product | Category | Revenue | Share |
|---|---|---|---|---|
| 1 | Laptop | Technology | $300,999 | 19.8% |
| 2 | Smartphone | Technology | $241,829 | 15.9% |
| 3 | Sofa | Furniture | $156,273 | 10.3% |
| 4 | Tablet | Technology | $140,713 | 9.3% |
| 5 | Standing Desk | Furniture | $103,949 | 6.8% |

## 4. Customer analytics (RFM segmentation)

The top 10% of customers generate **41.5%** of revenue.

| Segment | Customers | Revenue | Share of revenue |
|---|---|---|---|
| Champions | 79 | $976,690 | 64.2% |
| Loyal | 58 | $279,744 | 18.4% |
| Needs Attention | 63 | $136,023 | 8.9% |
| At Risk (high value) | 8 | $49,289 | 3.2% |
| Hibernating | 84 | $78,519 | 5.2% |

## 5. Regional analysis

| Region | Revenue | Share | Avg monthly target attainment* |
|---|---|---|---|
| East | $552,621 | 36.4% | 96% |
| South | $292,122 | 19.2% | 97% |
| West | $287,248 | 18.9% | 96% |
| North | $250,553 | 16.5% | 99% |
| Central | $137,720 | 9.1% | 96% |

*Targets are illustrative assumptions defined in `scripts/wrangling.py` (stand-in for an external targets file).

## 6. Recommendations

1. **Protect the core:** Laptop and Smartphone lead revenue; guarantee stock before Q4.
2. **Retain high-value customers:** 8 high-value customers have gone quiet; run a win-back campaign ($49,289 historic revenue).
3. **Reward Champions:** 79 customers deliver 64% of revenue; launch a loyalty programme.
4. **Fix the weakest region:** Central is last in revenue; investigate coverage and stock.
5. **Review Home & Kitchen:** slowest YoY growth (-3.2%).
6. **Plan around seasonality:** build campaigns for Jan-Feb to soften the post-holiday drop.
