$ErrorActionPreference = 'Stop'

$connectionString = "Server=localhost;Database=Customer_Analysis;Trusted_Connection=true;TrustServerCertificate=true;Connect Timeout=30"
$sourceFile = "C:\Users\pc\Documents\HiLyst DataSets\customer 360 curn analysis\Telco_customer_churn.xlsx"
$targetSchema = "bronze"
$targetTable = "telco_customer_churn"

Write-Host "Reading Excel file: $sourceFile"
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
    $wb = $excel.Workbooks.Open($sourceFile, $null, $true)
    $ws = $wb.Worksheets.Item(1)
    $used = $ws.UsedRange
    $rowCount = $used.Rows.Count
    $colCount = $used.Columns.Count
    Write-Host "Sheet: $($ws.Name) | Rows: $rowCount | Cols: $colCount"

    $values = $used.Value2

    $headers = @()
    $maxLen = @()
    for ($c = 1; $c -le $colCount; $c++) {
        $name = [string]$used.Cells.Item(1, $c).Value2
        $snake = [regex]::Replace($name, '([a-z0-9])([A-Z])', '$1_$2')
        $snake = $snake -replace '\s+', '_' -replace '\(|\)|\.|%', '' -replace '_+', '_'
        $snake = $snake.Trim('_').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($snake)) { $snake = "col_$c" }
        $headers += $snake
        $maxLen += 1
    }

    for ($r = 2; $r -le $rowCount; $r++) {
        for ($c = 1; $c -le $colCount; $c++) {
            $v = $values[$r, $c]
            if ($null -ne $v) {
                $len = $v.ToString().Length
                if ($len -gt $maxLen[$c - 1]) { $maxLen[$c - 1] = $len }
            }
        }
    }

    Write-Host "Creating table $targetSchema.$targetTable"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $conn.Open()
    $colDefs = for ($c = 0; $c -lt $colCount; $c++) {
        $size = $maxLen[$c]
        if ($size -lt 1) { $size = 1 }
        "[$($headers[$c])] nvarchar($size) NULL"
    }
    $createSql = "IF OBJECT_ID('$targetSchema.$targetTable','U') IS NOT NULL DROP TABLE [$targetSchema].[$targetTable]; CREATE TABLE [$targetSchema].[$targetTable] (" + ($colDefs -join ', ') + ");"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $createSql
    $cmd.ExecuteNonQuery() | Out-Null

    $dt = New-Object System.Data.DataTable
    foreach ($h in $headers) {
        $dt.Columns.Add($h, [System.Type]::GetType('System.String')) | Out-Null
    }
    for ($r = 2; $r -le $rowCount; $r++) {
        $row = $dt.NewRow()
        for ($c = 1; $c -le $colCount; $c++) {
            $v = $values[$r, $c]
            $row[$headers[$c - 1]] = if ($null -eq $v) { [DBNull]::Value } else { $v.ToString() }
        }
        $dt.Rows.Add($row)
    }

    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($conn, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepNulls, $null)
    $bulk.DestinationTableName = "[$targetSchema].[$targetTable]"
    $bulk.BulkCopyTimeout = 300
    foreach ($h in $headers) {
        $null = $bulk.ColumnMappings.Add($h, $h)
    }
    $bulk.WriteToServer($dt)
    $bulk.Close()

    $cmd.CommandText = "SELECT COUNT(*) AS TotalRows, COUNT(DISTINCT customer_id) AS DistinctCustomers FROM [$targetSchema].[$targetTable]"
    $r2 = $cmd.ExecuteReader()
    while ($r2.Read()) {
        Write-Host "LOADED: $($r2['TotalRows']) rows | $($r2['DistinctCustomers']) distinct customers"
    }
    $r2.Close()
    $conn.Close()
    $wb.Close($false)
}
catch {
    Write-Output "FAIL: $($_.Exception.Message)"
}
finally {
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
}