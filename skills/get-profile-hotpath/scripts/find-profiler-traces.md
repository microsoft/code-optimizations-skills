# Find Profiler Traces

If the user doesn't have a specific trace location ID, query the Application Insights resource for recent profiler samples.

This requires the Application Insights **resource ID** (not the app ID). Use the `az monitor app-insights query` command:

## Basic query (traces with correlated request operations)

```powershell
az monitor app-insights query \
  --apps "<RESOURCE_ID>" \
  --analytics-query "
    let traces = customEvents
    | where name == 'ServiceProfilerSample'
    | extend spc = tostring(customDimensions['ServiceProfilerContent'])
    | extend parts = split(spc, '|')
    | extend partCount = array_length(parts)
    | extend requestStartTime = todatetime(parts[partCount - 2])
    | extend requestEndTime = todatetime(parts[partCount - 1])
    | extend traceDurationMs = datetime_diff('millisecond', requestEndTime, requestStartTime)
    | extend machineName = tostring(parts[3])
    | extend activityPath = tostring(parts[partCount - 3])
    | project timestamp, spc, requestStartTime, requestEndTime, traceDurationMs, machineName, activityPath;
    traces
    | join kind=leftouter (
        requests
        | project reqTimestamp = timestamp, operationName = name, reqUrl = url, reqDurationMs = duration, reqStart = timestamp, reqEnd = timestamp + totimespan(duration * 10000)
    ) on \$left.requestStartTime >= \$right.reqStart and \$left.requestEndTime <= \$right.reqEnd
    | project timestamp, spc, operationName, reqUrl, traceDurationMs, reqDurationMs, machineName, activityPath
    | order by timestamp desc
    | take 10
  " \
  --output json
```

If the join produces too many or too few results (due to timestamp precision), use this simpler two-step approach:

## Alternative: separate queries

**Step 1** — List recent traces:

```powershell
az monitor app-insights query \
  --apps "<RESOURCE_ID>" \
  --analytics-query "
    customEvents
    | where name == 'ServiceProfilerSample'
    | extend spc = tostring(customDimensions['ServiceProfilerContent'])
    | extend parts = split(spc, '|')
    | extend partCount = array_length(parts)
    | extend requestStartTime = todatetime(parts[partCount - 2])
    | extend requestEndTime = todatetime(parts[partCount - 1])
    | extend traceDurationMs = datetime_diff('millisecond', requestEndTime, requestStartTime)
    | extend machineName = tostring(parts[3])
    | project timestamp, spc, requestStartTime, requestEndTime, traceDurationMs, machineName
    | order by timestamp desc
    | take 10
  " \
  --output json
```

**Step 2** — Look up which requests were active during a specific trace's time window:

```powershell
az monitor app-insights query \
  --apps "<RESOURCE_ID>" \
  --analytics-query "
    requests
    | where timestamp >= datetime('<requestStartTime>') and timestamp <= datetime('<requestEndTime>')
    | project timestamp, name, url, duration
    | order by timestamp desc
  " \
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

## Presenting traces to the user

Present the traces to the user with: timestamp, correlated operation name (if available), estimated duration (endTime − startTime from ServiceProfilerContent), machine name, and activity path. This gives enough context to pick the right trace without downloading each one.
