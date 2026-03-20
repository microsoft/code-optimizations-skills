# Resolve Trace Identifiers

Query Application Insights `customEvents` to resolve the **artifact ID** and/or **trace location ID** for a profiler trace. Use this when the trace listing returns `artifactId: null` — the identifiers needed for download can often be found in the `ServiceProfilerSample` telemetry.

## What this resolves

The `ServiceProfilerSample` custom event contains two fields in `customDimensions`:

| Field | Contains | Used for |
|---|---|---|
| `ServiceProfilerContext` | A v2 pipe-delimited string that embeds the **artifact ID** (5th field, index 4) | Preferred — enables download via the standard artifact ID endpoint |
| `ServiceProfilerContent` | The **v1 trace location ID** | Fallback — enables download via the trace location ID endpoint |

### Artifact ID extraction from `ServiceProfilerContext`

The v2 string format:

```
v2|{stamp}|{appId}|Profile|{artifactId}||{pid}|{path}|{startTime}|{endTime}
```

Example:

```
v2|westus2-ey2ahqc2dsyvq|44efb156-2036-42f6-a074-8516ca273c21|Profile|a075ba6a3c054da895662a9c05def54a||5960|/#5960/1/6613/1/|2026-03-20T22:16:01.2093910Z|2026-03-20T22:16:03.2256929Z
```

The artifact ID is `a075ba6a3c054da895662a9c05def54a` (5th pipe-delimited field, zero-based index 4).

### Trace location ID from `ServiceProfilerContent`

The v1 string format:

```
v1|{stampId}|{appId}|{machineName}|{processId}|{etlFileSessionId}
```

See [download-trace-by-location.md](download-trace-by-location.md) for full format details.

## KQL query

```kql
customEvents
| where name == "ServiceProfilerSample"
| where timestamp >= ago({timeSpan})
| extend TraceLocationId = tostring(customDimensions.ServiceProfilerContent)
| extend ProfilerContext = tostring(customDimensions.ServiceProfilerContext)
| extend ArtifactId = extract("^v2\\|[^|]*\\|[^|]*\\|[^|]*\\|([^|]+)", 1, ProfilerContext)
| project timestamp, TraceLocationId, ArtifactId, ProfilerContext
```

To match a specific trace from the listing, add filters:

```kql
| where timestamp between (datetime({triggerTime}) - 1m .. datetime({triggerTime}) + 1m)
```

## PowerShell script

```powershell
$appId = "<APP_ID>"
$triggerTime = "<TRIGGER_TIME>"  # ISO 8601 timestamp from the selected trace, e.g., "2026-03-20T22:16:01.2093910Z"
$timeSpan = "P7D"  # Match the time range used in the trace listing

# Build the KQL query, filtering around the selected trace's trigger time
$query = @"
customEvents
| where name == 'ServiceProfilerSample'
| where timestamp between (datetime('$triggerTime') - 2m .. datetime('$triggerTime') + 2m)
| extend TraceLocationId = tostring(customDimensions.ServiceProfilerContent)
| extend ProfilerContext = tostring(customDimensions.ServiceProfilerContext)
| extend ArtifactId = extract('v2\\\\|[^|]*\\\\|[^|]*\\\\|[^|]*\\\\|([^|]+)', 1, ProfilerContext)
| project timestamp, TraceLocationId, ArtifactId
"@

$result = az monitor app-insights query --app $appId --analytics-query $query --output json | ConvertFrom-Json

# Extract the first matching row
$tables = $result.tables
if ($tables -and $tables.Count -gt 0) {
    $rows = $tables[0].rows
    if ($rows -and $rows.Count -gt 0) {
        $row = $rows[0]
        $traceLocationId = $row[1]
        $artifactId = $row[2]

        if ($artifactId) {
            Write-Host "Resolved Artifact ID: $artifactId"
            Write-Host "Use the standard artifact download endpoint (download-trace.md)."
        }
        if ($traceLocationId) {
            Write-Host "Resolved Trace Location ID: $traceLocationId"
            Write-Host "Use the trace location download endpoint (download-trace-by-location.md)."
        }
    } else {
        Write-Host "No ServiceProfilerSample events found for trigger time: $triggerTime"
    }
} else {
    Write-Host "Query returned no results."
}
```

## Decision logic

After running this script:

1. **If `ArtifactId` is resolved** → use the standard artifact ID download method ([download-trace.md](download-trace.md))
2. **If only `TraceLocationId` is resolved** → use the trace location ID download method ([download-trace-by-location.md](download-trace-by-location.md))
3. **If neither is resolved** → ask the user for the trace location ID or artifact ID manually
