# Trace Location ID Format

The trace location ID is a pipe-delimited v1 string that uniquely identifies a profiler trace or a specific activity within a trace session. It appears in the `ServiceProfilerContent` field of `ServiceProfilerSample` custom events in Application Insights.

## Prefix form (6 fields) — for downloading a full trace session

```
v1|{stampId}|{appId}|{machineName}|{processId}|{etlFileSessionId}
```

## Full form (9 fields) — for a specific activity within a trace session

```
v1|{stampId}|{appId}|{machineName}|{processId}|{etlFileSessionId}|{activityId}|{activityStartTime}|{activityStopTime}
```

## Fields

| Field | Description | Example |
|---|---|---|
| `v1` | Version identifier (always `v1` for this format) | `v1` |
| `stampId` | The stamp/deployment identifier for the Application Insights backend | `westus2-ey2ahqc2dsyvq` |
| `appId` | The Application Insights app ID (GUID, lowercase with hyphens) | `d40e2d66-4e93-47c2-881e-71a758e09f54` |
| `machineName` | The machine or container instance name (maps to `roleInstance` from the trace listing) | `8666f5e97d3e` |
| `processId` | The process ID (integer, must be non-zero; use `1` if unknown) | `1874` |
| `etlFileSessionId` | The profiling session start time in UTC (ISO 8601 format, maps to `triggerTime` from the trace listing) | `2026-03-20T21:41:35.8314098Z` |
| `activityId` | *(optional)* The activity path within the trace | `/#1874/1/189/` |
| `activityStartTime` | *(optional)* Activity start time in UTC (ISO 8601) | `2026-03-20T21:55:36.0751543Z` |
| `activityStopTime` | *(optional)* Activity stop time in UTC (ISO 8601) | `2026-03-20T21:55:39.0792972Z` |

## Source

The trace location ID comes from `ServiceProfilerContent` in the `ServiceProfilerSample` custom event:

```kql
customEvents
| where name == "ServiceProfilerSample"
| extend traceLocationId = tostring(customDimensions['ServiceProfilerContent'])
```

## Examples

Prefix form:
```
v1|westus2-ey2ahqc2dsyvq|d40e2d66-4e93-47c2-881e-71a758e09f54|8666f5e97d3e|1|2026-03-20T21:41:35.8314098Z
```

Full form (from `ServiceProfilerContent`):
```
v1|westus2-ey2ahqc2dsyvq|d40e2d66-4e93-47c2-881e-71a758e09f54|8666f5e97d3e|1874|2026-03-20T21:55:35.9066175Z|/#1874/1/189/|2026-03-20T21:55:36.0751543Z|2026-03-20T21:55:39.0792972Z
```

## Indexing

The last two pipe-separated segments (indices `partCount - 2` and `partCount - 1`) are the request start and end times — this holds for both prefix and full forms.

## API usage

The API accepts both the full 9-field format and the 6-field prefix format. When the value comes from `ServiceProfilerContent`, pass it as-is — there is no need to truncate it. The trace location ID must be URL-encoded when used in query parameters:

```powershell
$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
```
