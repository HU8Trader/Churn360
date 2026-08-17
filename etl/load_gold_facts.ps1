$ErrorActionPreference = 'Stop'

$connectionString = "Server=localhost;Database=Customer_Analysis;Trusted_Connection=true;TrustServerCertificate=true;Connect Timeout=30"

$factService = @"
DELETE FROM [gold].[fact_customer_service];
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
"@

$factChurn = @"
DELETE FROM [gold].[fact_churn];
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
"@

$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 300

$cmd.CommandText = $factService
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "fact_customer_service loaded"

$cmd.CommandText = $factChurn
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "fact_churn loaded"

$cmd.CommandText = "SELECT 'fact_customer_service' AS Tbl, COUNT(*) AS Rows FROM [gold].[fact_customer_service] UNION ALL SELECT 'fact_churn', COUNT(*) FROM [gold].[fact_churn]"
$r = $cmd.ExecuteReader()
while ($r.Read()) { Write-Output "$($r['Tbl']): $($r['Rows'])" }
$r.Close()
$conn.Close()
Write-Host "Done."