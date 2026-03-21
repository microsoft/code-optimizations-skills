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

```powershell
$resourceId = "<RESOURCE_ID>"
$lookbackHours = 24  # Adjust: 1, 6, 24, 48, 168 (7 days), 720 (30 days)

$query = @'
let lookback = ago({LOOKBACK_HOURS}h);
let profilerSamples = (customEvents
| where timestamp > lookback
| where name == "ServiceProfilerSample"
| extend RequestId_ = tostring(customDimensions.RequestId));
requests
| where timestamp > lookback
| join kind=inner profilerSamples on $left.id == $right.RequestId_
| order by duration desc
| project timestamp, name, duration, resultCode, id, cloud_RoleName, url, performanceBucket
'@

$query = $query.Replace("{LOOKBACK_HOURS}", $lookbackHours.ToString())

az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query $query `
  --output table
```

### Adjusting the time range

Change `$lookbackHours` to widen or narrow the search window:

```powershell
# Last 6 hours
$lookbackHours = 6

# Last 7 days
$lookbackHours = 168

# Last 30 days
$lookbackHours = 720
```

### Reading the results

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

- **No profiler traces in the time window** — The Application Insights Profiler may not have been active or may not have captured samples. Widen the time range (e.g., 7 or 30 days).
- **Profiler not enabled** — Verify that Application Insights Profiler is enabled on the target resource.
- **Low traffic** — The profiler samples only a fraction of requests. If traffic is low, fewer requests will have associated traces.

When no profiler samples are available, proceed directly to the Code Optimization recommendations step — those rely on aggregated profiler data and may still return results even if individual samples aren't visible in the query.
