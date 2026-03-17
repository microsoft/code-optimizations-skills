---
name: appinsights-profiler-perf-optimization
description: Guide for analyzing performance issues based on profiler and code optimizations, including CPU, latency, and throughput. Use this when asked to investigate performance bottlenecks or optimize application performance.
---

# Analysis

When asked to analyze performance issues based on profiler data, follow these steps:

1. **Identify the application insights resource**

2. **Find out the performance bottlenecks**

3. **Query code optimizations data**

4. **Putting data together to identify performance improvement opportunities**

5. **Try provide code edits to optimize the performance**

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

## Tips

- Always confirm the application insights resource with the user before proceeding with analysis.
- Always include the `subscription` parameter — it is required by the MCP server even though the schema marks it optional.
- Extract the subscription ID from the resource ID path: `/subscriptions/{subscriptionId}/resourceGroups/...`
- Use `monitor_resource_log_query` for targeted queries against a known Application Insights resource.
- Query multiple tables in parallel (requests, customEvents, performanceCounters, dependencies) to build a complete picture quickly.
- Use the profiler analysis guide to systematically analyze the profiler traces and identify bottlenecks.
- When suggesting code optimizations, consider the context of the application and the specific performance issues identified.

## References

For detailed guidance on finding application insights resource, see:
- [Identify Application Insights Resource](references/identify-appinsights-resource.md)

For detailed guidance on analyzing Application Insights Profiler traces, see:
- [Profiler Analysis Guide](references/profiler-analysis-guide.md)
