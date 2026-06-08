# Query Failed Dependencies

Queries Application Insights for recent failed dependency calls (HTTP calls, database queries, queue operations, etc.), grouped by type, target, and result code. This surfaces unreliable downstream dependencies to help prioritize reliability improvements.

## Query

The KQL query filters for failed dependency calls (`success == false`), groups them by dependency type, target, and result code, and computes a trend indicator.

```kql
let lookback = ago(24h);
let midpoint = ago(12h);
dependencies
| where timestamp > lookback
| where success == false
| summarize
    FailedCount = count(),
    FirstHalfCount = countif(timestamp < midpoint),
    SecondHalfCount = countif(timestamp >= midpoint),
    AvgDurationMs = round(avg(duration), 1),
    P95DurationMs = round(percentile(duration, 95), 1),
    LastSeen = max(timestamp),
    AffectedOperations = dcount(operation_Name),
    SampleOperationId = take_any(operation_Id),
    TopOperations = make_set(operation_Name, 5)
    by type, target, name, resultCode, cloud_RoleName
| extend Trend = case(
    SecondHalfCount > FirstHalfCount * 1.5, "increasing",
    SecondHalfCount < FirstHalfCount * 0.5, "decreasing",
    "stable")
| order by FailedCount desc
| take 50
| project type, target, name, resultCode, cloud_RoleName, FailedCount, Trend, AvgDurationMs, P95DurationMs, AffectedOperations, LastSeen, SampleOperationId, TopOperations
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `resourceId` | — | Application Insights resource ID (full ARM path) or app ID (GUID). |
| `lookbackHours` | `24` | How many hours to look back. Common values: `1`, `6`, `24`, `48`, `168` (7 days), `720` (30 days). |

## Script

> ⚠️ Read [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md) before modifying this script. Key requirements: `--offset` is mandatory, use `--output json`, and flatten KQL to a single line.

```powershell
$resourceId = "<RESOURCE_ID>"
$lookbackHours = 24  # Adjust: 1, 6, 24, 48, 168 (7 days), 720 (30 days)

$halfLookback = [math]::Max(1, [math]::Floor($lookbackHours / 2))

# Build the KQL query as a single line to avoid here-string truncation issues.
$query = "let lookback = ago(${lookbackHours}h); let midpoint = ago(${halfLookback}h); dependencies | where timestamp > lookback | where success == false | summarize FailedCount = count(), FirstHalfCount = countif(timestamp < midpoint), SecondHalfCount = countif(timestamp >= midpoint), AvgDurationMs = round(avg(duration), 1), P95DurationMs = round(percentile(duration, 95), 1), LastSeen = max(timestamp), AffectedOperations = dcount(operation_Name), SampleOperationId = take_any(operation_Id), TopOperations = make_set(operation_Name, 5) by type, target, name, resultCode, cloud_RoleName | extend Trend = case(SecondHalfCount > FirstHalfCount * 1.5, 'increasing', SecondHalfCount < FirstHalfCount * 0.5, 'decreasing', 'stable') | order by FailedCount desc | take 50 | project type, target, name, resultCode, cloud_RoleName, FailedCount, Trend, AvgDurationMs, P95DurationMs, AffectedOperations, LastSeen, SampleOperationId, TopOperations"

# --offset is MANDATORY: without it, the CLI applies a 1-hour server-side time
# filter regardless of any KQL ago() in the query. Use ISO 8601 duration format.
$offset = if ($lookbackHours -le 24) { "P1D" } elseif ($lookbackHours -le 168) { "P7D" } else { "P30D" }

$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset $offset `
  --output json 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: Query failed (exit code $LASTEXITCODE). Output:"
  Write-Host $result
} else {
  try {
    $parsed = $result | ConvertFrom-Json
  } catch {
    Write-Host "ERROR: Failed to parse query results: $_"
    Write-Host $result
    return
  }

  if (-not $parsed.tables -or $parsed.tables.Count -eq 0) {
    Write-Host "ERROR: Unexpected response structure (no tables). Output:"
    Write-Host $result
    return
  }

  $rows = $parsed.tables[0].rows
  $columns = $parsed.tables[0].columns

  if ($rows.Count -eq 0) {
    Write-Host "No failed dependency calls found in the last $lookbackHours hours."
    Write-Host "Try widening the time range (e.g., `$lookbackHours = 168 for 7 days)."
  } else {
    Write-Host "Found $($rows.Count) failed dependency group(s) in the last $lookbackHours hours:`n"
    $i = 1
    foreach ($row in $rows) {
      $depType     = $row[0]
      $target      = $row[1]
      $depName     = $row[2]
      $code        = $row[3]
      $role        = $row[4]
      $count       = $row[5]
      $trend       = $row[6]
      $avgDur      = $row[7]
      $p95Dur      = $row[8]
      $affectedOps = $row[9]
      $lastSeen    = $row[10]
      $opId        = $row[11]
      Write-Host "[$i] $depType > $target | $code | Count: $count | Trend: $trend"
      Write-Host "    Name: $depName | Role: $role"
      Write-Host "    Avg: ${avgDur}ms | P95: ${p95Dur}ms | Affected operations: $affectedOps | Last seen: $lastSeen"
      if ($opId) { Write-Host "    Sample Operation ID: $opId" }
      Write-Host ""
      $i++
    }
  }
}
```

### Adjusting the time range

Change `$lookbackHours` to widen or narrow the search window. The `$offset` variable is computed automatically to match, but you can also set it explicitly. Use valid ISO 8601 durations only — see [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md#offset-is-mandatory).

### Reading the results

The script parses the JSON response and displays a formatted summary. Each result row contains:

| Column | Description |
|--------|-------------|
| `type` | Dependency type (e.g., `HTTP`, `SQL`, `Azure blob`, `Azure queue`) |
| `target` | The target system (e.g., hostname, database server, storage account) |
| `name` | Dependency call name (e.g., `GET /api/data`, `SELECT * FROM users`) |
| `resultCode` | Result code from the dependency (e.g., HTTP `500`, SQL error code) |
| `cloud_RoleName` | The service/role that made the dependency call |
| `FailedCount` | Number of failed calls in the lookback window |
| `Trend` | Whether the failure rate is `increasing`, `decreasing`, or `stable` |
| `AvgDurationMs` | Average duration of failed calls in milliseconds |
| `P95DurationMs` | 95th percentile duration — very high values suggest timeouts |
| `AffectedOperations` | Number of distinct parent operations affected by this dependency failure |
| `LastSeen` | Most recent failure timestamp |
| `SampleOperationId` | A sample operation ID — use this with the `deep-analysis` skill for distributed trace investigation |
| `TopOperations` | Up to 5 distinct operation names affected by this dependency failure |

### What to do with the results

1. **Identify the most impactful dependencies** — Focus on entries with high `FailedCount` and high `AffectedOperations` (blast radius).
2. **Distinguish dependency types** — HTTP failures to external APIs may require retry logic or circuit breakers; SQL failures may indicate schema or connection issues; storage failures may indicate capacity or permissions problems.
3. **Watch for increasing trends** — Dependencies with `increasing` failure trend may indicate a degrading downstream service.
4. **Check for timeout patterns** — If `P95DurationMs` is very high (e.g., >30,000ms) with result codes like `504` or connection errors, the downstream service may be overloaded or unreachable.
5. **Correlate with failed requests** — Failed dependencies often cause cascading request failures. Cross-reference with the failed requests query to see the end-user impact.

### No results?

If the query returns no rows:

- **Check `--offset`** — See [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md#offset-is-mandatory).
- **No dependency failures in the time window** — Widen the time range.
- **Verify data exists** — Run a simpler query: `dependencies | where success == false | summarize count()`.
- **Check dependency tracking** — Ensure the application is configured to track dependency calls. Auto-instrumentation covers HTTP and SQL; custom dependencies may need manual tracking.
