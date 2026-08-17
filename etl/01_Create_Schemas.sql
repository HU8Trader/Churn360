/*============================================================================
  FILE     : 01_Create_Schemas.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Creates the three Medallion architecture schemas:

        bronze   -> raw landing layer
        silver   -> cleansed / conformed layer
        gold     -> star schema (reporting) layer

  USAGE
  -----
  Run after 00_Create_Database.sql. Safe to re-run (idempotent).

  RUN ORDER
  ---------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql   <-- THIS FILE
    3. 02_Bronze_Create.sql
    4. 03_Silver_Create.sql
    5. 04_Gold_Create.sql
    6. 05_Silver_Load.sql
    7. 06_Gold_Load.sql
============================================================================*/

USE [Customer_Analysis];
GO

-- bronze : raw landing layer (source-as-is, all nvarchar)
IF SCHEMA_ID(N'bronze') IS NULL
    EXEC(N'CREATE SCHEMA [bronze] AUTHORIZATION dbo');

-- silver : cleansed / conformed layer (typed, audited)
IF SCHEMA_ID(N'silver') IS NULL
    EXEC(N'CREATE SCHEMA [silver] AUTHORIZATION dbo');

-- gold   : star schema presentation layer
IF SCHEMA_ID(N'gold') IS NULL
    EXEC(N'CREATE SCHEMA [gold] AUTHORIZATION dbo');
GO

-- Confirm the schemas exist.
SELECT name AS Schema_Name, schema_id
FROM sys.schemas
WHERE name IN (N'bronze', N'silver', N'gold');
GO