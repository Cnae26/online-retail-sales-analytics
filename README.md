# online-retail-sales-analytics
End-to-end retail sales analysis using PostgreSQL, Supabase, and Power BI.
[← Back to Portfolio](https://github.com/Cnae26/DATA-ANALYTICS-PORTFOLIO)

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

[View Data Profiling SQL](./sql/01_data_profiling.sql)

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
