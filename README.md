# online-retail-sales-analytics
End-to-end retail sales analysis using PostgreSQL, Supabase, and Power BI.
[← Back to Portfolio](https://github.com/Cnae26/DATA-ANALYTICS-PORTFOLIO)

## Data Source

This project uses the
[Online Retail II dataset from the UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/502/online%2Bretail%2Bii).

The original dataset contains 1,067,371 transaction-line records covering
December 2009 to December 2011. This project uses the `Year 2010-2011`
worksheet, containing 541,910 rows from 1 December 2010 to 9 December 2011.

The dataset is licensed under the Creative Commons Attribution 4.0
International license (CC BY 4.0).

**Citation:** Chen, D. (2012). Online Retail II [Dataset].
UCI Machine Learning Repository. https://doi.org/10.24432/C5CG6D

## Project Background

This project analyzes transaction-level data from a UK-based online retailer.
The objective is to evaluate sales performance, product performance, customer
behavior, returns, and geographic markets using PostgreSQL and Power BI.

## Tools

- PostgreSQL
- Supabase
- SQL
- Power BI

## Data Structure & Initial Checks

The dataset contains 541,910 transaction-line records from December 2010 to
December 2011. Each row represents one product line within an invoice rather
than one complete order.

The dataset contains the following fields:

| Column | Description |
|---|---|
| Invoice | Invoice number; values beginning with C indicate cancellations |
| StockCode | Product identifier |
| Description | Product description |
| Quantity | Number of units purchased or returned |
| InvoiceDate | Transaction date and time |
| Price | Unit price in GBP |
| Customer ID | Customer identifier |
| Country | Customer country |

Initial data profiling identified:

- Missing product descriptions
- Missing Customer IDs
- Cancelled invoices beginning with C
- Negative quantities
- Zero and negative prices
- Exact duplicate records
- Non-product stock codes and adjustment records
- An incomplete final month in December 2011

The SQL used for data profiling is available here:

## SQL Analysis

The SQL workflow is organized into the following stages:

1. [Data Profiling](./sql/01_data_profiling.sql)
2. [Data Cleaning](./sql/02_data_cleaning.sql)
3. [Executive Sales Analysis](./sql/03_executive_sales.sql)
4. [Product Performance](./sql/04_product_performance.sql)
5. [Customer Analytics](./sql/05_customer_analytics.sql)
6. [Returns and Cancellations](./sql/06_returns_cancellations.sql)
7. [Geographic Analysis](./sql/07_geographic_analysis.sql)

## Analysis Areas

1. Executive Sales Overview
2. Product Performance
3. Customer Analytics
4. Returns and Cancellations
5. Geographic Analysis

## Project Status

- [x] Data profiling
- [x] Data cleaning and validation
- [x] Executive sales analysis
- [x] Product performance analysis
- [x] Customer analytics
- [x] Returns and cancellations analysis
- [x] Geographic analysis
- [ ] Power BI dashboard
- [ ] Business insights and recommendations
