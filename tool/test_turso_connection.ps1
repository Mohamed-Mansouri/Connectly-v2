param(
    [string]$DatabaseUrl = 'libsql://connectly1-mansouri.aws-eu-north-1.turso.io',
    [string]$TokenFile = (Join-Path $PSScriptRoot '../dbtoken')
)

$ErrorActionPreference = 'Stop'

# Read the credential locally; never print it or include it in command arguments.
$token = (Get-Content -LiteralPath $TokenFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'The database token file is empty.'
}

$databaseUri = [Uri]($DatabaseUrl -replace '^libsql://', 'https://')
if ($databaseUri.Scheme -ne 'https' -or $databaseUri.Host -notlike '*.turso.io') {
    throw 'Use an HTTPS or libsql URL for a Turso database.'
}
$endpoint = $databaseUri.GetLeftPart([UriPartial]::Authority) + '/v2/pipeline'

function Invoke-TursoPipeline {
    param([object[]]$Requests)

    $body = @{ requests = @($Requests) + @(@{ type = 'close' }) } |
        ConvertTo-Json -Depth 12 -Compress
    try {
        $response = Invoke-RestMethod -Uri $endpoint -Method Post `
            -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/json' -Body $body -TimeoutSec 30 `
            -MaximumRedirection 0
    }
    catch {
        $status = 'unavailable'
        if ($null -ne $_.Exception.Response) {
            $status = [string][int]$_.Exception.Response.StatusCode
        }
        throw "Turso HTTP request failed (status: $status). Credential omitted."
    }

    if ($null -eq $response.results -or $response.results.Count -ne ($Requests.Count + 1)) {
        throw 'Turso returned an unexpected response.'
    }
    foreach ($result in $response.results) {
        if ($result.type -ne 'ok') {
            throw 'Turso rejected a database statement. Check database permissions and the test table schema.'
        }
    }
    return $response
}

$testId = [Guid]::NewGuid().ToString()
$message = 'Connectly test write successful'
$boundId = @{ type = 'text'; value = $testId }

$writeResponse = Invoke-TursoPipeline -Requests @(
    @{ type = 'execute'; stmt = @{ sql = 'BEGIN IMMEDIATE' } },
    @{ type = 'execute'; stmt = @{
        sql = 'CREATE TABLE IF NOT EXISTS connectly_connection_tests (test_id TEXT PRIMARY KEY, message TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)'
    } },
    @{ type = 'execute'; stmt = @{
        sql = 'INSERT INTO connectly_connection_tests (test_id, message) VALUES (?, ?)'
        args = @($boundId, @{ type = 'text'; value = $message })
    } },
    @{ type = 'execute'; stmt = @{ sql = 'COMMIT' } }
)
if ($writeResponse.results[2].response.result.affected_row_count -ne 1) {
    throw 'The test insert did not affect exactly one row.'
}

# Read through a new connection to verify that the write was committed.
$readResponse = Invoke-TursoPipeline -Requests @(
    @{ type = 'execute'; stmt = @{
        sql = 'SELECT test_id, message, created_at FROM connectly_connection_tests WHERE test_id = ?'
        args = @($boundId)
    } }
)
$rows = $readResponse.results[0].response.result.rows
if ($rows.Count -ne 1 -or $rows[0][0].value -ne $testId -or $rows[0][1].value -ne $message) {
    throw 'The database read did not match the inserted test record.'
}

[ordered]@{
    verified = $true
    database = $databaseUri.Host
    table = 'connectly_connection_tests'
    test_id = $testId
    message = $rows[0][1].value
    created_at_utc = $rows[0][2].value
} | ConvertTo-Json
