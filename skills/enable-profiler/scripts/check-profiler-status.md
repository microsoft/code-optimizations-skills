# Check Profiler Status

Queries Application Insights for both `ServiceProfilerIndex` and `ServiceProfilerSample` custom events to determine whether the Application Insights Profiler is enabled and actively collecting data.

The profiler emits two types of custom events:

| Event | Scope | Description |
|-------|-------|-------------|
| `ServiceProfilerIndex` | **Session** | One per profiling session. Indicates the profiler ran and uploaded a trace file. Contains session metadata (machine name, CPU/memory usage, profiler source). |
| `ServiceProfilerSample` | **Request** | One per sampled request within a session. Contains the trace location ID (`ServiceProfilerContent`) and request ID needed for hot path analysis. |

A `ServiceProfilerIndex` can exist **without** any `ServiceProfilerSample` events — this means the profiler session ran but captured zero matching requests (e.g., due to low traffic or no requests during the profiling window).

## Query

```kql
customEvents
| where timestamp > ago(7d)
| where name in ("ServiceProfilerIndex", "ServiceProfilerSample")
| summarize Count = count(), LastEvent = max(timestamp) by name
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

$query = "customEvents | where timestamp > ago(${lookbackDays}d) | where name in ('ServiceProfilerIndex', 'ServiceProfilerSample') | summarize Count = count(), LastEvent = max(timestamp) by name"

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
  $indexCount = 0; $indexLast = $null
  $sampleCount = 0; $sampleLast = $null

  foreach ($row in $rows) {
    if ($row[0] -eq "ServiceProfilerIndex") { $indexCount = $row[1]; $indexLast = $row[2] }
    if ($row[0] -eq "ServiceProfilerSample") { $sampleCount = $row[1]; $sampleLast = $row[2] }
  }

  if ($indexCount -eq 0 -and $sampleCount -eq 0) {
    Write-Host "No profiler events found in the last $lookbackDays days."
    Write-Host "The Application Insights Profiler is NOT enabled or has not collected any data."
  } elseif ($indexCount -gt 0 -and $sampleCount -eq 0) {
    Write-Host "Profiler sessions found, but NO request-level samples."
    Write-Host "  Sessions (ServiceProfilerIndex): $indexCount (last: $indexLast)"
    Write-Host "  Samples (ServiceProfilerSample): 0"
    Write-Host "The profiler IS running but is not capturing request samples."
    Write-Host "Possible causes: low traffic, no requests during profiling windows, or trigger thresholds not met."
  } else {
    Write-Host "Profiler is ACTIVE."
    Write-Host "  Sessions (ServiceProfilerIndex): $indexCount (last: $indexLast)"
    Write-Host "  Samples (ServiceProfilerSample): $sampleCount (last: $sampleLast)"
  }
}
```

## Interpreting results

| ServiceProfilerIndex | ServiceProfilerSample | Meaning | Next step |
|---|---|---|---|
| Found | Found | Profiler is enabled and capturing request-level data | No action needed — proceed with `perf-optimization` skill |
| Found | **Zero** | Profiler is running sessions but not capturing individual requests | Check traffic volume, ensure requests are hitting the app during profiling windows, verify trigger thresholds. Do NOT recommend enabling the profiler — it is already enabled. |
| **Zero** | **Zero** | Profiler is not enabled or has never run | Proceed with enablement steps in the `enable-profiler` skill |

> **Note:** `ServiceProfilerIndex` without `ServiceProfilerSample` is common when traffic is low or when the profiler ran during a period with no incoming requests. The profiler still uploaded a trace file (the session), but no individual request activities were matched to it.

## Widening the check

If the default 7-day window returns zero, try 30 days before concluding the profiler is disabled:

```powershell
$lookbackDays = 30
$offset = "P30D"
```
