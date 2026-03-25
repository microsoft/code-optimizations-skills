# Check Profiler Status

Queries Application Insights for `ServiceProfilerSample` custom events to determine whether the Application Insights Profiler is actively collecting data.

## Query

```kql
customEvents
| where timestamp > ago(7d)
| where name == "ServiceProfilerSample"
| summarize SampleCount = count(), LastSample = max(timestamp)
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `resourceId` | — | Application Insights resource ID (full ARM path) or app ID (GUID). |
| `lookbackDays` | `7` | How many days to look back. Use `30` for a wider check. |

## Script

> ⚠️ Read [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md) before modifying this script.

```powershell
$resourceId = "<RESOURCE_ID>"
$lookbackDays = 7

$query = "customEvents | where timestamp > ago(${lookbackDays}d) | where name == 'ServiceProfilerSample' | summarize SampleCount = count(), LastSample = max(timestamp)"

$offset = if ($lookbackDays -le 1) { "P1D" } elseif ($lookbackDays -le 7) { "P7D" } else { "P30D" }

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

  $rows = $parsed.tables[0].rows
  $sampleCount = $rows[0][0]
  $lastSample = $rows[0][1]

  if ($sampleCount -eq 0) {
    Write-Host "No ServiceProfilerSample events found in the last $lookbackDays days."
    Write-Host "The Application Insights Profiler is NOT active or has not collected any data."
  } else {
    Write-Host "Profiler is ACTIVE."
    Write-Host "  Samples collected (last $lookbackDays days): $sampleCount"
    Write-Host "  Most recent sample: $lastSample"
  }
}
```

## Interpreting results

| Result | Meaning | Next step |
|--------|---------|-----------|
| Samples found | Profiler is enabled and collecting data | No action needed — proceed with `perf-optimization` skill |
| Zero samples | Profiler is not enabled or not collecting | Proceed with enablement steps in the `enable-profiler` skill |

## Widening the check

If the default 7-day window returns zero, try 30 days before concluding the profiler is disabled:

```powershell
$lookbackDays = 30
$offset = "P30D"
```
