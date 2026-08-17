/*============================================================================
  PROJECT  : Customer 360 - Churn Analytics
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)
  VERSION  : 1.0

  DESCRIPTION
  -----------
  Builds the full Medallion (Multi-hop) data architecture for the
  Telco customer churn analytics solution:

        bronze  (raw landing)      ->  silver (cleansed / conformed)
                                    ->  gold   (star schema for reporting)

  DATA SOURCE
  -----------
  File      : Telco_customer_churn.xlsx  (sheet: Telco_Churn)
  Volume    : 7,043 customer records, 33 source columns
  Domain    : US telco customers (California) with churn outcome.

  ARCHITECTURE (Medallion)
  ------------------------
    +-----------+   +----------------------+   +-------------------------+
    |  bronze   |   |   silver             |   |  gold (star schema)     |
    |  raw      |-> |   typed / cleansed   |-> |  dim_* / fact_*         |
    |  nvarchar |   |   dwh_create_date    |   |  surrogate keys, FK     |
    +-----------+   +----------------------+   +-------------------------+

  GOLD STAR SCHEMA
  ----------------
    dim_customer   (1) ----< fact_churn >---- (1) dim_contract
    dim_customer   (1) ----< fact_customer_service >---- (1) dim_service

    fact_churn              : point-in-time subscription snapshot + churn outcome
    fact_customer_service   : FACTLESS fact table -> service subscription matrix

  NOTES / CONVENTIONS
  -------------------
  * bronze  = raw landing layer; every column kept as nvarchar (as-is).
  * silver  = conformed layer; proper data types, NULL handling, audit column.
  * gold    = presentation layer; PascalCase columns, int/bigint identity keys.
  * All scripts are IDEMPOTENT (safe to re-run).
  * This script assumes bronze data is already staged. If bronze is empty,
    load the source Excel first via etl\load_bronze.ps1.

============================================================================*/


/*============================================================================
  SECTION 0 : USE DATABASE + SCHEMA CREATION
  The three medallion schemas are created if they do not already exist.
============================================================================*/
USE [Customer_Analysis];
GO

IF SCHEMA_ID('bronze') IS NULL
    EXEC('CREATE SCHEMA [bronze] AUTHORIZATION dbo');
IF SCHEMA_ID('silver') IS NULL
    EXEC('CREATE SCHEMA [silver] AUTHORIZATION dbo');
IF SCHEMA_ID('gold')   IS NULL
    EXEC('CREATE SCHEMA [gold]   AUTHORIZATION dbo');
GO


/*============================================================================
  SECTION 1 : BRONZE (RAW LANDING LAYER)

  PURPOSE   : Exact copy of the source workbook, one column per source field,
              all stored as nvarchar to preserve raw values. No business logic
              is applied here. Downstream consumers should never query bronze
              for analysis - it exists only to retain the raw record.

  LOAD      : The source Excel is ingested by etl\load_bronze.ps1
              (PowerShell + SqlBulkCopy). Table is dropped & recreated on each
              load so it is fully idempotent.

  DATA QA   : 7,043 rows expected. 11 records have blank Total Charges
              (new customers, tenure = 0). 5,174 records have a blank
              Churn Reason (these are non-churners).
============================================================================*/
IF OBJECT_ID('bronze.telco_customer_churn','U') IS NOT NULL
    DROP TABLE [bronze].[telco_customer_churn];

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
    [churn_reason]           nvarchar(100) NULL    -- stated churn reason (NULL for active)
);
GO


/*============================================================================
  SECTION 2 : SILVER (CLEANSED / CONFORMED LAYER)

  PURPOSE   : One clean, typed record per customer. All the raw nvarchar
              values are converted to the correct data types, Yes/No flags
              become bit columns, blank values become NULL, and an audit
              column (dwh_create_date) is added.

  CLEANSING RULES
  ----------------
  1. Trim      : LTRIM/RTRIM applied to every character column.
  2. Booleans  : Yes -> 1, No -> 0  (senior_citizen, partner, dependents,
                 phone_service, paperless_billing).
  3. Numerics  : TRY_CONVERT to decimal/smallint/int so bad values become
                 NULL instead of failing the load.
  4. Nulls     : Blank Total Charges -> NULL (new customer).
                 Blank Churn Reason  -> NULL (non-churner).
============================================================================*/
IF OBJECT_ID('silver.customer','U') IS NOT NULL
    DROP TABLE [silver].[customer];

CREATE TABLE [silver].[customer]
(
    [customer_id]        nvarchar(10)    NOT NULL,   -- unique customer identifier (PK candidate)
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
    [total_charges]      decimal(10,2)   NULL,       -- lifetime billed amount (NULL for new customers)
    [churn_label]        nvarchar(5)     NULL,       -- Yes = churned / No = active
    [churn_value]        tinyint         NULL,       -- 1 = churned / 0 = active
    [churn_score]        smallint        NULL,       -- 0-100 churn likelihood
    [cltv]               int             NULL,       -- customer lifetime value
    [churn_reason]       nvarchar(200)   NULL,       -- stated churn reason (NULL = active)
    [dwh_create_date]    datetime2       NOT NULL
        CONSTRAINT DF_customer_dwh_create_date DEFAULT (SYSDATETIME())   -- audit timestamp
);
GO

-- Populate silver from bronze (idempotent: load when empty).
IF NOT EXISTS (SELECT 1 FROM [silver].[customer])
BEGIN
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
END;
GO


/*============================================================================
  SECTION 3 : GOLD (STAR SCHEMA - REPORTING / SEMANTIC LAYER)

  DESIGN
  ------
  Conformed star schema consumed directly by Power BI / Excel / SSRS.

      dim_customer        -- demographics + geography surrogate
      dim_contract        -- contract type x billing x payment method
      dim_service         -- service catalog (9 services)
      fact_churn          -- subscription snapshot + churn outcome (grained per customer)
      fact_customer_service -- FACTLESS FACT: customer x service subscription matrix

  KEYS
  ----
  * Dimensions: int IDENTITY surrogate keys (CustomerKey, ContractKey, ServiceKey)
  * Fact       : bigint IDENTITY surrogate keys (ChurnKey)
  * Business key in dim_customer : CustomerID (natural key)

  WHY A FACTLESS FACT?
  --------------------
  Services are 'many-to-many' with customers. Rather than stuffing 9 flag
  columns into the fact (wide & hard to pivot), each service a customer has
  becomes one row. This supports counts such as "how many customers have
  Tech Support", and "which service mix correlates with churn".
============================================================================*/

/* ---- 3.1 Drop in dependency-safe order (facts before dimensions) ---- */
IF OBJECT_ID('gold.fact_churn','U')            IS NOT NULL DROP TABLE [gold].[fact_churn];
IF OBJECT_ID('gold.fact_customer_service','U') IS NOT NULL DROP TABLE [gold].[fact_customer_service];
IF OBJECT_ID('gold.dim_service','U')           IS NOT NULL DROP TABLE [gold].[dim_service];
IF OBJECT_ID('gold.dim_contract','U')          IS NOT NULL DROP TABLE [gold].[dim_contract];
IF OBJECT_ID('gold.dim_customer','U')          IS NOT NULL DROP TABLE [gold].[dim_customer];
GO

/* ---- 3.2 Dimension : customer ---- */
CREATE TABLE [gold].[dim_customer]
(
    [CustomerKey]        int           IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_dim_customer PRIMARY KEY,      -- surrogate key
    [CustomerID]         nvarchar(10)  NOT NULL,     -- natural business key
    [Gender]             nvarchar(10)  NULL,         -- Male / Female
    [SeniorCitizen]      bit           NULL,         -- 1 = senior citizen
    [Partner]            bit           NULL,         -- 1 = has partner
    [Dependents]         bit           NULL,         -- 1 = has dependents
    [Country]            nvarchar(50)  NULL,         -- country
    [State]              nvarchar(50)  NULL,         -- state
    [City]               nvarchar(100) NULL,         -- city
    [ZipCode]            nvarchar(10)  NULL,         -- postal code
    [Latitude]           decimal(9,6)  NULL,         -- latitude
    [Longitude]          decimal(9,6)  NULL          -- longitude
);
GO

/* ---- 3.3 Dimension : contract (SCD-like reference data) ---- */
CREATE TABLE [gold].[dim_contract]
(
    [ContractKey]       int           IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_dim_contract PRIMARY KEY,      -- surrogate key
    [ContractType]      nvarchar(20)  NOT NULL,      -- Month-to-month / One year / Two year
    [PaperlessBilling]  bit           NOT NULL,      -- 1 = paperless billing
    [PaymentMethod]     nvarchar(30)  NOT NULL       -- payment method
);
GO

/* ---- 3.4 Dimension : service catalog (9 static rows) ---- */
CREATE TABLE [gold].[dim_service]
(
    [ServiceKey]       int           IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_dim_service PRIMARY KEY,       -- surrogate key
    [ServiceName]      nvarchar(30)  NOT NULL,       -- e.g. 'Tech Support'
    [ServiceCategory]  nvarchar(20)  NOT NULL        -- Phone / Internet / Add-on / Streaming
);
GO

/* ---- 3.5 Fact : churn snapshot (one row per customer) ---- */
CREATE TABLE [gold].[fact_churn]
(
    [ChurnKey]         bigint        IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_fact_churn PRIMARY KEY,        -- surrogate key
    [CustomerKey]      int           NOT NULL,       -- FK -> dim_customer
    [ContractKey]      int           NOT NULL,       -- FK -> dim_contract
    [TenureMonths]     tinyint       NULL,           -- months as subscriber
    [MonthlyCharges]   decimal(10,2) NULL,           -- monthly billing
    [TotalCharges]     decimal(10,2) NULL,           -- lifetime billing (NULL = new customer)
    [ChurnScore]       smallint      NULL,           -- 0-100 churn likelihood
    [CLTV]             int           NULL,           -- customer lifetime value
    [ChurnValue]       tinyint       NULL,           -- 1 = churned / 0 = active
    [ChurnLabel]       nvarchar(5)   NULL,           -- Yes / No
    [ChurnReason]      nvarchar(200) NULL,           -- stated reason (NULL = active)
    CONSTRAINT FK_fact_churn_customer FOREIGN KEY ([CustomerKey])
        REFERENCES [gold].[dim_customer] ([CustomerKey]),
    CONSTRAINT FK_fact_churn_contract FOREIGN KEY ([ContractKey])
        REFERENCES [gold].[dim_contract] ([ContractKey])
);
GO

/* ---- 3.6 Factless fact : customer x service subscription ---- */
CREATE TABLE [gold].[fact_customer_service]
(
    [CustomerKey]  int  NOT NULL,                    -- FK -> dim_customer
    [ServiceKey]   int  NOT NULL,                    -- FK -> dim_service
    CONSTRAINT PK_fact_customer_service PRIMARY KEY ([CustomerKey], [ServiceKey]),
    CONSTRAINT FK_fcs_customer FOREIGN KEY ([CustomerKey])
        REFERENCES [gold].[dim_customer] ([CustomerKey]),
    CONSTRAINT FK_fcs_service FOREIGN KEY ([ServiceKey])
        REFERENCES [gold].[dim_service] ([ServiceKey])
);
GO


/*============================================================================
  SECTION 4 : GOLD - POPULATION
  Dimensions are populated first (they generate the surrogate keys), then the
  facts reference those keys via JOINs on the natural keys.
============================================================================*/

-- 4.1 dim_customer : one row per distinct customer identity/geography
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

-- 4.2 dim_contract : distinct contract combinations
INSERT INTO [gold].[dim_contract] ([ContractType], [PaperlessBilling], [PaymentMethod])
SELECT DISTINCT [contract], [paperless_billing], [payment_method]
FROM [silver].[customer];
GO

-- 4.3 dim_service : static catalog
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

-- 4.4 fact_customer_service (factless) : only services the customer actually has.
--     'No' and 'No internet service' / 'No phone service' are excluded.
--     Uses CROSS APPLY to explode the service flags into rows.
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

-- 4.5 fact_churn : subscription snapshot per customer
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


/*============================================================================
  SECTION 5 : VALIDATION (run these to confirm the build)

  Expected results:
    dim_customer          7,043 rows
    dim_contract             24 rows
    dim_service               9 rows
    fact_customer_service 29,202 rows
    fact_churn            7,043 rows
============================================================================*/
SELECT 'bronze.telco_customer_churn'  AS Layer_Table, COUNT(*) AS Row_Count FROM [bronze].[telco_customer_churn]
UNION ALL SELECT 'silver.customer',              COUNT(*) FROM [silver].[customer]
UNION ALL SELECT 'gold.dim_customer',            COUNT(*) FROM [gold].[dim_customer]
UNION ALL SELECT 'gold.dim_contract',            COUNT(*) FROM [gold].[dim_contract]
UNION ALL SELECT 'gold.dim_service',             COUNT(*) FROM [gold].[dim_service]
UNION ALL SELECT 'gold.fact_customer_service',   COUNT(*) FROM [gold].[fact_customer_service]
UNION ALL SELECT 'gold.fact_churn',              COUNT(*) FROM [gold].[fact_churn];
GO

-- Churn KPI sanity check: overall churn rate should be 26.5%
SELECT
    COUNT(*)                                             AS Total_Customers,
    SUM(CASE WHEN [ChurnLabel] = 'Yes' THEN 1 ELSE 0 END) AS Churned_Customers,
    CAST(100.0 * SUM(CASE WHEN [ChurnLabel] = 'Yes' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*),0) AS DECIMAL(5,1))            AS Churn_Rate_Pct
FROM [gold].[fact_churn];
GO

/*============================================================================
  END OF SCRIPT
  Next step: connect Power BI to gold.fact_churn + gold dimensions and build
  the reporting layer (see project plan for the 12 visual deliverables).
============================================================================*/