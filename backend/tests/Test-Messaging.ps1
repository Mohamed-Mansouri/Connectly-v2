param([string]$ApiUrl = 'http://127.0.0.1:8789')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(30)
$backendRoot = Split-Path -Parent $PSScriptRoot
$settings = Get-Content -LiteralPath (Join-Path $backendRoot 'appsettings.json') -Raw | ConvertFrom-Json
$databaseUrl = $settings.Turso.DatabaseUrl -replace '^libsql://', 'https://'
$databaseToken = (Get-Content -LiteralPath (Join-Path $backendRoot $settings.Turso.TokenFile) -Raw).Trim()
$testUserIds = [System.Collections.Generic.List[string]]::new()

function Send-Json {
    param([string]$Method, [string]$Path, $Body, [string]$Token, [int]$ExpectedStatus = 200)
    $url = if ($Path.StartsWith('https://')) { $Path } else { $ApiUrl + $Path }
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $url)
    if ($Token) { $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token) }
    if ($null -ne $Body) { $request.Content = [System.Net.Http.StringContent]::new((ConvertTo-Json -InputObject $Body -Depth 15 -Compress), [System.Text.Encoding]::UTF8, 'application/json') }
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -ne $ExpectedStatus) { throw "Expected HTTP $ExpectedStatus; received HTTP $([int]$response.StatusCode). Response omitted." }
            $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($text) { return ($text | ConvertFrom-Json) }
        } finally { $response.Dispose() }
    } finally { $request.Dispose() }
}
function Invoke-Database {
    param([string]$Sql, [string[]]$Values = @())
    $result = Send-Json -Method POST -Path ($databaseUrl + '/v2/pipeline') -Token $databaseToken -Body @{
        requests = @(@{ type = 'execute'; stmt = @{ sql = $Sql; args = @($Values | ForEach-Object { @{ type = 'text'; value = $_ } }) } }, @{ type = 'close' })
    }
    if ($result.results[0].type -ne 'ok') { throw 'Database check failed. Details omitted.' }
    return $result.results[0].response.result
}
function Assert-Check {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAILED: $Description" }
    Write-Output "PASS: $Description"
}
function New-TestUser {
    param([string]$Label)
    $account = Send-Json -Method POST -Path '/auth/signup' -ExpectedStatus 201 -Body @{
        name = "Messaging Test $Label"; email = ('chat-' + [Guid]::NewGuid().ToString('N') + '@example.test'); password = ([Guid]::NewGuid().ToString('N') + '!Aa9')
    }
    $testUserIds.Add($account.user.id)
    return $account
}
try {
    [void](Send-Json -Method GET -Path '/conversations' -ExpectedStatus 401)
    Write-Output 'PASS: anonymous inbox access is rejected'
    $a = New-TestUser 'Alpha'
    $b = New-TestUser 'Beta'
    $c = New-TestUser 'Gamma'
    $outsider = New-TestUser 'Outsider'
    [void](Send-Json -Method POST -Path '/conversations' -Token $a.token -ExpectedStatus 403 -Body @{ kind = 'direct'; memberIds = @($outsider.user.id) })
    Write-Output 'PASS: starting a chat requires an eligible connection'
    foreach ($person in @($b, $c)) { [void](Send-Json -Method PUT -Path "/people/$($person.user.id)/follow" -Token $a.token -ExpectedStatus 204) }
    [void](Send-Json -Method PUT -Path "/people/$($a.user.id)/follow" -Token $b.token -ExpectedStatus 204)
    $contacts = Send-Json -Method GET -Path '/conversations/contacts?search=Messaging%20Test' -Token $a.token
    Assert-Check (@($contacts.contacts).Count -eq 2) 'contacts include followed people and exclude strangers/self'
    Assert-Check (-not ($contacts.contacts[0].PSObject.Properties.Name -contains 'email')) 'contacts omit private account fields'
    $direct = (Send-Json -Method POST -Path '/conversations' -Token $a.token -ExpectedStatus 201 -Body @{ kind = 'direct'; memberIds = @($b.user.id) }).conversation
    $reverse = (Send-Json -Method POST -Path '/conversations' -Token $b.token -ExpectedStatus 201 -Body @{ kind = 'direct'; memberIds = @($a.user.id) }).conversation
    Assert-Check ($direct.id -eq $reverse.id -and $direct.title -eq $b.user.name -and $reverse.title -eq $a.user.name) 'direct chat is unique for the pair and titles use the other person'
    $members = Send-Json -Method GET -Path "/conversations/$($direct.id)/members" -Token $a.token
    Assert-Check (@($members.members).Count -eq 2) 'direct chat has exactly two members'
    foreach ($suffix in @('messages', 'members')) {
        [void](Send-Json -Method GET -Path "/conversations/$($direct.id)/$suffix" -Token $outsider.token -ExpectedStatus 404)
    }
    [void](Send-Json -Method POST -Path "/conversations/$($direct.id)/messages" -Token $outsider.token -ExpectedStatus 404 -Body @{ clientId = [Guid]::NewGuid().ToString(); body = 'Forbidden' })
    [void](Send-Json -Method POST -Path "/conversations/$($direct.id)/read" -Token $outsider.token -ExpectedStatus 404 -Body @{ throughSequence = 999999 })
    $hidden = Send-Json -Method GET -Path '/conversations' -Token $outsider.token
    Assert-Check (@($hidden.conversations).Count -eq 0) 'nonmembers cannot list/read/send/mark the private conversation'
    $clientId = [Guid]::NewGuid().ToString()
    $first = (Send-Json -Method POST -Path "/conversations/$($direct.id)/messages" -Token $a.token -ExpectedStatus 201 -Body @{ clientId = $clientId; body = '  Hello Beta  '; senderId = $outsider.user.id }).message
    $retry = (Send-Json -Method POST -Path "/conversations/$($direct.id)/messages" -Token $a.token -ExpectedStatus 201 -Body @{ clientId = $clientId; body = 'Hello Beta' }).message
    Assert-Check ($first.sequence -eq $retry.sequence -and $first.sender.id -eq $a.user.id -and $first.body -ceq 'Hello Beta') 'sending derives the sender, trims text, and deduplicates retries'
    [void](Send-Json -Method POST -Path "/conversations/$($direct.id)/messages" -Token $a.token -ExpectedStatus 409 -Body @{ clientId = $clientId; body = 'Changed retry' })
    [void](Send-Json -Method POST -Path "/conversations/$($direct.id)/messages" -Token $a.token -ExpectedStatus 400 -Body @{ clientId = [Guid]::NewGuid().ToString(); body = '   ' })
    $inbox = Send-Json -Method GET -Path '/conversations' -Token $b.token
    Assert-Check ($inbox.conversations[0].unreadCount -eq 1 -and $inbox.conversations[0].lastBody -eq 'Hello Beta') 'recipient inbox includes the shared preview and unread count'
    [void](Send-Json -Method POST -Path "/conversations/$($direct.id)/read" -Token $b.token -ExpectedStatus 204 -Body @{ throughSequence = 999999999 })
    $inbox = Send-Json -Method GET -Path '/conversations' -Token $b.token
    Assert-Check ($inbox.conversations[0].unreadCount -eq 0) 'opening the conversation clears existing unread messages'
    [void](Send-Json -Method POST -Path "/conversations/$($direct.id)/messages" -Token $a.token -ExpectedStatus 201 -Body @{ clientId = [Guid]::NewGuid().ToString(); body = 'A later message' })
    $inbox = Send-Json -Method GET -Path '/conversations' -Token $b.token
    Assert-Check ($inbox.conversations[0].unreadCount -eq 1) 'read cursor is bounded to existing messages and cannot hide future unread messages'
    $after = Send-Json -Method GET -Path "/conversations/$($direct.id)/messages?after=$($first.sequence)" -Token $b.token
    Assert-Check (@($after.messages).Count -eq 1 -and $after.messages[0].body -eq 'A later message') 'incremental fetch delivers new messages in the other account'
    $group = (Send-Json -Method POST -Path '/conversations' -Token $a.token -ExpectedStatus 201 -Body @{ kind = 'group'; title = '  Study group  '; memberIds = @($b.user.id, $c.user.id) }).conversation
    Assert-Check ($group.kind -eq 'group' -and $group.title -ceq 'Study group' -and $group.memberCount -eq 3) 'group creation includes its creator and selected members'
    $groupMessage = (Send-Json -Method POST -Path "/conversations/$($group.id)/messages" -Token $c.token -ExpectedStatus 201 -Body @{ clientId = [Guid]::NewGuid().ToString(); body = 'Hello group' }).message
    $groupHistory = Send-Json -Method GET -Path "/conversations/$($group.id)/messages" -Token $b.token
    Assert-Check ($groupHistory.messages[0].sequence -eq $groupMessage.sequence -and $groupHistory.messages[0].sender.id -eq $c.user.id) 'group messages are shared with all members and identify the real sender'
    [void](Send-Json -Method GET -Path "/conversations/$($group.id)/messages" -Token $outsider.token -ExpectedStatus 404)
    [void](Send-Json -Method POST -Path '/conversations' -Token $a.token -ExpectedStatus 400 -Body @{ kind = 'group'; title = 'Invalid'; memberIds = @($b.user.id, $b.user.id) })
    Write-Output 'PASS: duplicate group members and outsider access are rejected'
    $values = [System.Collections.Generic.List[string]]::new()
    $rows = @()
    for ($i = 0; $i -lt 55; $i++) {
        $rows += '(?, ?, ?, ?, ?)'
        foreach ($value in @($direct.id, $a.user.id, [Guid]::NewGuid().ToString(), "Pagination message $i", '2026-10-24T12:00:00.000Z')) { $values.Add($value) }
    }
    [void](Invoke-Database -Sql ('INSERT INTO messages (conversation_id, sender_id, client_id, body, created_at) VALUES ' + ($rows -join ',')) -Values $values.ToArray())
    $latest = Send-Json -Method GET -Path "/conversations/$($direct.id)/messages" -Token $b.token
    $older = Send-Json -Method GET -Path "/conversations/$($direct.id)/messages?before=$($latest.olderCursor)" -Token $b.token
    $all = @($older.messages.sequence) + @($latest.messages.sequence)
    Assert-Check (@($latest.messages).Count -eq 50 -and @($older.messages).Count -eq 7 -and @($all | Select-Object -Unique).Count -eq 57) 'older history uses sequence cursors without missing or duplicating tied timestamps'
    $forward1 = Send-Json -Method GET -Path "/conversations/$($direct.id)/messages?after=0" -Token $b.token
    $lastSequence = $forward1.messages[-1].sequence
    $forward2 = Send-Json -Method GET -Path "/conversations/$($direct.id)/messages?after=$lastSequence" -Token $b.token
    Assert-Check ($forward1.hasMore -and -not $forward2.hasMore -and @($forward2.messages).Count -eq 7) 'incremental polling drains backlogs larger than one page'
} finally {
    try {
        if ($testUserIds.Count -gt 0) {
            $slots = ($testUserIds | ForEach-Object { '?' }) -join ','
            $ids = $testUserIds.ToArray()
            [void](Invoke-Database -Sql "DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE created_by IN ($slots)) OR sender_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM conversation_members WHERE conversation_id IN (SELECT id FROM conversations WHERE created_by IN ($slots)) OR user_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM conversations WHERE created_by IN ($slots)" -Values $ids)
            [void](Invoke-Database -Sql "DELETE FROM follows WHERE follower_id IN ($slots) OR followed_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM friendships WHERE user_low_id IN ($slots) OR user_high_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM auth_sessions WHERE user_id IN ($slots)" -Values $ids)
            [void](Invoke-Database -Sql "DELETE FROM users WHERE id IN ($slots)" -Values $ids)
            Write-Output 'Removed only the accounts, connections, conversations, and messages created by this check.'
        }
    } finally { $client.Dispose() }
}
