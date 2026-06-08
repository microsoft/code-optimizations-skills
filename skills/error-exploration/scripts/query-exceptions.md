# Query Exceptions

Queries Application Insights for recent exceptions, grouped by type and method. This surfaces the most frequent and impactful exceptions to help prioritize error investigation.

## Query

The KQL query aggregates exceptions by type and calling method, counts occurrences, and computes a simple trend indicator by comparing the first and second halves of the lookback window.

```kql
let lookback = ago(24h);
let midpoint = ago(12h);
exceptions
| where timestamp > lookback
| extend ExceptionMethod = iif(isempty(outerMethod), method, outerMethod)
| summarize
    TotalCount = count(),
    FirstHalfCount = countif(timestamp < midpoint),
    SecondHalfCount = countif(timestamp >= midpoint),
    LastSeen = max(timestamp),
    SampleMessage = take_any(outerMessage),
    SampleOperationId = take_any(operation_Id),
    TopOperations = make_set(operation_Name, 5)
    by type, ExceptionMethod, problemId, cloud_RoleName
| extend Trend = case(
    SecondHalfCount > FirstHalfCount * 1.5, "increasing",
    SecondHalfCount < FirstHalfCount * 0.5, "decreasing",
    "stable")
| order by TotalCount desc
| take 50
| project type, ExceptionMethod, problemId, cloud_RoleName, TotalCount, Trend, LastSeen, SampleMessage, SampleOperationId, TopOperations
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
$query = "let lookback = ago(${lookbackHours}h); let midpoint = ago(${halfLookback}h); exceptions | where timestamp > lookback | extend ExceptionMethod = iif(isempty(outerMethod), method, outerMethod) | summarize TotalCount = count(), FirstHalfCount = countif(timestamp < midpoint), SecondHalfCount = countif(timestamp >= midpoint), LastSeen = max(timestamp), SampleMessage = take_any(outerMessage), SampleOperationId = take_any(operation_Id), TopOperations = make_set(operation_Name, 5) by type, ExceptionMethod, problemId, cloud_RoleName | extend Trend = case(SecondHalfCount > FirstHalfCount * 1.5, 'increasing', SecondHalfCount < FirstHalfCount * 0.5, 'decreasing', 'stable') | order by TotalCount desc | take 50 | project type, ExceptionMethod, problemId, cloud_RoleName, TotalCount, Trend, LastSeen, SampleMessage, SampleOperationId, TopOperations"

# --offset is MANDATORY: without it, the CLI applies a 1-hour server-side time
# filter regardless of any KQL ago() in the query. Use ISO 8601 duration format.
# --output json is required: --output table silently drops results for join queries.
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
    Write-Host "No exceptions found in the last $lookbackHours hours."
    Write-Host "Try widening the time range (e.g., `$lookbackHours = 168 for 7 days)."
  } else {
    Write-Host "Found $($rows.Count) exception group(s) in the last $lookbackHours hours:`n"
    $i = 1
    foreach ($row in $rows) {
      $exType     = $row[0]
      $exMethod   = $row[1]
      $problemId  = $row[2]
      $role       = $row[3]
      $count      = $row[4]
      $trend      = $row[5]
      $lastSeen   = $row[6]
      $msg        = $row[7]
      $opId       = $row[8]
      # Truncate long messages for display
      if ($msg -and $msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
      Write-Host "[$i] $exType | Count: $count | Trend: $trend | Role: $role"
      Write-Host "    Method: $exMethod"
      Write-Host "    Problem ID: $problemId | Last seen: $lastSeen"
      if ($opId) { Write-Host "    Sample Operation ID: $opId" }
      if ($msg) { Write-Host "    Message: $msg" }
      Write-Host ""
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
| `type` | Exception type (e.g., `System.NullReferenceException`, `System.TimeoutException`) |
| `ExceptionMethod` | The method where the exception was thrown (outer method preferred) |
| `problemId` | Application Insights problem ID — groups related exception occurrences |
| `cloud_RoleName` | The service/role that threw the exception |
| `TotalCount` | Number of occurrences in the lookback window |
| `Trend` | Whether the exception rate is `increasing`, `decreasing`, or `stable` (comparing first vs. second half of the window) |
| `LastSeen` | Most recent occurrence timestamp |
| `SampleMessage` | A sample exception message for context |
| `SampleOperationId` | A sample operation ID — use this with the `deep-analysis` skill for distributed trace investigation |
| `TopOperations` | Up to 5 distinct operation names affected by this exception type |

### What to do with the results

1. **Identify the most frequent exceptions** — Focus on the top entries with the highest `TotalCount`.
2. **Watch for increasing trends** — Exceptions with `increasing` trend may indicate a regression or growing issue.
3. **Note the problem IDs** — These can be used to drill into specific exception groups in the Azure portal.
4. **Cross-reference with failed requests** — Compare exception types with the failed requests query to see which exceptions are causing user-facing failures.

### No results?

If the query returns no rows:

- **Check `--offset`** — The most common cause of empty results is a missing or too-narrow `--offset`. See [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md#offset-is-mandatory).
- **No exceptions in the time window** — This is actually good news! The application may not be throwing exceptions. Widen the time range to check historical patterns.
- **Verify data exists** — Run a simpler query to confirm data is present: `exceptions | summarize count()`.
- **Check telemetry configuration** — Ensure the application is configured to send exception telemetry to Application Insights.
