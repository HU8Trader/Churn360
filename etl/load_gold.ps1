$ErrorActionPreference = 'Stop'

$connectionString = "Server=localhost;Database=Customer_Analysis;Trusted_Connection=true;TrustServerCertificate=true;Connect Timeout=30"

$sql = @"
-- ============ DIMENSIONS ============
IF OBJECT_ID('gold.fact_churn','U') IS NOT NULL DROP TABLE [gold].[fact_churn];
IF OBJECT_ID('gold.fact_customer_service','U') IS NOT NULL DROP TABLE [gold].[fact_customer_service];
IF OBJECT_ID('gold.dim_service','U') IS NOT NULL DROP TABLE [gold].[dim_service];
IF OBJECT_ID('gold.dim_contract','U') IS NOT NULL DROP TABLE [gold].[dim_contract];
IF OBJECT_ID('gold.dim_customer','U') IS NOT NULL DROP TABLE [gold].[dim_customer];

CREATE TABLE [gold].[dim_customer] (
    CustomerKey        int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_customer PRIMARY KEY,
    CustomerID         nvarchar(10) NOT NULL,
    Gender             nvarchar(10) NULL,
    SeniorCitizen      bit          NULL,
    Partner            bit          NULL,
    Dependents         bit          NULL,
    Country            nvarchar(50) NULL,
    State              nvarchar(50) NULL,
    City               nvarchar(100) NULL,
    ZipCode            nvarchar(10) NULL,
    Latitude           decimal(9,6) NULL,
    Longitude          decimal(9,6) NULL
);

CREATE TABLE [gold].[dim_contract] (
    ContractKey        int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_contract PRIMARY KEY,
    ContractType       nvarchar(20) NOT NULL,
    PaperlessBilling   bit          NOT NULL,
    PaymentMethod      nvarchar(30) NOT NULL
);

CREATE TABLE [gold].[dim_service] (
    ServiceKey         int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_service PRIMARY KEY,
    ServiceName        nvarchar(30) NOT NULL,
    ServiceCategory    nvarchar(20) NOT NULL
);

-- ============ FACTS ============
CREATE TABLE [gold].[fact_churn] (
    ChurnKey           bigint       IDENTITY(1,1) NOT NULL CONSTRAINT PK_fact_churn PRIMARY KEY,
    CustomerKey        int          NOT NULL,
    ContractKey        int          NOT NULL,
    TenureMonths       tinyint      NULL,
    MonthlyCharges     decimal(10,2) NULL,
    TotalCharges       decimal(10,2) NULL,
    ChurnScore         smallint     NULL,
    CLTV               int          NULL,
    ChurnValue         tinyint      NULL,
    ChurnLabel         nvarchar(5)  NULL,
    ChurnReason        nvarchar(200) NULL,
    CONSTRAINT FK_fact_churn_customer FOREIGN KEY (CustomerKey) REFERENCES [gold].[dim_customer](CustomerKey),
    CONSTRAINT FK_fact_churn_contract FOREIGN KEY (ContractKey) REFERENCES [gold].[dim_contract](ContractKey)
);

CREATE TABLE [gold].[fact_customer_service] (
    CustomerKey        int          NOT NULL,
    ServiceKey         int          NOT NULL,
    CONSTRAINT PK_fact_customer_service PRIMARY KEY (CustomerKey, ServiceKey),
    CONSTRAINT FK_fcs_customer FOREIGN KEY (CustomerKey) REFERENCES [gold].[dim_customer](CustomerKey),
    CONSTRAINT FK_fcs_service  FOREIGN KEY (ServiceKey)  REFERENCES [gold].[dim_service](ServiceKey)
);

-- ============ LOAD DIMENSIONS ============
INSERT INTO [gold].[dim_customer] (CustomerID, Gender, SeniorCitizen, Partner, Dependents, Country, State, City, ZipCode, Latitude, Longitude)
SELECT DISTINCT
    customer_id, gender, senior_citizen, partner, dependents, country, state, city, zip_code, latitude, longitude
FROM [silver].[customer];

INSERT INTO [gold].[dim_contract] (ContractType, PaperlessBilling, PaymentMethod)
SELECT DISTINCT contract, paperless_billing, payment_method
FROM [silver].[customer];

INSERT INTO [gold].[dim_service] (ServiceName, ServiceCategory)
VALUES
    ('Phone Service',    'Phone'),
    ('Multiple Lines',   'Phone'),
    ('Internet Service', 'Internet'),
    ('Online Security',  'Add-on'),
    ('Online Backup',    'Add-on'),
    ('Device Protection','Add-on'),
    ('Tech Support',     'Add-on'),
    ('Streaming TV',     'Streaming'),
    ('Streaming Movies', 'Streaming');

-- ============ LOAD FACTLESS SERVICE FACT ============
INSERT INTO [gold].[fact_customer_service] (CustomerKey, ServiceKey)
SELECT c.CustomerKey, s.ServiceKey
FROM [silver].[customer] cu
JOIN [gold].[dim_customer] c ON cu.customer_id = c.CustomerID
CROSS APPLY (
    SELECT 'Phone Service' AS SName WHERE cu.phone_service = 1
    UNION ALL SELECT 'Multiple Lines' WHERE cu.multiple_lines = 'Yes'
    UNION ALL SELECT 'Internet Service' WHERE cu.internet_service IN ('DSL','Fiber optic')
    UNION ALL SELECT 'Online Security'  WHERE cu.online_security = 'Yes'
    UNION ALL SELECT 'Online Backup'    WHERE cu.online_backup = 'Yes'
    UNION ALL SELECT 'Device Protection' WHERE cu.device_protection = 'Yes'
    UNION ALL SELECT 'Tech Support'     WHERE cu.tech_support = 'Yes'
    UNION ALL SELECT 'Streaming TV'     WHERE cu.streaming_tv = 'Yes'
    UNION ALL SELECT 'Streaming Movies' WHERE cu.streaming_movies = 'Yes'
) sv
JOIN [gold].[dim_service] s ON sv.SName = s.ServiceName;

-- ============ LOAD FACT CHURN ============
INSERT INTO [gold].[fact_churn] (CustomerKey, ContractKey, TenureMonths, MonthlyCharges, TotalCharges, ChurnScore, CLTV, ChurnValue, ChurnLabel, ChurnReason)
SELECT
    c.CustomerKey,
    ct.ContractKey,
    cu.tenure_months,
    cu.monthly_charges,
    cu.total_charges,
    cu.churn_score,
    cu.cltv,
    cu.churn_value,
    cu.churn_label,
    cu.churn_reason
FROM [silver].[customer] cu
JOIN [gold].[dim_customer] c  ON cu.customer_id = c.CustomerID
JOIN [gold].[dim_contract] ct ON cu.contract = ct.ContractType
                             AND cu.paperless_billing = ct.PaperlessBilling
                             AND cu.payment_method = ct.PaymentMethod;

SELECT 'dim_customer' AS Tbl, COUNT(*) AS Rows FROM [gold].[dim_customer]
UNION ALL SELECT 'dim_contract', COUNT(*) FROM [gold].[dim_contract]
UNION ALL SELECT 'dim_service', COUNT(*) FROM [gold].[dim_service]
UNION ALL SELECT 'fact_customer_service', COUNT(*) FROM [gold].[fact_customer_service]
UNION ALL SELECT 'fact_churn', COUNT(*) FROM [gold].[fact_churn];
"@

Write-Host "Building gold star schema..."
$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = $sql
$r = $cmd.ExecuteReader()
while ($r.Read()) { Write-Output "$($r['Tbl']): $($r['Rows']) rows" }
$r.Close()
$conn.Close()
Write-Host "Done."