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

The `ServiceProfilerContent` field contains a **full v1 trace location ID** (9 pipe-delimited fields) that includes the activity. See [trace-location-id-format.md](../../shared/trace-location-id-format.md) for the full format specification, field descriptions, and examples.

Example:

```
v1|westus2-ey2ahqc2dsyvq|d40e2d66-4e93-47c2-881e-71a758e09f54|8666f5e97d3e|1874|2026-03-20T21:55:35.9066175Z|/#1874/1/189/|2026-03-20T21:55:36.0751543Z|2026-03-20T21:55:39.0792972Z
```

The API accepts both the full 9-field format and the 6-field prefix format. Pass the full string as-is from `ServiceProfilerContent` — there is no need to truncate it.

See [download-trace-by-location.md](download-trace-by-location.md) for download instructions.

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

> ⚠️ Read [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md) before modifying this script. Key requirements: `--offset` is mandatory, use `--output json`, and flatten KQL to a single line.

```powershell
$appId = "<APP_ID>"
$triggerTime = "<TRIGGER_TIME>"  # ISO 8601 timestamp from the selected trace, e.g., "2026-03-20T21:56:12"
$timeSpan = "P7D"  # Match the time range used in the trace listing

# Single-line KQL — multi-line here-strings are silently truncated by `az`
$query = "customEvents | where name == 'ServiceProfilerSample' | where timestamp between (datetime('$triggerTime') - 2m .. datetime('$triggerTime') + 2m) | extend ctx = tostring(customDimensions.ServiceProfilerContext), content = tostring(customDimensions.ServiceProfilerContent) | project timestamp, ctx, content"

# --offset is critical: without it, az CLI defaults to a 1-hour window that overrides KQL time filters
$result = az monitor app-insights query --app $appId --analytics-query $query --offset $timeSpan --output json | ConvertFrom-Json

# Extract the first matching row
$tables = $result.tables
if ($tables -and $tables.Count -gt 0) {
    $rows = $tables[0].rows
    if ($rows -and $rows.Count -gt 0) {
        $row = $rows[0]
        $profilerContext = $row[1]
        $traceLocationId = $row[2]

        # Try to extract artifact ID from v2 context string
        $artifactId = $null
        if ($profilerContext -match '^v2\|[^|]*\|[^|]*\|[^|]*\|([^|]+)') {
            $artifactId = $matches[1]
        }

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
