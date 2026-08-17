$ErrorActionPreference = 'Stop'

$connectionString = "Server=localhost;Database=Customer_Analysis;Trusted_Connection=true;TrustServerCertificate=true;Connect Timeout=30"

$sql = @"
IF OBJECT_ID('silver.customer','U') IS NOT NULL DROP TABLE [silver].[customer];
CREATE TABLE [silver].[customer] (
    customer_id        nvarchar(10)   NOT NULL,
    [count]            smallint       NULL,
    country            nvarchar(50)   NULL,
    state              nvarchar(50)   NULL,
    city               nvarchar(100)  NULL,
    zip_code           nvarchar(10)   NULL,
    lat_long           nvarchar(50)   NULL,
    latitude           decimal(9,6)   NULL,
    longitude          decimal(9,6)   NULL,
    gender             nvarchar(10)   NULL,
    senior_citizen     bit            NULL,
    partner            bit            NULL,
    dependents         bit            NULL,
    tenure_months      tinyint        NULL,
    phone_service      bit            NULL,
    multiple_lines     nvarchar(20)   NULL,
    internet_service   nvarchar(20)   NULL,
    online_security    nvarchar(20)   NULL,
    online_backup      nvarchar(20)   NULL,
    device_protection  nvarchar(20)   NULL,
    tech_support       nvarchar(20)   NULL,
    streaming_tv       nvarchar(20)   NULL,
    streaming_movies   nvarchar(20)   NULL,
    contract           nvarchar(20)   NULL,
    paperless_billing  bit            NULL,
    payment_method     nvarchar(30)   NULL,
    monthly_charges    decimal(10,2)  NULL,
    total_charges      decimal(10,2)  NULL,
    churn_label        nvarchar(5)    NULL,
    churn_value        tinyint        NULL,
    churn_score        smallint       NULL,
    cltv               int            NULL,
    churn_reason       nvarchar(200)  NULL,
    dwh_create_date    datetime2      NOT NULL CONSTRAINT DF_customer_dwh_create_date DEFAULT (SYSDATETIME())
);

INSERT INTO [silver].[customer] (
    customer_id, [count], country, state, city, zip_code, lat_long, latitude, longitude,
    gender, senior_citizen, partner, dependents, tenure_months, phone_service, multiple_lines,
    internet_service, online_security, online_backup, device_protection, tech_support,
    streaming_tv, streaming_movies, contract, paperless_billing, payment_method,
    monthly_charges, total_charges, churn_label, churn_value, churn_score, cltv, churn_reason, dwh_create_date
)
SELECT
    LTRIM(RTRIM(customer_id)),
    TRY_CONVERT(smallint, [count]),
    LTRIM(RTRIM(country)),
    LTRIM(RTRIM(state)),
    LTRIM(RTRIM(city)),
    LTRIM(RTRIM(zip_code)),
    LTRIM(RTRIM(lat_long)),
    TRY_CONVERT(decimal(9,6), latitude),
    TRY_CONVERT(decimal(9,6), longitude),
    LTRIM(RTRIM(gender)),
    CASE WHEN senior_citizen = 'Yes' THEN 1 WHEN senior_citizen = 'No' THEN 0 END,
    CASE WHEN partner = 'Yes' THEN 1 WHEN partner = 'No' THEN 0 END,
    CASE WHEN dependents = 'Yes' THEN 1 WHEN dependents = 'No' THEN 0 END,
    TRY_CONVERT(tinyint, tenure_months),
    CASE WHEN phone_service = 'Yes' THEN 1 WHEN phone_service = 'No' THEN 0 END,
    LTRIM(RTRIM(multiple_lines)),
    LTRIM(RTRIM(internet_service)),
    LTRIM(RTRIM(online_security)),
    LTRIM(RTRIM(online_backup)),
    LTRIM(RTRIM(device_protection)),
    LTRIM(RTRIM(tech_support)),
    LTRIM(RTRIM(streaming_tv)),
    LTRIM(RTRIM(streaming_movies)),
    LTRIM(RTRIM(contract)),
    CASE WHEN paperless_billing = 'Yes' THEN 1 WHEN paperless_billing = 'No' THEN 0 END,
    LTRIM(RTRIM(payment_method)),
    TRY_CONVERT(decimal(10,2), monthly_charges),
    CASE WHEN total_charges = '' THEN NULL ELSE TRY_CONVERT(decimal(10,2), total_charges) END,
    LTRIM(RTRIM(churn_label)),
    TRY_CONVERT(tinyint, churn_value),
    TRY_CONVERT(smallint, churn_score),
    TRY_CONVERT(int, cltv),
    NULLIF(LTRIM(RTRIM(churn_reason)), ''),
    SYSDATETIME()
FROM [bronze].[telco_customer_churn];

SELECT COUNT(*) AS TotalRows FROM [silver].[customer];
"@

Write-Host "Building silver layer..."
$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = $sql
$cmd.ExecuteNonQuery() | Out-Null
$conn.Close()
Write-Host "Done."