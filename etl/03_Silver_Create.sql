/*============================================================================
  FILE     : 03_Silver_Create.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Creates the silver conformed table. This is the cleansed, typed, single
  record-per-customer view of the source data.

  DESIGN
  ------
  * Correct data types (decimal / tinyint / smallint / int / bit / datetime2)
    instead of raw nvarchar.
  * Yes/No flags stored as bit.
  * Audit column dwh_create_date stamped by the load process.
  * Nulls are meaningful: TotalCharges NULL = new customer (0 tenure),
    ChurnReason NULL = active (non-churner).

  USAGE
  -----
  Run after 02_Bronze_Create.sql. Safe to re-run (idempotent).
  Data is loaded later by 05_Silver_Load.sql.

  RUN ORDER
  ---------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql
    3. 02_Bronze_Create.sql
    4. 03_Silver_Create.sql   <-- THIS FILE
    5. 04_Gold_Create.sql
    6. 05_Silver_Load.sql
    7. 06_Gold_Load.sql
============================================================================*/

USE [Customer_Analysis];
GO

-- Drop the existing table so the script is re-runnable.
IF OBJECT_ID(N'silver.customer', N'U') IS NOT NULL
    DROP TABLE [silver].[customer];
GO

CREATE TABLE [silver].[customer]
(
    [customer_id]        nvarchar(10)    NOT NULL,   -- unique customer identifier (natural key)
    [count]              smallint        NULL,       -- row counter (not used in analysis)
    [country]            nvarchar(50)    NULL,       -- country
    [state]              nvarchar(50)    NULL,       -- state
    [city]               nvarchar(100)   NULL,       -- city
    [zip_code]           nvarchar(10)    NULL,       -- postal code
    [lat_long]           nvarchar(50)    NULL,       -- original combined lat/long string
    [latitude]           decimal(9,6)    NULL,       -- latitude coordinate
    [longitude]          decimal(9,6)    NULL,       -- longitude coordinate
    [gender]             nvarchar(10)    NULL,       -- Male / Female
    [senior_citizen]     bit             NULL,       -- 1 = senior citizen
    [partner]            bit             NULL,       -- 1 = has partner
    [dependents]         bit             NULL,       -- 1 = has dependents
    [tenure_months]      tinyint         NULL,       -- months as subscriber (0-72)
    [phone_service]      bit             NULL,       -- 1 = has phone service
    [multiple_lines]     nvarchar(20)    NULL,       -- Yes / No / No phone service
    [internet_service]   nvarchar(20)    NULL,       -- DSL / Fiber optic / No
    [online_security]    nvarchar(20)    NULL,       -- Yes / No / No internet service
    [online_backup]      nvarchar(20)    NULL,       -- Yes / No / No internet service
    [device_protection]  nvarchar(20)    NULL,       -- Yes / No / No internet service
    [tech_support]       nvarchar(20)    NULL,       -- Yes / No / No internet service
    [streaming_tv]       nvarchar(20)    NULL,       -- Yes / No / No internet service
    [streaming_movies]   nvarchar(20)    NULL,       -- Yes / No / No internet service
    [contract]           nvarchar(20)    NULL,       -- Month-to-month / One year / Two year
    [paperless_billing]  bit             NULL,       -- 1 = paperless billing
    [payment_method]     nvarchar(30)    NULL,       -- payment method
    [monthly_charges]    decimal(10,2)   NULL,       -- monthly billing amount
    [total_charges]      decimal(10,2)   NULL,       -- lifetime billed amount (NULL = new customer)
    [churn_label]        nvarchar(5)     NULL,       -- Yes = churned / No = active
    [churn_value]        tinyint         NULL,       -- 1 = churned / 0 = active
    [churn_score]        smallint        NULL,       -- 0-100 churn likelihood
    [cltv]               int             NULL,       -- customer lifetime value
    [churn_reason]       nvarchar(200)   NULL,       -- stated churn reason (NULL = active)
    [dwh_create_date]    datetime2       NOT NULL
        CONSTRAINT DF_customer_dwh_create_date DEFAULT (SYSDATETIME())   -- audit timestamp
);
GO

-- Confirm the table exists (expect 0 rows until 05_Silver_Load.sql runs).
SELECT COUNT(*) AS Silver_Row_Count
FROM [silver].[customer];
GO