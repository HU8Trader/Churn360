/*============================================================================
  FILE     : 00_Create_Database.sql
  PROJECT  : Customer 360 - Churn Analytics (Telco)
  DATABASE : Customer_Analysis
  AUTHOR   : Himanshu Upadhyay (HiLyst)

  PURPOSE
  -------
  Creates the target data warehouse database (if it does not already exist)
  and switches context to it.

  USAGE
  -----
  Run this script FIRST. All downstream scripts assume this database exists
  and connect to it via the USE statement in each file.

  RUN ORDER (medallion build)
  ----------------------------
    1. 00_Create_Database.sql
    2. 01_Create_Schemas.sql
    3. 02_Bronze_Create.sql
    4. 03_Silver_Create.sql
    5. 04_Gold_Create.sql
    6. 05_Silver_Load.sql
    7. 06_Gold_Load.sql
============================================================================*/

-- Create the database only if it does not already exist.
IF DB_ID(N'Customer_Analysis') IS NULL
    CREATE DATABASE [Customer_Analysis];
GO

-- Switch context to the data warehouse.
USE [Customer_Analysis];
GO

-- Confirm the database is available.
SELECT DB_NAME() AS Current_Database;
GO