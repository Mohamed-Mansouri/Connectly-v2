param([string]$ApiUrl = 'http://127.0.0.1:8787')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(30)
$backendRoot = Split-Path -Parent $PSScriptRoot
$settings = Get-Content -LiteralPath (Join-Path $backendRoot 'appsettings.json') -Raw | ConvertFrom-Json
$databaseUrl = $settings.Turso.DatabaseUrl -replace '^libsql://', 'https://'
$databaseToken = (Get-Content -LiteralPath (Join-Path $backendRoot $settings.Turso.TokenFile) -Raw).Trim()

function Send-Json {
    param([string]$Method, [string]$Url, $Body, [string]$Token, [int]$ExpectedStatus)
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Url)
    if ($Token) {
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
    }
    if ($null -ne $Body) {
        $json = ConvertTo-Json -InputObject $Body -Depth 15 -Compress
        $request.Content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
    }
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -ne $ExpectedStatus) {
                throw "Expected HTTP $ExpectedStatus; received HTTP $([int]$response.StatusCode). Response omitted."
            }
            $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($text) { return ($text | ConvertFrom-Json) }
        } finally { $response.Dispose() }
    } finally { $request.Dispose() }
}

function Invoke-Database {
    param([string]$Sql, [string[]]$Values = @())
    $arguments = @($Values | ForEach-Object { @{ type = 'text'; value = $_ } })
    $result = Send-Json -Method POST -Url ($databaseUrl + '/v2/pipeline') -Token $databaseToken -ExpectedStatus 200 -Body @{
        requests = @(
            @{ type = 'execute'; stmt = @{ sql = $Sql; args = $arguments } },
            @{ type = 'close' }
        )
    }
    if ($result.results[0].type -ne 'ok') { throw 'A database test operation failed. Details omitted.' }
    return $result.results[0].response.result
}

function Assert-Check {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAILED: $Description" }
    Write-Output "PASS: $Description"
}

$email = 'connectly-smoke-' + [Guid]::NewGuid().ToString('N') + '@example.test'
$password = [Guid]::NewGuid().ToString('N') + '!Aa9'
$userId = $null

try {
    $health = Send-Json -Method GET -Url ($ApiUrl + '/health') -ExpectedStatus 200
    Assert-Check ($health.status -eq 'ok') 'API reaches Turso'
    [void](Send-Json -Method GET -Url ($ApiUrl + '/me') -ExpectedStatus 401)
    Write-Output 'PASS: anonymous profile access is rejected'

    $signup = Send-Json -Method POST -Url ($ApiUrl + '/auth/signup') -ExpectedStatus 201 -Body @{
        name = 'Connection Test'; email = $email.ToUpperInvariant(); password = $password
    }
    Assert-Check ($signup.user.email -ceq $email) 'registration normalizes email'
    $userId = $signup.user.id
    Assert-Check ([bool]$userId -and $signup.token -match '^[A-Za-z0-9_-]{43}$') 'registration returns a user session'

    $duplicate = Send-Json -Method POST -Url ($ApiUrl + '/auth/signup') -ExpectedStatus 409 -Body @{
        name = 'Duplicate'; email = $email; password = $password
    }
    Assert-Check ($duplicate.error.code -eq 'email_taken') 'duplicate email is rejected'

    $wrong = Send-Json -Method POST -Url ($ApiUrl + '/auth/login') -ExpectedStatus 401 -Body @{
        email = $email; password = 'incorrect-password'
    }
    $unknown = Send-Json -Method POST -Url ($ApiUrl + '/auth/login') -ExpectedStatus 401 -Body @{
        email = ('unknown-' + $email); password = 'incorrect-password'
    }
    Assert-Check ($wrong.error.message -eq $unknown.error.message) 'wrong password and unknown account return the same error'

    $login = Send-Json -Method POST -Url ($ApiUrl + '/auth/login') -ExpectedStatus 200 -Body @{
        email = $email; password = $password
    }
    $profile = Send-Json -Method GET -Url ($ApiUrl + '/me') -Token $login.token -ExpectedStatus 200
    Assert-Check ($profile.user.id -eq $userId) 'login session authenticates the correct profile'
    Assert-Check (-not ($profile.user.PSObject.Properties.Name -contains 'password_hash')) 'profile omits the password hash'

    $stored = Invoke-Database -Sql 'SELECT password_hash FROM users WHERE id = ? AND email = ?' -Values @($userId, $email)
    Assert-Check ($stored.rows[0][0].value -ne $password -and $stored.rows[0][0].value.Length -gt 64) 'password is stored as a framework-generated hash'
    $sessionRows = Invoke-Database -Sql 'SELECT COUNT(*) AS total FROM auth_sessions WHERE user_id = ?' -Values @($userId)
    Assert-Check ($sessionRows.rows[0][0].value -eq '2') 'failed duplicate registration rolls back its session'

    [void](Send-Json -Method POST -Url ($ApiUrl + '/auth/logout') -Token $login.token -ExpectedStatus 204)
    [void](Send-Json -Method GET -Url ($ApiUrl + '/me') -Token $login.token -ExpectedStatus 401)
    Write-Output 'PASS: logout revokes the bearer session'

    [void](Invoke-Database -Sql 'UPDATE auth_sessions SET expires_at = ? WHERE user_id = ?' -Values @('2000-01-01T00:00:00.000Z', $userId))
    [void](Send-Json -Method GET -Url ($ApiUrl + '/me') -Token $signup.token -ExpectedStatus 401)
    Write-Output 'PASS: expired sessions are rejected'
} finally {
    if ($userId) {
        [void](Invoke-Database -Sql 'DELETE FROM auth_sessions WHERE user_id IN (SELECT id FROM users WHERE id = ? AND email = ?)' -Values @($userId, $email))
        [void](Invoke-Database -Sql 'DELETE FROM users WHERE id = ? AND email = ?' -Values @($userId, $email))
        Write-Output 'Removed only the generated smoke-test account and its sessions.'
    }
    $client.Dispose()
}
