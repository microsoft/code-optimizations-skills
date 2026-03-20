---
name: perf-optimization
description: Guide for analyzing performance issues based on profiler and code optimizations, including CPU, latency, and throughput. Use this when asked to investigate performance bottlenecks or optimize application performance.
---

# Analysis

When asked to analyze performance issues based on profiler data, follow these steps:

1. **Check investigation notes** — Check whether `investigation-notes.md` exists in the working directory. If it does, read it for existing Application Insights resource details (resource ID, app ID, subscription, resource group). Present any found values to the user and ask whether to reuse them or provide new ones. See [Investigation Notes](../shared/investigation-notes.md) for the file format and rules.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in [Identify Application Insights Resource](references/identify-appinsights-resource.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values.

3. **Query logs to find operations worth investigating** — Query the `requests`, `dependencies`, and `performanceCounters` tables to surface slow endpoints, high-latency dependencies, and resource pressure. Use this data to decide which specific operations deserve deeper profiler analysis.

4. **Query Code Optimizations data** — Use `applicationinsights_recommendation_list` to get AI-powered recommendations based on profiler data. This is cheap and may already point to the right methods.

5. **Fetch profiler hot path for targeted operations** — Once you've identified the most impactful operations from steps 3–4, use the `get-profile-hotpath` skill to retrieve the call tree and hot path for specific traces. This is an expensive operation — only invoke it for operations that warrant deep investigation. See [Leveraging Profiler Hot Path Data](#leveraging-profiler-hot-path-data) for details.

6. **Putting data together to identify performance improvement opportunities** — Correlate the hot path bottlenecks with code optimization recommendations and telemetry data to prioritize fixes.

7. **Try provide code edits to optimize the performance** — When source code is available, suggest concrete code changes targeting the methods identified in the hot path.

## MCP Tools

The following MCP tools are available for querying Azure Monitor and Application Insights data. Always include the `subscription` parameter (extracted from the resource ID) in every call.

### azure-perf-monitoring-subscription_list

List all Azure subscriptions accessible to the current account. Use this first if the subscription ID is unknown.

### azure-perf-monitoring-group_list

List all resource groups in a subscription. Use this to discover resource groups when the user hasn't specified one.

- Required: `subscription`

### azure-perf-monitoring-applicationinsights

This tool provides access to Application Insights-specific commands. Use the `command` parameter to select a sub-command and wrap arguments in `parameters`.

#### applicationinsights_recommendation_list

List Code Optimization Recommendations from Application Insights based on profiler data. Returns actionable recommendations for improving application performance. Can be scoped to a specific resource group.

- Optional: `subscription`, `resource-group`, `tenant`, `auth-method`

### azure-perf-monitoring-monitor

This is the primary tool for querying Application Insights data. Use the `command` parameter to select a sub-command and wrap arguments in `parameters`.

#### monitor_resource_log_query

Query logs for a **specific** Azure resource using KQL. This is the main command for querying Application Insights tables.

- Required: `resource-id`, `table`, `query`, `subscription`
- Optional: `hours`, `limit`

**Key tables and example queries:**

| Table | Purpose | Example KQL |
|---|---|---|
| `requests` | HTTP request performance | `requests \| where duration > 1000 \| summarize avg(duration), percentile(duration, 95), count() by name, resultCode \| order by avg_duration desc` |
| `customEvents` | Profiler samples & code optimization insights | `customEvents \| where name == 'ServiceProfilerSample' or name == 'ServiceProfilerIndex' \| project timestamp, customDimensions` |
| `performanceCounters` | CPU, memory, and process metrics | `performanceCounters \| summarize avg(value) by name, category \| order by avg_value desc` |
| `dependencies` | External dependency calls (DB, HTTP, etc.) | `dependencies \| summarize avg(duration), percentile(duration, 95), count() by name, type, target \| order by avg_duration desc` |
| `traces` | Application log messages | `traces \| where message contains 'profiler' or message contains 'slow' \| project timestamp, message, severityLevel \| order by timestamp desc` |
| `customMetrics` | Custom metric values | `customMetrics \| summarize avg(value), count() by name \| order by avg_value desc` |

#### monitor_workspace_log_query

Query logs across an **entire** Log Analytics workspace. Use when the user wants workspace-wide queries rather than a specific resource.

- Required: `resource-group`, `workspace`, `table`, `query`
- Optional: `hours`, `limit`, `subscription`

#### monitor_metrics_query

Query Azure Monitor metrics (time-series data) for a resource.

- Required: `resource`, `metric-names`, `metric-namespace`
- Optional: `resource-group`, `resource-type`, `start-time`, `end-time`, `interval`, `aggregation`, `subscription`

#### monitor_metrics_definitions

List available metric definitions for an Azure resource. Use this to discover which metrics can be queried.

- Required: `resource`
- Optional: `resource-group`, `resource-type`, `subscription`

#### monitor_workspace_list

List all Log Analytics workspaces in a subscription.

- Optional: `subscription`

#### monitor_table_list

List all tables in a Log Analytics workspace.

- Required: `resource-group`, `workspace`, `table-type`
- Optional: `subscription`

#### monitor_table_type_list

List available table types in a Log Analytics workspace.

- Required: `resource-group`, `workspace`
- Optional: `subscription`

## Leveraging Profiler Hot Path Data

The `get-profile-hotpath` skill provides method-level profiler trace data. Invoke it to get the hot path call tree for a specific profiler trace, then use the results here for deeper analysis.

### When to use the hot path data

- Fetch the hot path only **after** log queries and code optimization recommendations have identified specific operations worth investigating — it is an expensive operation per request.
- Use it to get method-level detail on **targeted** slow operations already surfaced by telemetry.
- Cross-reference hot path methods with Code Optimization recommendations for actionable fixes.

### How to use the hot path results

The `get-profile-hotpath` skill returns a call tree with timing data. Use it as follows:

1. **Identify the dominant method**: The hot path highlights the most expensive execution path. Focus optimization efforts on the methods consuming the most inclusive time (highest `Values.Metric`).
2. **Classify the bottleneck type**: Check `TotalCpuTime`, `TotalAwaitTime`, and `TotalBlockedTime` from the root tree to determine if the issue is CPU-bound, I/O-bound, or contention-bound.
3. **Correlate with telemetry**: Query the `requests` and `dependencies` tables filtered to the endpoint shown in the hot path to see overall latency percentiles and failure rates.
4. **Match with Code Optimization recommendations**: Use `applicationinsights_recommendation_list` and match recommendations to the hot path methods for prioritized, data-backed fixes.
5. **Target code changes**: If source code is available, navigate to the methods identified in the hot path and apply targeted optimizations.

### Example workflow

```
1. Check investigation-notes.md for previously identified App Insights resource
2. If found, confirm with user; if not, identify and write to investigation notes
3. Query requests table for slow endpoints (p95 latency, error rates)
4. Query dependencies table for high-latency external calls
5. Query applicationinsights_recommendation_list for code optimization suggestions
6. Identify the top operations worth deep-diving (e.g., GET /api/forecasts at p95 = 2s)
7. Query customEvents for ServiceProfilerSample traces matching those operations
8. Invoke get-profile-hotpath skill with the app ID and trace location ID
9. Receive hot path call tree (e.g., WeatherForecastController.Get → 70% in ToList lambda)
10. Combine hot path + telemetry + recommendations into prioritized action plan
11. Suggest code changes targeting the hot path bottleneck methods
```

## Tips

- Always confirm the Application Insights resource with the user before proceeding with analysis.
- Always include the `subscription` parameter — it is required by the MCP server even though the schema marks it optional.
- Extract the subscription ID from the resource ID path: `/subscriptions/{subscriptionId}/resourceGroups/...`
- Use `monitor_resource_log_query` for targeted queries against a known Application Insights resource.
- Query multiple tables in parallel (requests, customEvents, performanceCounters, dependencies) to build a complete picture quickly.
- When a profiler trace is available for a slow operation, invoke the `get-profile-hotpath` skill to get method-level bottleneck data — but only after telemetry has confirmed the operation is worth investigating.
- Cross-reference hot path methods with Code Optimization recommendations for the highest-confidence optimization suggestions.
- When suggesting code optimizations, target the specific methods identified in the hot path and consider the bottleneck type (CPU, I/O, contention).

## References

For the investigation notes format and read/write protocol, see:
- [Investigation Notes](../shared/investigation-notes.md)

For detailed guidance on finding application insights resource, see:
- [Identify Application Insights Resource](references/identify-appinsights-resource.md)

For detailed guidance on analyzing Application Insights Profiler traces, see:
- [Profiler Analysis Guide](references/profiler-analysis-guide.md)

For fetching and interpreting profiler hot path call trees, see:
- [Get Profile Hot Path skill](../get-profile-hotpath/SKILL.md)
