param([string]$ApiUrl = 'http://127.0.0.1:8788')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(30)
$backendRoot = Split-Path -Parent $PSScriptRoot
$settings = Get-Content -LiteralPath (Join-Path $backendRoot 'appsettings.json') -Raw | ConvertFrom-Json
$databaseUrl = $settings.Turso.DatabaseUrl -replace '^libsql://', 'https://'
$databaseToken = (Get-Content -LiteralPath (Join-Path $backendRoot $settings.Turso.TokenFile) -Raw).Trim()
$testUserIds = [System.Collections.Generic.List[string]]::new()
$prefix = 'Feed Check ' + [Guid]::NewGuid().ToString('N')

function Send-Json {
    param([string]$Method, [string]$Path, $Body, [string]$Token, [int]$ExpectedStatus = 200)
    $url = if ($Path.StartsWith('https://')) { $Path } else { $ApiUrl + $Path }
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $url)
    if ($Token) { $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token) }
    if ($null -ne $Body) {
        $request.Content = [System.Net.Http.StringContent]::new((ConvertTo-Json -InputObject $Body -Depth 15 -Compress), [System.Text.Encoding]::UTF8, 'application/json')
    }
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
        name = "$prefix $Label"; email = ('feed-' + [Guid]::NewGuid().ToString('N') + '@example.test'); password = ([Guid]::NewGuid().ToString('N') + '!Aa9')
    }
    $testUserIds.Add($account.user.id)
    return $account
}

try {
    [void](Send-Json -Method GET -Path '/feed' -ExpectedStatus 401)
    Write-Output 'PASS: anonymous feed access is rejected'
    $author = New-TestUser 'Author'
    $follower = New-TestUser 'Follower'
    $friend = New-TestUser 'Friend'
    $stranger = New-TestUser 'Stranger'
    $post = (Send-Json -Method POST -Path '/posts' -Token $author.token -ExpectedStatus 201 -Body @{ body = '  A real feed post  ' }).post
    Assert-Check ($post.body -ceq 'A real feed post' -and $post.author.id -eq $author.user.id) 'post is trimmed and authored by the authenticated account'
    [void](Send-Json -Method POST -Path '/posts' -Token $author.token -ExpectedStatus 400 -Body @{ body = '   ' })
    $initial = Send-Json -Method GET -Path '/feed' -Token $stranger.token
    Assert-Check (@($initial.posts).Count -eq 0) 'unconnected users do not see the post'
    [void](Send-Json -Method PUT -Path "/posts/$($post.id)/reaction" -Token $stranger.token -ExpectedStatus 404 -Body @{ kind = 'like' })
    Write-Output 'PASS: unconnected users cannot react using a guessed post ID'

    [void](Send-Json -Method PUT -Path "/people/$($author.user.id)/follow" -Token $follower.token -ExpectedStatus 204)
    $followFeed = Send-Json -Method GET -Path '/feed?scope=following' -Token $follower.token
    Assert-Check (@($followFeed.posts).Count -eq 1 -and $followFeed.posts[0].id -eq $post.id) 'one-way following includes the author in Following'
    $otherPost = (Send-Json -Method POST -Path '/posts' -Token $follower.token -ExpectedStatus 201 -Body @{ body = 'Follower post' }).post
    $authorFeed = Send-Json -Method GET -Path '/feed' -Token $author.token
    Assert-Check (@($authorFeed.posts).Count -eq 1) 'being followed does not automatically follow back'
    $friendsOnly = Send-Json -Method GET -Path '/feed?scope=friends' -Token $follower.token
    Assert-Check (@($friendsOnly.posts).Count -eq 1 -and $friendsOnly.posts[0].id -eq $otherPost.id) 'Friends excludes follows while retaining own posts'

    [void](Send-Json -Method PUT -Path "/people/$($author.user.id)/friendship" -Token $friend.token -ExpectedStatus 204 -Body @{ action = 'request' })
    $pending = Send-Json -Method GET -Path '/feed' -Token $friend.token
    Assert-Check (@($pending.posts).Count -eq 0) 'pending requests do not grant feed access'
    [void](Send-Json -Method PUT -Path "/people/$($author.user.id)/friendship" -Token $friend.token -ExpectedStatus 409 -Body @{ action = 'accept' })
    $requests = Send-Json -Method GET -Path ('/people?requests=true&search=' + [Uri]::EscapeDataString($prefix)) -Token $author.token
    Assert-Check (@($requests.people).Count -eq 1 -and $requests.people[0].friendship -eq 'incoming') 'recipient sees the incoming request without private account fields'
    Assert-Check (-not ($requests.people[0].PSObject.Properties.Name -contains 'email')) 'people directory omits email addresses'
    [void](Send-Json -Method PUT -Path "/people/$($friend.user.id)/friendship" -Token $author.token -ExpectedStatus 204 -Body @{ action = 'accept' })
    $accepted = Send-Json -Method GET -Path '/feed?scope=friends' -Token $friend.token
    Assert-Check (@($accepted.posts).Count -eq 1) 'accepted friendship includes posts without a follow'

    $reacted = (Send-Json -Method PUT -Path "/posts/$($post.id)/reaction" -Token $follower.token -Body @{ kind = 'like' }).post
    Assert-Check ($reacted.reactions.like -eq 1 -and $reacted.myReaction -eq 'like') 'reaction count and own selection come from the server'
    $reacted = (Send-Json -Method PUT -Path "/posts/$($post.id)/reaction" -Token $follower.token -Body @{ kind = 'love' }).post
    Assert-Check ($reacted.reactions.like -eq 0 -and $reacted.reactions.love -eq 1) 'changing a reaction replaces the previous selection'
    $reacted = (Send-Json -Method PUT -Path "/posts/$($post.id)/reaction" -Token $follower.token -Body @{ kind = 'love' }).post
    Assert-Check ($reacted.reactions.love -eq 1) 'repeating the same reaction is idempotent'
    [void](Send-Json -Method PUT -Path "/posts/$($post.id)/reaction" -Token $friend.token -Body @{ kind = 'celebrate' })
    $removed = (Send-Json -Method DELETE -Path "/posts/$($post.id)/reaction" -Token $follower.token).post
    Assert-Check ($removed.reactions.love -eq 0 -and $removed.reactions.celebrate -eq 1 -and $null -eq $removed.myReaction) 'removing own reaction preserves another user reaction'
    [void](Send-Json -Method PUT -Path "/posts/$($post.id)/reaction" -Token $follower.token -ExpectedStatus 400 -Body @{ kind = 'unsupported' })
    [void](Send-Json -Method DELETE -Path "/posts/$($post.id)" -Token $follower.token -ExpectedStatus 204)
    $stillThere = Send-Json -Method GET -Path '/feed' -Token $author.token
    Assert-Check (@($stillThere.posts).Count -eq 1) 'another account cannot delete the post'

    for ($i = 0; $i -lt 21; $i++) {
        [void](Invoke-Database -Sql 'INSERT INTO posts (id, author_id, body, created_at) VALUES (?, ?, ?, ?)' -Values @([Guid]::NewGuid().ToString(), $author.user.id, "Pagination fixture $i", '2026-01-01T00:00:00.000Z'))
    }
    $page1 = Send-Json -Method GET -Path '/feed' -Token $author.token
    $page2 = Send-Json -Method GET -Path ('/feed?cursor=' + [Uri]::EscapeDataString($page1.nextCursor)) -Token $author.token
    $allIds = @($page1.posts.id) + @($page2.posts.id)
    Assert-Check (@($page1.posts).Count -eq 20 -and @($page2.posts).Count -eq 2 -and @($allIds | Select-Object -Unique).Count -eq 22) 'cursor pagination handles tied timestamps without missing or duplicating posts'

    [void](Send-Json -Method DELETE -Path "/people/$($author.user.id)/follow" -Token $follower.token -ExpectedStatus 204)
    [void](Send-Json -Method PUT -Path "/people/$($author.user.id)/friendship" -Token $friend.token -ExpectedStatus 204 -Body @{ action = 'remove' })
    $unfollowed = Send-Json -Method GET -Path '/feed' -Token $follower.token
    $unfriended = Send-Json -Method GET -Path '/feed' -Token $friend.token
    Assert-Check (@($unfollowed.posts).Count -eq 1 -and @($unfriended.posts).Count -eq 0) 'unfollowing and removing friendship remove feed access independently'
    [void](Send-Json -Method DELETE -Path "/posts/$($post.id)" -Token $author.token -ExpectedStatus 204)
    $reactions = Invoke-Database -Sql 'SELECT COUNT(*) FROM post_reactions WHERE post_id = ?' -Values @($post.id)
    Assert-Check ($reactions.rows[0][0].value -eq '0') 'author deletion also removes reactions'
} finally {
    try {
        if ($testUserIds.Count -gt 0) {
            $slots = ($testUserIds | ForEach-Object { '?' }) -join ','
            $ids = $testUserIds.ToArray()
            [void](Invoke-Database -Sql "DELETE FROM post_reactions WHERE post_id IN (SELECT id FROM posts WHERE author_id IN ($slots)) OR user_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM posts WHERE author_id IN ($slots)" -Values $ids)
            [void](Invoke-Database -Sql "DELETE FROM follows WHERE follower_id IN ($slots) OR followed_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM friendships WHERE user_low_id IN ($slots) OR user_high_id IN ($slots)" -Values ($ids + $ids))
            [void](Invoke-Database -Sql "DELETE FROM auth_sessions WHERE user_id IN ($slots)" -Values $ids)
            [void](Invoke-Database -Sql "DELETE FROM users WHERE id IN ($slots)" -Values $ids)
            Write-Output 'Removed only the accounts and records created by this feed check.'
        }
    } finally { $client.Dispose() }
}
