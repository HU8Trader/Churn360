/*============================================================================
  FILE     : 02_Bronze_Create.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Creates the bronze raw-landing table for the Telco customer churn source
  file (Telco_customer_churn.xlsx, sheet: Telco_Churn).

  DESIGN
  ------
  One column per source field, all stored as nvarchar. No business logic is
  applied here. The bronze layer exists ONLY to retain the raw record and to
  feed the silver layer.

  IMPORTANT
  ---------
  * This script DROPS and RECREATES the table. Run it only when you want to
    reset the raw layer.
  * After creating the table, the source Excel must be ingested into it
    (e.g. via etl\load_bronze.ps1 using PowerShell + SqlBulkCopy).
  * Downstream consumers should never query bronze for analysis.

  USAGE
  -----
  Run after 01_Create_Schemas.sql. Safe to re-run (idempotent).

  RUN ORDER
  ---------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql
    3. 02_Bronze_Create.sql   <-- THIS FILE
    4. 03_Silver_Create.sql
    5. 04_Gold_Create.sql
    6. 05_Silver_Load.sql
    7. 06_Gold_Load.sql

  EXPECTED RESULT
  ---------------
  7,043 rows / 33 columns. 11 records have blank Total Charges (new
  customers, tenure = 0). 5,174 records have a blank Churn Reason
  (these are the non-churners).
============================================================================*/

USE [Customer_Analysis];
GO

-- Drop the existing table so the script is re-runnable.
IF OBJECT_ID(N'bronze.telco_customer_churn', N'U') IS NOT NULL
    DROP TABLE [bronze].[telco_customer_churn];
GO

CREATE TABLE [bronze].[telco_customer_churn]
(
    [customer_id]            nvarchar(10)  NULL,   -- unique customer identifier
    [count]                  nvarchar(3)   NULL,   -- row counter (always 1; not used in analysis)
    [country]                nvarchar(20)  NULL,   -- country (United States)
    [state]                  nvarchar(20)  NULL,   -- state (California)
    [city]                   nvarchar(50)  NULL,   -- city of residence
    [zip_code]               nvarchar(5)   NULL,   -- postal code
    [lat_long]               nvarchar(50)  NULL,   -- combined lat/long string (original)
    [latitude]               nvarchar(15)  NULL,   -- latitude coordinate
    [longitude]              nvarchar(15)  NULL,   -- longitude coordinate
    [gender]                 nvarchar(10)  NULL,   -- Male / Female
    [senior_citizen]         nvarchar(3)   NULL,   -- Yes / No
    [partner]                nvarchar(3)   NULL,   -- Yes / No (has partner)
    [dependents]             nvarchar(3)   NULL,   -- Yes / No (has dependents)
    [tenure_months]          nvarchar(3)   NULL,   -- months as a subscriber (0 - 72)
    [phone_service]          nvarchar(3)   NULL,   -- Yes / No
    [multiple_lines]         nvarchar(20)  NULL,   -- Yes / No / No phone service
    [internet_service]       nvarchar(20)  NULL,   -- DSL / Fiber optic / No
    [online_security]        nvarchar(20)  NULL,   -- Yes / No / No internet service
    [online_backup]          nvarchar(20)  NULL,   -- Yes / No / No internet service
    [device_protection]      nvarchar(20)  NULL,   -- Yes / No / No internet service
    [tech_support]           nvarchar(20)  NULL,   -- Yes / No / No internet service
    [streaming_tv]           nvarchar(20)  NULL,   -- Yes / No / No internet service
    [streaming_movies]       nvarchar(20)  NULL,   -- Yes / No / No internet service
    [contract]               nvarchar(20)  NULL,   -- Month-to-month / One year / Two year
    [paperless_billing]      nvarchar(3)   NULL,   -- Yes / No
    [payment_method]         nvarchar(30)  NULL,   -- Electronic check / Mailed check / Credit card (automatic) / Bank transfer (automatic)
    [monthly_charges]        nvarchar(10)  NULL,   -- monthly billing amount
    [total_charges]          nvarchar(10)  NULL,   -- lifetime billed amount (BLANK for 0-tenure customers)
    [churn_label]            nvarchar(3)   NULL,   -- Yes = churned / No = active
    [churn_value]            nvarchar(3)   NULL,   -- 1 = churned / 0 = active
    [churn_score]            nvarchar(3)   NULL,   -- 0 - 100 churn likelihood score
    [cltv]                   nvarchar(4)   NULL,   -- customer lifetime value
    [churn_reason]           nvarchar(100) NULL    -- stated churn reason (NULL for active customers)
);
GO

-- Confirm the table exists (expect 0 rows until the Excel load runs).
SELECT COUNT(*) AS Bronze_Row_Count
FROM [bronze].[telco_customer_churn];
GO