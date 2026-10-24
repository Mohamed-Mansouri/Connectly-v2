using System.Net.Http.Headers;
using System.Text.Json;
using Connectly.Api.Models;

namespace Connectly.Api.Data;

public sealed record SqlStatement(string Sql, params string[] Args);
public sealed record SqlResult(IReadOnlyList<Dictionary<string, string?>> Rows, long AffectedRows);

// Uses Turso's documented /v2/pipeline protocol; credentials never reach Flutter.
public sealed class TursoDatabase(
    IHttpClientFactory clients,
    IConfiguration configuration,
    IWebHostEnvironment environment)
{
    private readonly Uri _endpoint = BuildEndpoint(configuration);

    private static Uri BuildEndpoint(IConfiguration configuration)
    {
        var url = configuration["Turso:DatabaseUrl"]
            ?? throw new InvalidOperationException("Configure Turso:DatabaseUrl.");
        var uri = new Uri(url.Replace("libsql://", "https://", StringComparison.Ordinal));
        if (uri.Scheme != "https" || !uri.Host.EndsWith(".turso.io", StringComparison.OrdinalIgnoreCase)
            || !string.IsNullOrEmpty(uri.UserInfo))
            throw new InvalidOperationException("Configure an HTTPS Turso database URL.");
        return new Uri(uri.GetLeftPart(UriPartial.Authority) + "/v2/pipeline");
    }

    private async Task<string> ReadTokenAsync(CancellationToken ct)
    {
        var token = configuration["Turso:AuthToken"];
        if (string.IsNullOrWhiteSpace(token))
        {
            var path = Path.GetFullPath(
                configuration["Turso:TokenFile"] ?? "../dbtoken", environment.ContentRootPath);
            token = await File.ReadAllTextAsync(path, ct);
        }
        if (string.IsNullOrWhiteSpace(token))
            throw new InvalidOperationException("The Turso credential is empty.");
        return token.Trim();
    }

    public async Task<SqlResult> ExecuteAsync(string sql, CancellationToken ct, params string[] args)
    {
        var connection = new Pipeline(this);
        var results = await connection.SendAsync([new SqlStatement(sql, args)], close: true, ct);
        return results[0];
    }

    public async Task BatchAsync(IEnumerable<SqlStatement> statements, CancellationToken ct)
    {
        var connection = new Pipeline(this);
        await connection.SendAsync([new SqlStatement("BEGIN IMMEDIATE")], close: false, ct);
        try
        {
            // Commit only after every statement succeeds. Errors trigger rollback.
            await connection.SendAsync(statements.ToArray(), close: false, ct);
            await connection.SendAsync([new SqlStatement("COMMIT")], close: true, ct);
        }
        catch
        {
            try
            {
                await connection.SendAsync([new SqlStatement("ROLLBACK")], close: true, CancellationToken.None);
            }
            catch { /* Closing/timeout also rolls back an uncommitted transaction. */ }
            throw;
        }
    }

    public async Task MigrateAsync(CancellationToken ct)
    {
        var directory = Path.Combine(environment.ContentRootPath, "migrations");
        foreach (var path in Directory.GetFiles(directory, "*.sql").Order(StringComparer.Ordinal))
        {
            var sql = await File.ReadAllTextAsync(path, ct);
            var statements = sql.Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            await BatchAsync(statements.Select(statement => new SqlStatement(statement)), ct);
        }
    }

    private sealed class Pipeline(TursoDatabase database)
    {
        private string? _baton;

        public async Task<IReadOnlyList<SqlResult>> SendAsync(
            IReadOnlyList<SqlStatement> statements, bool close, CancellationToken ct)
        {
            var requests = new List<object>();
            foreach (var statement in statements)
                requests.Add(new
                {
                    type = "execute",
                    stmt = new
                    {
                        sql = statement.Sql,
                        args = statement.Args.Select(value => new { type = "text", value }).ToArray()
                    }
                });
            if (close) requests.Add(new { type = "close" });

            using var message = new HttpRequestMessage(HttpMethod.Post, database._endpoint);
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await database.ReadTokenAsync(ct));
            message.Content = JsonContent.Create(new { baton = _baton, requests });
            using var client = database.CreateClient();
            using var response = await client.SendAsync(message, ct);
            if (!response.IsSuccessStatusCode) throw new TursoException("HTTP_" + (int)response.StatusCode);
            using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
            var root = document.RootElement;
            _baton = root.TryGetProperty("baton", out var baton) && baton.ValueKind == JsonValueKind.String
                ? baton.GetString() : null;
            var items = root.GetProperty("results").EnumerateArray().ToArray();
            if (items.Length != requests.Count) throw new TursoException("INVALID_RESPONSE");
            var results = new List<SqlResult>();
            foreach (var item in items)
            {
                if (item.GetProperty("type").GetString() != "ok")
                {
                    var code = item.GetProperty("error").GetProperty("code").GetString() ?? "QUERY_ERROR";
                    throw new TursoException(code);
                }
                var operation = item.GetProperty("response");
                if (operation.GetProperty("type").GetString() != "execute") continue;
                var result = operation.GetProperty("result");
                var columns = result.GetProperty("cols").EnumerateArray()
                    .Select(column => column.GetProperty("name").GetString()!).ToArray();
                var rows = new List<Dictionary<string, string?>>();
                foreach (var row in result.GetProperty("rows").EnumerateArray())
                {
                    var values = row.EnumerateArray().ToArray();
                    var mapped = new Dictionary<string, string?>();
                    for (var index = 0; index < columns.Length; index++)
                        mapped[columns[index]] = values[index].TryGetProperty("value", out var value)
                            ? value.ToString() : null;
                    rows.Add(mapped);
                }
                results.Add(new SqlResult(rows, result.GetProperty("affected_row_count").GetInt64()));
            }
            return results;
        }

    }

    private HttpClient CreateClient() => clients.CreateClient("Turso");
}
