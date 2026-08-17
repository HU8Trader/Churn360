$ErrorActionPreference = 'Stop'

$connectionString = "Server=localhost;Database=Customer_Analysis;Trusted_Connection=true;TrustServerCertificate=true;Connect Timeout=30"
$outFile = "C:\Users\pc\Documents\HiLyst DataSets\customer 360 curn analysis\dashboard\data.js"

New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null

$sql = @"
SELECT
    customer_id                       AS id,
    gender                            AS gender,
    senior_citizen                    AS senior,
    partner                           AS partner,
    dependents                        AS dep,
    tenure_months                     AS tenure,
    phone_service                     AS phone,
    multiple_lines                    AS mlines,
    internet_service                  AS internet,
    online_security                   AS osec,
    online_backup                     AS oback,
    device_protection                 AS dprot,
    tech_support                      AS tech,
    streaming_tv                      AS stv,
    streaming_movies                  AS smov,
    contract                          AS contract,
    paperless_billing                 AS paper,
    payment_method                    AS pay,
    monthly_charges                   AS monthly,
    total_charges                     AS total,
    churn_label                       AS churn,
    churn_value                       AS churnv,
    churn_score                       AS score,
    cltv                              AS cltv,
    churn_reason                      AS reason,
    city                              AS city,
    zip_code                          AS zip,
    state                             AS state,
    country                           AS country,
    latitude                          AS lat,
    longitude                         AS lng
FROM [silver].[customer]
"@

$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 120
$cmd.CommandText = $sql
$reader = $cmd.ExecuteReader()

function IsDbNull($v) {
    return ($null -eq $v) -or ([System.DBNull]::Value.Equals($v))
}

function Esc($s) {
    if (IsDbNull $s) { return 'null' }
    $t = $s.ToString()
    $t = $t.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", ' ').Replace("`t", ' ')
    return '"' + $t + '"'
}

function Num($v) {
    if (IsDbNull $v) { return 'null' }
    return $v.ToString()
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('// Auto-generated from Customer_Analysis.silver.customer - do not edit manually.')
[void]$sb.AppendLine('var CHURN_DATA = [')

$count = 0
while ($reader.Read()) {
    $vals = @()
    $vals += "id:`"$($reader['id'])`""
    $vals += "gender:$(Esc $reader['gender'])"
    $vals += "senior:$(if($reader['senior']) {1} else {0})"
    $vals += "partner:$(if($reader['partner']) {1} else {0})"
    $vals += "dep:$(if($reader['dep']) {1} else {0})"
    $vals += "tenure:$($reader['tenure'])"
    $vals += "phone:$(if($reader['phone']) {1} else {0})"
    $vals += "mlines:$(Esc $reader['mlines'])"
    $vals += "internet:$(Esc $reader['internet'])"
    $vals += "osec:$(Esc $reader['osec'])"
    $vals += "oback:$(Esc $reader['oback'])"
    $vals += "dprot:$(Esc $reader['dprot'])"
    $vals += "tech:$(Esc $reader['tech'])"
    $vals += "stv:$(Esc $reader['stv'])"
    $vals += "smov:$(Esc $reader['smov'])"
    $vals += "contract:$(Esc $reader['contract'])"
    $vals += "paper:$(if($reader['paper']) {1} else {0})"
    $vals += "pay:$(Esc $reader['pay'])"
    $vals += "monthly:$(Num $reader['monthly'])"
    $vals += "total:$(Num $reader['total'])"
    $vals += "churn:$(Esc $reader['churn'])"
    $vals += "churnv:$(Num $reader['churnv'])"
    $vals += "score:$(Num $reader['score'])"
    $vals += "cltv:$(Num $reader['cltv'])"
    $vals += "reason:$(Esc $reader['reason'])"
    $vals += "city:$(Esc $reader['city'])"
    $vals += "zip:$(Esc $reader['zip'])"
    $vals += "state:$(Esc $reader['state'])"
    $vals += "country:$(Esc $reader['country'])"
    $vals += "lat:$(Num $reader['lat'])"
    $vals += "lng:$(Num $reader['lng'])"
    [void]$sb.AppendLine('  {' + ($vals -join ', ') + '},')
    $count++
}
$reader.Close()
$conn.Close()

[void]$sb.AppendLine('];')
[void]$sb.AppendLine('window.CHURN_DATA = CHURN_DATA;')
[void]$sb.AppendLine("window.__CHURN_ROWS__ = $count;")

[System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Exported $count rows -> $outFile"
Write-Output "File size: $((Get-Item $outFile).Length) bytes"