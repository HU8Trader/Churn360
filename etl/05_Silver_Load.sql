/*============================================================================
  FILE     : 05_Silver_Load.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Loads silver.customer from bronze.telco_customer_churn.

  CLEANSING RULES APPLIED
  -----------------------
  1. Trim      : LTRIM/RTRIM on every character column.
  2. Booleans  : Yes -> 1, No -> 0 (senior_citizen, partner, dependents,
                 phone_service, paperless_billing).
  3. Numerics  : TRY_CONVERT to decimal/smallint/int so bad values become
                 NULL instead of failing the load.
  4. Nulls     : Blank Total Charges -> NULL (new customer).
                 Blank Churn Reason  -> NULL (non-churner).

  USAGE
  -----
  Run after 04_Gold_Create.sql AND after bronze has been populated
  (etl\load_bronze.ps1 or a bulk-load of the source workbook).
  Safe to re-run (truncates and reloads).

  RUN ORDER
  ---------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql
    3. 02_Bronze_Create.sql
    4. 03_Silver_Create.sql
    5. 04_Gold_Create.sql
    6. 05_Silver_Load.sql   <-- THIS FILE
    7. 06_Gold_Load.sql
============================================================================*/

USE [Customer_Analysis];
GO

-- Reset the table so this script can be re-run safely.
TRUNCATE TABLE [silver].[customer];
GO

INSERT INTO [silver].[customer]
(
    [customer_id], [count], [country], [state], [city], [zip_code], [lat_long],
    [latitude], [longitude], [gender], [senior_citizen], [partner], [dependents],
    [tenure_months], [phone_service], [multiple_lines], [internet_service],
    [online_security], [online_backup], [device_protection], [tech_support],
    [streaming_tv], [streaming_movies], [contract], [paperless_billing],
    [payment_method], [monthly_charges], [total_charges], [churn_label],
    [churn_value], [churn_score], [cltv], [churn_reason], [dwh_create_date]
)
SELECT
    LTRIM(RTRIM([customer_id])),
    TRY_CONVERT(smallint, [count]),
    LTRIM(RTRIM([country])),
    LTRIM(RTRIM([state])),
    LTRIM(RTRIM([city])),
    LTRIM(RTRIM([zip_code])),
    LTRIM(RTRIM([lat_long])),
    TRY_CONVERT(decimal(9,6), [latitude]),
    TRY_CONVERT(decimal(9,6), [longitude]),
    LTRIM(RTRIM([gender])),
    CASE WHEN [senior_citizen] = 'Yes' THEN 1 WHEN [senior_citizen] = 'No' THEN 0 END,
    CASE WHEN [partner]        = 'Yes' THEN 1 WHEN [partner]        = 'No' THEN 0 END,
    CASE WHEN [dependents]     = 'Yes' THEN 1 WHEN [dependents]     = 'No' THEN 0 END,
    TRY_CONVERT(tinyint, [tenure_months]),
    CASE WHEN [phone_service] = 'Yes' THEN 1 WHEN [phone_service] = 'No' THEN 0 END,
    LTRIM(RTRIM([multiple_lines])),
    LTRIM(RTRIM([internet_service])),
    LTRIM(RTRIM([online_security])),
    LTRIM(RTRIM([online_backup])),
    LTRIM(RTRIM([device_protection])),
    LTRIM(RTRIM([tech_support])),
    LTRIM(RTRIM([streaming_tv])),
    LTRIM(RTRIM([streaming_movies])),
    LTRIM(RTRIM([contract])),
    CASE WHEN [paperless_billing] = 'Yes' THEN 1 WHEN [paperless_billing] = 'No' THEN 0 END,
    LTRIM(RTRIM([payment_method])),
    TRY_CONVERT(decimal(10,2), [monthly_charges]),
    CASE WHEN [total_charges] = '' THEN NULL ELSE TRY_CONVERT(decimal(10,2), [total_charges]) END,
    LTRIM(RTRIM([churn_label])),
    TRY_CONVERT(tinyint, [churn_value]),
    TRY_CONVERT(smallint, [churn_score]),
    TRY_CONVERT(int, [cltv]),
    NULLIF(LTRIM(RTRIM([churn_reason])), ''),
    SYSDATETIME()
FROM [bronze].[telco_customer_churn];
GO

-- Confirm the load.
SELECT
    COUNT(*)                                                       AS Silver_Row_Count,
    SUM(CASE WHEN [churn_label] = 'Yes' THEN 1 ELSE 0 END)          AS Churners,
    SUM(CASE WHEN [total_charges] IS NULL THEN 1 ELSE 0 END)        AS New_Customers_No_TotalCharges,
    MIN([monthly_charges])                                          AS Min_Monthly_Charges,
    MAX([monthly_charges])                                          AS Max_Monthly_Charges
FROM [silver].[customer];
GO