/*============================================================================
  FILE     : 04_Gold_Create.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Creates the gold star-schema tables used directly by Power BI / Excel /
  SSRS reporting.

  STAR SCHEMA DESIGN
  ------------------
        dim_customer   (1) ----< fact_churn >---- (1) dim_contract
        dim_customer   (1) ----< fact_customer_service >---- (1) dim_service

  * dim_customer            : demographics + geography (surrogate CustomerKey)
  * dim_contract            : contract type x billing x payment method
  * dim_service             : service catalog (9 services)
  * fact_churn              : subscription snapshot + churn outcome (per customer)
  * fact_customer_service   : FACTLESS FACT - customer x service subscription matrix

  KEYS
  ----
  * Dimensions : int IDENTITY surrogate keys
  * Facts      : bigint IDENTITY surrogate keys
  * Natural key in dim_customer : CustomerID

  WHY A FACTLESS FACT?
  --------------------
  Services are many-to-many with customers. Each service a customer has is
  stored as one row, enabling counts like "customers with Tech Support" and
  service-mix vs churn analysis without wide flag columns.

  USAGE
  -----
  Run after 03_Silver_Create.sql. Safe to re-run (idempotent).
  Data is loaded later by 06_Gold_Load.sql.

  RUN ORDER
  ---------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql
    3. 02_Bronze_Create.sql
    4. 03_Silver_Create.sql
    5. 04_Gold_Create.sql      <-- THIS FILE
    6. 05_Silver_Load.sql
    7. 06_Gold_Load.sql
============================================================================*/

USE [Customer_Analysis];
GO

/* ---------------------------------------------------------------------------
   4.1 Drop tables in dependency-safe order (facts before dimensions)
   ------------------------------------------------------------------------- */
IF OBJECT_ID(N'gold.fact_churn', N'U')            IS NOT NULL DROP TABLE [gold].[fact_churn];
IF OBJECT_ID(N'gold.fact_customer_service', N'U') IS NOT NULL DROP TABLE [gold].[fact_customer_service];
IF OBJECT_ID(N'gold.dim_service', N'U')           IS NOT NULL DROP TABLE [gold].[dim_service];
IF OBJECT_ID(N'gold.dim_contract', N'U')          IS NOT NULL DROP TABLE [gold].[dim_contract];
IF OBJECT_ID(N'gold.dim_customer', N'U')          IS NOT NULL DROP TABLE [gold].[dim_customer];
GO

/* ---------------------------------------------------------------------------
   4.2 Dimension : customer
   ------------------------------------------------------------------------- */
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

/* ---------------------------------------------------------------------------
   4.3 Dimension : contract (reference data)
   ------------------------------------------------------------------------- */
CREATE TABLE [gold].[dim_contract]
(
    [ContractKey]       int           IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_dim_contract PRIMARY KEY,      -- surrogate key
    [ContractType]      nvarchar(20)  NOT NULL,      -- Month-to-month / One year / Two year
    [PaperlessBilling]  bit           NOT NULL,      -- 1 = paperless billing
    [PaymentMethod]     nvarchar(30)  NOT NULL       -- payment method
);
GO

/* ---------------------------------------------------------------------------
   4.4 Dimension : service catalog (9 static rows)
   ------------------------------------------------------------------------- */
CREATE TABLE [gold].[dim_service]
(
    [ServiceKey]       int           IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_dim_service PRIMARY KEY,       -- surrogate key
    [ServiceName]      nvarchar(30)  NOT NULL,       -- e.g. 'Tech Support'
    [ServiceCategory]  nvarchar(20)  NOT NULL        -- Phone / Internet / Add-on / Streaming
);
GO

/* ---------------------------------------------------------------------------
   4.5 Fact : churn snapshot (one row per customer)
   ------------------------------------------------------------------------- */
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

/* ---------------------------------------------------------------------------
   4.6 Factless fact : customer x service subscription
   ------------------------------------------------------------------------- */
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

-- Confirm all gold tables exist (expect 0 rows until 06_Gold_Load.sql runs).
SELECT
    (SELECT COUNT(*) FROM [gold].[dim_customer])            AS Dim_Customer,
    (SELECT COUNT(*) FROM [gold].[dim_contract])            AS Dim_Contract,
    (SELECT COUNT(*) FROM [gold].[dim_service])             AS Dim_Service,
    (SELECT COUNT(*) FROM [gold].[fact_churn])              AS Fact_Churn,
    (SELECT COUNT(*) FROM [gold].[fact_customer_service])   AS Fact_Customer_Service;
GO