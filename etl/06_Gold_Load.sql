/*============================================================================
  FILE     : 06_Gold_Load.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Populates the gold star schema from silver.customer.

  LOAD SEQUENCE (order matters)
  -----------------------------
  1. Clear facts first, then dimensions (respects foreign keys).
  2. Load dimensions (they generate the surrogate identity keys).
  3. Load facts by joining back to dimensions on the natural keys.

  USAGE
  -----
  Run after 05_Silver_Load.sql. Safe to re-run (clears and reloads).

  RUN ORDER
  ---------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql
    3. 02_Bronze_Create.sql
    4. 03_Silver_Create.sql
    5. 04_Gold_Create.sql
    6. 05_Silver_Load.sql
    7. 06_Gold_Load.sql   <-- THIS FILE

  EXPECTED RESULT
  ---------------
    dim_customer          7,043 rows
    dim_contract             24 rows
    dim_service               9 rows
    fact_customer_service 29,202 rows
    fact_churn            7,043 rows
============================================================================*/

USE [Customer_Analysis];
GO

/* ---------------------------------------------------------------------------
   STEP 1 : CLEAR - facts first, then dimensions (FK-safe order)
   ------------------------------------------------------------------------- */
DELETE FROM [gold].[fact_customer_service];
DELETE FROM [gold].[fact_churn];
DELETE FROM [gold].[dim_customer];
DELETE FROM [gold].[dim_contract];
DELETE FROM [gold].[dim_service];
GO

/* ---------------------------------------------------------------------------
   STEP 2 : LOAD DIMENSIONS
   ------------------------------------------------------------------------- */

-- 2.1 dim_customer : one row per distinct customer identity/geography
INSERT INTO [gold].[dim_customer]
(
    [CustomerID], [Gender], [SeniorCitizen], [Partner], [Dependents],
    [Country], [State], [City], [ZipCode], [Latitude], [Longitude]
)
SELECT DISTINCT
    [customer_id],
    [gender],
    [senior_citizen],
    [partner],
    [dependents],
    [country],
    [state],
    [city],
    [zip_code],
    [latitude],
    [longitude]
FROM [silver].[customer];
GO

-- 2.2 dim_contract : distinct contract combinations
INSERT INTO [gold].[dim_contract] ([ContractType], [PaperlessBilling], [PaymentMethod])
SELECT DISTINCT [contract], [paperless_billing], [payment_method]
FROM [silver].[customer];
GO

-- 2.3 dim_service : static catalog
INSERT INTO [gold].[dim_service] ([ServiceName], [ServiceCategory])
VALUES
    ('Phone Service',     'Phone'),
    ('Multiple Lines',    'Phone'),
    ('Internet Service',  'Internet'),
    ('Online Security',   'Add-on'),
    ('Online Backup',     'Add-on'),
    ('Device Protection', 'Add-on'),
    ('Tech Support',      'Add-on'),
    ('Streaming TV',      'Streaming'),
    ('Streaming Movies',  'Streaming');
GO

/* ---------------------------------------------------------------------------
   STEP 3 : LOAD FACTS
   ------------------------------------------------------------------------- */

-- 3.1 fact_customer_service (factless) : only services the customer actually
--     has. 'No' / 'No internet service' / 'No phone service' are excluded.
--     CROSS APPLY explodes the service flags into rows.
INSERT INTO [gold].[fact_customer_service] ([CustomerKey], [ServiceKey])
SELECT c.[CustomerKey], s.[ServiceKey]
FROM [silver].[customer] cu
JOIN [gold].[dim_customer] c ON cu.[customer_id] = c.[CustomerID]
CROSS APPLY
(
    SELECT 'Phone Service'      AS SName WHERE cu.[phone_service]     = 1
    UNION ALL SELECT 'Multiple Lines'    WHERE cu.[multiple_lines]    = 'Yes'
    UNION ALL SELECT 'Internet Service'  WHERE cu.[internet_service]  IN ('DSL','Fiber optic')
    UNION ALL SELECT 'Online Security'   WHERE cu.[online_security]   = 'Yes'
    UNION ALL SELECT 'Online Backup'     WHERE cu.[online_backup]     = 'Yes'
    UNION ALL SELECT 'Device Protection' WHERE cu.[device_protection] = 'Yes'
    UNION ALL SELECT 'Tech Support'      WHERE cu.[tech_support]      = 'Yes'
    UNION ALL SELECT 'Streaming TV'      WHERE cu.[streaming_tv]      = 'Yes'
    UNION ALL SELECT 'Streaming Movies'  WHERE cu.[streaming_movies]  = 'Yes'
) sv
JOIN [gold].[dim_service] s ON sv.SName = s.[ServiceName];
GO

-- 3.2 fact_churn : subscription snapshot per customer
INSERT INTO [gold].[fact_churn]
(
    [CustomerKey], [ContractKey], [TenureMonths], [MonthlyCharges],
    [TotalCharges], [ChurnScore], [CLTV], [ChurnValue], [ChurnLabel], [ChurnReason]
)
SELECT
    c.[CustomerKey],
    ct.[ContractKey],
    cu.[tenure_months],
    cu.[monthly_charges],
    cu.[total_charges],
    cu.[churn_score],
    cu.[cltv],
    cu.[churn_value],
    cu.[churn_label],
    cu.[churn_reason]
FROM [silver].[customer] cu
JOIN [gold].[dim_customer] c  ON cu.[customer_id] = c.[CustomerID]
JOIN [gold].[dim_contract] ct ON cu.[contract]          = ct.[ContractType]
                             AND cu.[paperless_billing] = ct.[PaperlessBilling]
                             AND cu.[payment_method]    = ct.[PaymentMethod];
GO

/* ---------------------------------------------------------------------------
   STEP 4 : VALIDATION
   ------------------------------------------------------------------------- */
SELECT
    (SELECT COUNT(*) FROM [gold].[dim_customer])            AS Dim_Customer_Rows,
    (SELECT COUNT(*) FROM [gold].[dim_contract])            AS Dim_Contract_Rows,
    (SELECT COUNT(*) FROM [gold].[dim_service])             AS Dim_Service_Rows,
    (SELECT COUNT(*) FROM [gold].[fact_customer_service])   AS Fact_Customer_Service_Rows,
    (SELECT COUNT(*) FROM [gold].[fact_churn])              AS Fact_Churn_Rows;
GO

-- Churn KPI sanity check (overall churn rate should be ~26.5%).
SELECT
    COUNT(*)                                              AS Total_Customers,
    SUM(CASE WHEN [ChurnLabel] = 'Yes' THEN 1 ELSE 0 END)  AS Churned_Customers,
    CAST(100.0 * SUM(CASE WHEN [ChurnLabel] = 'Yes' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,1))            AS Churn_Rate_Pct
FROM [gold].[fact_churn];
GO

/*============================================================================
  END OF MEDALLION BUILD
  Next step: connect Power BI to gold.fact_churn + gold dimensions.
============================================================================*/