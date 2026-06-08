# Query Failed Requests

Queries Application Insights for recent failed requests, grouped by operation name and HTTP status code. This surfaces the most frequent request failures to help identify reliability issues.

## Query

The KQL query filters for failed requests (non-2xx status codes or `success == false`), groups them by operation name and result code, and computes a trend indicator.

```kql
let lookback = ago(24h);
let midpoint = ago(12h);
requests
| where timestamp > lookback
| where success == false or toint(resultCode) >= 400
| summarize
    FailedCount = count(),
    FirstHalfCount = countif(timestamp < midpoint),
    SecondHalfCount = countif(timestamp >= midpoint),
    AvgDurationMs = round(avg(duration), 1),
    P95DurationMs = round(percentile(duration, 95), 1),
    LastSeen = max(timestamp),
    SampleOperationId = take_any(operation_Id),
    SampleRequestId = take_any(id)
    by name, resultCode, cloud_RoleName
| extend Trend = case(
    SecondHalfCount > FirstHalfCount * 1.5, "increasing",
    SecondHalfCount < FirstHalfCount * 0.5, "decreasing",
    "stable")
| order by FailedCount desc
| take 50
| project name, resultCode, cloud_RoleName, FailedCount, Trend, AvgDurationMs, P95DurationMs, LastSeen, SampleOperationId, SampleRequestId
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

$halfLookbackMinutes = [math]::Max(1, [math]::Floor($lookbackHours * 60 / 2))

# Build the KQL query as a single line to avoid here-string truncation issues.
$query = "let lookback = ago(${lookbackHours}h); let midpoint = ago(${halfLookbackMinutes}m); requests | where timestamp > lookback | where success == false or toint(resultCode) >= 400 | summarize FailedCount = count(), FirstHalfCount = countif(timestamp < midpoint), SecondHalfCount = countif(timestamp >= midpoint), AvgDurationMs = round(avg(duration), 1), P95DurationMs = round(percentile(duration, 95), 1), LastSeen = max(timestamp), SampleOperationId = take_any(operation_Id), SampleRequestId = take_any(id) by name, resultCode, cloud_RoleName | extend Trend = case(SecondHalfCount > FirstHalfCount * 1.5, 'increasing', SecondHalfCount < FirstHalfCount * 0.5, 'decreasing', 'stable') | order by FailedCount desc | take 50 | project name, resultCode, cloud_RoleName, FailedCount, Trend, AvgDurationMs, P95DurationMs, LastSeen, SampleOperationId, SampleRequestId"

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
    Write-Host "No failed requests found in the last $lookbackHours hours."
    Write-Host "Try widening the time range (e.g., `$lookbackHours = 168 for 7 days)."
  } else {
    Write-Host "Found $($rows.Count) failed request group(s) in the last $lookbackHours hours:`n"
    $i = 1
    foreach ($row in $rows) {
      $opName   = $row[0]
      $code     = $row[1]
      $role     = $row[2]
      $count    = $row[3]
      $trend    = $row[4]
      $avgDur   = $row[5]
      $p95Dur   = $row[6]
      $lastSeen = $row[7]
      $opId     = $row[8]
      $reqId    = $row[9]
      Write-Host "[$i] $opName | HTTP $code | Count: $count | Trend: $trend | Role: $role"
      Write-Host "    Avg: ${avgDur}ms | P95: ${p95Dur}ms | Last seen: $lastSeen"
      if ($opId) { Write-Host "    Sample Operation ID: $opId | Request ID: $reqId" }
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
| `name` | Operation name (e.g., `GET /api/users`, `POST /api/orders`) |
| `resultCode` | HTTP status code (e.g., `404`, `500`, `503`) |
| `cloud_RoleName` | The service/role that handled the request |
| `FailedCount` | Number of failed requests in the lookback window |
| `Trend` | Whether the failure rate is `increasing`, `decreasing`, or `stable` |
| `AvgDurationMs` | Average duration of failed requests in milliseconds |
| `P95DurationMs` | 95th percentile duration — high values may indicate timeouts |
| `LastSeen` | Most recent failure timestamp |
| `SampleOperationId` | A sample operation ID — use this with the `deep-analysis` skill for distributed trace investigation |
| `SampleRequestId` | A sample request ID for drilling into specific failures |

### What to do with the results

1. **Identify the most frequent failures** — Focus on entries with the highest `FailedCount`.
2. **Distinguish error classes** — 4xx errors (client errors) may indicate API misuse or missing resources; 5xx errors (server errors) indicate application bugs or infrastructure issues. Prioritize 5xx errors.
3. **Watch for increasing trends** — Failures with `increasing` trend may indicate a regression or emerging issue.
4. **Check duration anomalies** — High `P95DurationMs` on failed requests often indicates timeout-related failures (e.g., downstream service unavailable).
5. **Cross-reference with exceptions** — Failed 5xx requests often have associated exceptions. Compare with the exceptions query to find the root cause.

### No results?

If the query returns no rows:

- **Check `--offset`** — See [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md#offset-is-mandatory).
- **No failures in the time window** — The application may be running cleanly. Widen the time range to check historical patterns.
- **Verify data exists** — Run a simpler query: `requests | where success == false | summarize count()`.
- **Sampling in effect** — If adaptive sampling is enabled, `count()` counts sampled rows, not original events. For high-traffic applications, actual failure volume may be higher than reported. To get sampling-aware counts, replace `count()` with `sum(itemCount)` and `countif(...)` with `sumif(itemCount, ...)` in the KQL query.
