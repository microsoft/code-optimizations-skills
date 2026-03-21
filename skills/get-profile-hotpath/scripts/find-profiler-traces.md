# Find Profiler Traces

If the user doesn't have a specific trace location ID, query the Application Insights resource for recent profiler samples.

This requires the Application Insights **resource ID** (not the app ID). Use the `az monitor app-insights query` command:

> **Important — `--offset` is required:** The `az monitor app-insights query` CLI defaults to a 1-hour window that **overrides** any `ago()` or time-based filters in the KQL query. Always pass `--offset` matching your desired lookback period (e.g., `P7D` for 7 days, `P1D` for 1 day). Without this parameter, queries for traces older than 1 hour will silently return empty results.

> **Important — read [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md) before modifying this script.** The `--offset` parameter, `--output json`, and single-line KQL are all required for correct results.

## Basic query (traces with correlated request operations)

```powershell
# Adjust the lookback period to match the investigation window (e.g., P7D = 7 days, P1D = 1 day)
$resourceId = "<RESOURCE_ID>"
$timeSpan = "P7D"

# Build the KQL query as a single line to avoid here-string truncation issues.
# Note: $left and $right are KQL keywords, not PowerShell variables — use backtick
# escaping (`$left, `$right) when inside double-quoted PowerShell strings.
$query = "let traces = customEvents | where name == 'ServiceProfilerSample' | extend spc = tostring(customDimensions['ServiceProfilerContent']) | extend parts = split(spc, '|') | extend partCount = array_length(parts) | extend requestStartTime = todatetime(parts[partCount - 2]) | extend requestEndTime = todatetime(parts[partCount - 1]) | extend traceDurationMs = datetime_diff('millisecond', requestEndTime, requestStartTime) | extend machineName = tostring(parts[3]) | extend activityPath = tostring(parts[partCount - 3]) | project timestamp, spc, requestStartTime, requestEndTime, traceDurationMs, machineName, activityPath; traces | join kind=leftouter (requests | project reqTimestamp = timestamp, operationName = name, reqUrl = url, reqDurationMs = duration, reqStart = timestamp, reqEnd = timestamp + totimespan(duration * 10000)) on `$left.requestStartTime >= `$right.reqStart and `$left.requestEndTime <= `$right.reqEnd | project timestamp, spc, operationName, reqUrl, traceDurationMs, reqDurationMs, machineName, activityPath | order by timestamp desc | take 10"

# --offset is MANDATORY: without it, the CLI applies a 1-hour server-side time
# filter regardless of any KQL ago() in the query. Use ISO 8601 duration format.
# --output json is required: --output table silently drops results for join queries.
az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset $timeSpan `
  --output json
```

If the join produces too many or too few results (due to timestamp precision), use this simpler two-step approach:

## Alternative: separate queries

**Step 1** — List recent traces:

```powershell
# Adjust the lookback period to match the investigation window (e.g., P7D = 7 days, P1D = 1 day)
$resourceId = "<RESOURCE_ID>"
$timeSpan = "P7D"

# Single-line KQL to avoid here-string truncation issues.
$query = "customEvents | where name == 'ServiceProfilerSample' | extend spc = tostring(customDimensions['ServiceProfilerContent']) | extend parts = split(spc, '|') | extend partCount = array_length(parts) | extend requestStartTime = todatetime(parts[partCount - 2]) | extend requestEndTime = todatetime(parts[partCount - 1]) | extend traceDurationMs = datetime_diff('millisecond', requestEndTime, requestStartTime) | extend machineName = tostring(parts[3]) | project timestamp, spc, requestStartTime, requestEndTime, traceDurationMs, machineName | order by timestamp desc | take 10"

az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset $timeSpan `
  --output json
```

**Step 2** — Look up which requests were active during a specific trace's time window:

```powershell
# Use the same lookback period as step 1
$resourceId = "<RESOURCE_ID>"
$timeSpan = "P7D"

# Replace <requestStartTime> and <requestEndTime> with values from the trace's ServiceProfilerContent.
$query = "requests | where timestamp >= datetime('<requestStartTime>') and timestamp <= datetime('<requestEndTime>') | project timestamp, name, url, duration | order by timestamp desc"

az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset $timeSpan `
  --output json
```

Replace `<requestStartTime>` and `<requestEndTime>` with values extracted from the trace's `ServiceProfilerContent`.

## ServiceProfilerContent format

Each result contains a `customDimensions` JSON string with a `ServiceProfilerContent` field. That value is the **trace location ID**.

Example `ServiceProfilerContent` value:

```
v1|westus2-ey2ahqc2dsyvq|a1163c00-895c-42ee-9c55-4c527742f747|weatherapp-6f5766589f-dkxzk|1|2026-03-18T21:00:39.1061639Z|/#1/1/61035/|2026-03-18T21:00:43.1159071Z|2026-03-18T21:00:43.1310982Z
```

The format is: `v1|{stampId}|{dataCube}|{machineName}|{processId}|{sessionId}|{activityPath}|{requestStartTime}|{requestEndTime}`

The last two pipe-separated segments before the final segment are the request start and end times (for both v1 and v2 formats). Use `partCount - 2` and `partCount - 1` indexing to extract them reliably.

## Selecting the right trace

When multiple traces are available, use these criteria to pick the best one:

- **For CPU issues identified by Code Optimizations**: prefer longer-duration traces (they contain more CPU samples and give a clearer picture of hot paths). Short traces (~1 second) may represent simple sleep/idle requests with minimal CPU activity.
- **Match timestamps to findings**: align the trace timestamps with the time range of the Code Optimization findings or the performance incident being investigated.
- **Match machine/role**: if the Code Optimization recommendation includes a `roleName`, prefer traces from the same machine or role instance.
- **Consider the operation**: if the correlated request operation (e.g., `GET /HighCPUAsync/4000`) matches the endpoint under investigation, that trace is more relevant than one from an unrelated endpoint (e.g., `GET /Sleep/1000`).

## Filtering by operation name

When Code Optimizations has identified a specific bottleneck operation (e.g., `HighCPUAsync`), you can narrow the trace list to traces that overlap with requests to that endpoint. Use the two-step approach above (step 1 for traces, step 2 for requests) and match the request `name` field against the operation identified in the Code Optimization recommendation's `parentFunction` or `function` field.

Alternatively, add a duration filter to the basic query to focus on longer traces more likely to contain the target operation:

```kql
| where traceDurationMs > 2000
```

This is especially useful for CPU investigations where longer traces contain more samples and give clearer hot paths.

## Presenting traces to the user

Present the traces to the user with: timestamp, correlated operation name (if available), estimated duration (endTime − startTime from ServiceProfilerContent), machine name, and activity path. This gives enough context to pick the right trace without downloading each one.
