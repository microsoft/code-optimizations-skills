# Query Slow Requests with Profiler Traces

Queries Application Insights for recent slow requests that have associated profiler trace data (`ServiceProfilerSample` custom events). This helps identify which slow operations have profiler coverage and are good candidates for deeper investigation.

## Query

The KQL query joins `requests` with `customEvents` that contain profiler sample metadata, surfacing slow requests that have profiler traces available for analysis.

```kql
let lookback = ago(24h);
let profilerSamples = (customEvents
| where timestamp > lookback
| where name == "ServiceProfilerSample"
| extend RequestId_ = tostring(customDimensions.RequestId));
requests
| where timestamp > lookback
| join kind=inner profilerSamples on $left.id == $right.RequestId_
| order by duration desc
| project timestamp, name, duration, resultCode, id, cloud_RoleName, url, performanceBucket
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

# Build the KQL query as a single line to avoid here-string truncation issues.
# Note: $left and $right are KQL keywords, not PowerShell variables — use backtick
# escaping (`$left, `$right) when inside double-quoted PowerShell strings.
$query = "let lookback = ago(${lookbackHours}h); let profilerSamples = (customEvents | where timestamp > lookback | where name == 'ServiceProfilerSample' | extend RequestId_ = tostring(customDimensions.RequestId)); requests | where timestamp > lookback | join kind=inner profilerSamples on `$left.id == `$right.RequestId_ | order by duration desc | project timestamp, name, duration, resultCode, id, cloud_RoleName, url, performanceBucket"

# --offset is MANDATORY: without it, the CLI applies a 1-hour server-side time
# filter regardless of any KQL ago() in the query. Use ISO 8601 duration format.
# --output json is required: --output table silently drops results for join queries.
$offset = if ($lookbackHours -le 24) { "P1D" } elseif ($lookbackHours -le 168) { "P7D" } else { "P30D" }

$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset $offset `
  --output json 2>&1

if (-not $result -or $result -match "ERROR" -or $result -match "BadArgumentError") {
  Write-Host "ERROR: Query failed. Output:"
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
    Write-Host "No slow requests with profiler traces found in the last $lookbackHours hours."
    Write-Host "Try widening the time range (e.g., `$lookbackHours = 168 for 7 days)."
  } else {
    Write-Host "Found $($rows.Count) slow request(s) with profiler traces (last $lookbackHours hours):`n"
    $i = 1
    foreach ($row in $rows) {
      $ts       = $row[0]
      $opName   = $row[1]
      $dur      = [math]::Round([double]$row[2], 1)
      $code     = $row[3]
      $reqId    = $row[4]
      $role     = $row[5]
      $url      = $row[6]
      $bucket   = $row[7]
      Write-Host "[$i] $opName | ${dur}ms ($bucket) | HTTP $code | Role: $role"
      Write-Host "    ID: $reqId | $ts"
      $i++
    }
  }
}
```

### Adjusting the time range

Change `$lookbackHours` to widen or narrow the search window. The `$offset` variable is computed automatically to match, but you can also set it explicitly. Use valid ISO 8601 durations only — see [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md#offset-is-mandatory).

```powershell
# Last 6 hours
$lookbackHours = 6
$offset = "P1D"       # P1D covers up to 24h

# Last 7 days
$lookbackHours = 168
$offset = "P7D"

# Last 30 days
$lookbackHours = 720
$offset = "P30D"
```

### Reading the results

The script parses the JSON response and displays a formatted summary. Each result row contains:

| Column | Description |
|--------|-------------|
| `timestamp` | When the request occurred |
| `name` | Operation name (e.g., `GET /api/weather`) |
| `duration` | Request duration in milliseconds — sorted descending (slowest first) |
| `resultCode` | HTTP status code |
| `id` | Request ID — use this to locate the profiler trace for deeper analysis |
| `cloud_RoleName` | The service/role that handled the request |
| `url` | Full request URL |
| `performanceBucket` | Duration bucket (e.g., `<250ms`, `250ms-500ms`, `1s-3s`) |

### What to do with the results

1. **Identify the slowest requests** — Focus on the top entries with the highest `duration` values.
2. **Note the operation names** — These are the operations worth investigating with Code Optimization recommendations and profiler hot path analysis.
3. **Use the request `id`** — Pass it to the `get-profile-hotpath` skill to retrieve the full call tree for a specific slow request.
4. **Compare across roles** — If multiple `cloud_RoleName` values appear, determine which service tier is contributing the most latency.

### No results?

If the query returns no rows:

- **Check `--offset`** — The most common cause of empty results is a missing or too-narrow `--offset`. The `az monitor app-insights query` CLI applies a server-side time filter that **overrides** KQL `ago()`. See [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md#offset-is-mandatory).
- **No profiler traces in the time window** — The Application Insights Profiler may not have been active or may not have captured samples. Widen the time range (e.g., 7 or 30 days).
- **Profiler not enabled** — Verify that Application Insights Profiler is enabled on the target resource.
- **Low traffic** — The profiler samples only a fraction of requests. If traffic is low, fewer requests will have associated traces.
- **Verify data exists** — Run a simpler query to confirm data is present: `requests | summarize count()` and `customEvents | where name == 'ServiceProfilerSample' | summarize count()`.

When no profiler samples are available, proceed directly to the Code Optimization recommendations step — those rely on aggregated profiler data and may still return results even if individual samples aren't visible in the query.
