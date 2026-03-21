---
name: perf-optimization
description: Guide for analyzing performance issues based on profiler and code optimizations, including CPU, latency, and throughput. Use this when asked to investigate performance bottlenecks or optimize application performance.
---

# Analysis

When asked to analyze performance issues based on profiler data, follow these steps:

1. **Check investigation notes** — Check whether `investigation-notes.md` exists in the working directory. If it does, read it for existing Application Insights resource details (resource ID, app ID, subscription, resource group). Present any found values to the user and ask whether to reuse them or provide new ones. See [Investigation Notes](../shared/investigation-notes.md) for the file format and rules.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in [Identify Application Insights Resource](references/identify-appinsights-resource.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values. If only a resource ID is available, resolve the app ID using [resolve-app-id.md](../shared/resolve-app-id.md).

3. **Query for slow requests with profiler traces** — Start by querying Application Insights for recent slow requests, especially those with `ServiceProfilerSample` events associated. Run the script in [query-slow-requests.md](scripts/query-slow-requests.md) to find the slowest requests that have profiler trace coverage. This gives you a concrete picture of what's slow and what has profiler data available for deeper analysis. The default lookback is 24 hours — adjust the `$lookbackHours` parameter to widen or narrow the window as needed.

   > **Why start here**: This step surfaces real slow requests with profiler traces attached, so you can prioritize which operations to investigate. Use the results to guide the Code Optimization and hot path analysis steps that follow.

   > **⚠️ CLI query pitfalls**: The `az monitor app-insights query` CLI has known issues that cause silent failures. Before running or modifying the query script, read [az CLI query pitfalls](../shared/az-cli-query-pitfalls.md). Key points: (1) `--offset` is **mandatory** — without it the CLI applies a 1-hour server-side filter that overrides KQL `ago()`, (2) always use `--output json` — `--output table` silently drops results for join queries, (3) flatten KQL to a single line to avoid here-string truncation.

4. **Query Code Optimizations data** — Run the script in [get-code-optimizations.md](scripts/get-code-optimizations.md) to fetch AI-powered recommendations from the profiler dataplane API. This is cheap and fast — it often points directly to the right methods without needing deeper analysis.

   > **If no recommendations are found**: This may happen when the Application Insights Profiler hasn't collected enough data, or the profiler isn't actively running. Try these fallback steps:
   > 1. **Widen the time range** — increase `$startTime` to cover the last 7 or 30 days instead of 24 hours.
   > 2. **Verify the profiler is active** — check that Application Insights Profiler is enabled and has recent profiling sessions. If step 3 returned no results either, the profiler may not be enabled.
   > 3. **Fall back to manual trace analysis** — skip to step 6 and invoke the `get-profile-hotpath` skill directly. Use the slow request IDs from step 3 (if available) to analyze the most expensive operations without Code Optimization guidance.

5. **Get recommendation details** — For the most impactful recommendations from step 4, extract the `key` and `timestamp` fields from each rollups result. Then run [get-recommendation-detail.md](scripts/get-recommendation-detail.md) with those values to get AI-generated fix guidance. **Important**: the rollups response variables won't persist across PowerShell sessions — extract the values you need before running the next script, or combine both calls in a single script block.

   > **If the recommendation service is unavailable**: The API may return `ServiceUnavailable` (HTTP 503) when the recommendation engine has failed after retries. This is a transient condition. When this happens:
   > 1. **Do not treat it as a blocking error** — the rollups data from step 4 is still valid and actionable.
   > 2. **Proceed with manual analysis** — use the `issueCategory`, `function`, `symbol`, `context` (call stack), and `value`/`criteria` fields from the rollups response to understand the bottleneck.
   > 3. **Fetch the hot path** — invoke the `get-profile-hotpath` skill (step 6) to get method-level detail, then combine with the rollups data to form your own recommendation.

6. **Fetch profiler hot path for targeted operations** — Once you've identified the most impactful operations from steps 3–5, use the `get-profile-hotpath` skill to retrieve the call tree and hot path for specific traces. This is an expensive operation — only invoke it for operations that warrant deep investigation. See [Leveraging Profiler Hot Path Data](#leveraging-profiler-hot-path-data) for details.

   > **Bridging request IDs to trace location IDs**: The slow requests from step 3 return request IDs, but the `get-profile-hotpath` skill requires a `ServiceProfilerContent` trace location ID. To look up trace location IDs for specific request IDs, query Application Insights `customEvents` filtering by `customDimensions.RequestId`:
   >
   > ```kql
   > customEvents | where name == 'ServiceProfilerSample' | extend reqId = tostring(customDimensions['RequestId']) | where reqId in ('REQUEST_ID_1', 'REQUEST_ID_2') | project timestamp, tostring(customDimensions['ServiceProfilerContent']), reqId
   > ```
   >
   > Run this using the same `az monitor app-insights query` pattern from step 3 (with `--offset` and `--output json`). The `ServiceProfilerContent` value from the results is the trace location ID needed for the hot path skill.

   > **Set user expectations**: The hot path fetch involves multiple API steps (trigger analysis → poll for completion → fetch root tree → expand child nodes) and typically takes **1–2 minutes** for fresh analyses. Inform the user upfront that this will take some time. For previously analyzed traces, results are cached and return in seconds.

7. **Putting data together to identify performance improvement opportunities** — Correlate the hot path bottlenecks with code optimization recommendations to prioritize fixes.

8. **Try provide code edits to optimize the performance** — When source code is available, suggest concrete code changes targeting the methods identified in the hot path.

## Leveraging Profiler Hot Path Data

The `get-profile-hotpath` skill provides method-level profiler trace data. Invoke it to get the hot path call tree for a specific profiler trace, then use the results here for deeper analysis.

### When to use the hot path data

- Fetch the hot path only **after** code optimization recommendations have identified specific operations worth investigating, or after step 3 has surfaced specific slow requests with profiler traces — it is an expensive operation per request.
- Use it to get method-level detail on **targeted** slow operations already surfaced by telemetry.
- Cross-reference hot path methods with Code Optimization recommendations for actionable fixes.

### How to use the hot path results

The `get-profile-hotpath` skill returns a call tree with timing data. Use it as follows:

1. **Identify the dominant method**: The hot path highlights the most expensive execution path. Focus optimization efforts on the methods consuming the most inclusive time (highest `Values.Metric`).
2. **Classify the bottleneck type**: Check `TotalCpuTime`, `TotalAwaitTime`, and `TotalBlockedTime` from the root tree to determine if the issue is CPU-bound, I/O-bound, or contention-bound.
3. **Match with Code Optimization recommendations**: Cross-reference the hot path methods with the recommendations from [get-code-optimizations.md](scripts/get-code-optimizations.md) and detail from [get-recommendation-detail.md](scripts/get-recommendation-detail.md) for prioritized, data-backed fixes.
4. **Target code changes**: If source code is available, navigate to the methods identified in the hot path and apply targeted optimizations.

> **Note on log queries**: If you need to query Application Insights logs (requests, dependencies, performanceCounters tables) for additional context beyond what [query-slow-requests.md](scripts/query-slow-requests.md) provides, use the Azure portal, Azure CLI (`az monitor app-insights query`), or the Azure Monitor REST API directly. This skill focuses on profiler-based analysis via the dataplane API.

### Example workflow

```
1. Check investigation-notes.md for previously identified App Insights resource
2. If found, confirm with user; if not, identify and write to investigation notes
3. Resolve app ID from resource ID if needed
4. Query for slow requests with profiler traces (query-slow-requests.md)
5. Run get-code-optimizations.md to fetch Code Optimization recommendations
6. Run get-recommendation-detail.md for the top recommendations to get AI fix guidance
7. Identify the top operations worth deep-diving (from steps 4–6)
8. Invoke get-profile-hotpath skill with the app ID and trace location ID
9. Receive hot path call tree (e.g., WeatherForecastController.Get → 70% in ToList lambda)
10. Combine hot path + recommendations into prioritized action plan
11. Suggest code changes targeting the hot path bottleneck methods
```

## Tips

- Always confirm the Application Insights resource with the user before proceeding with analysis.
- The app ID (GUID) is required for all dataplane API calls. If only a resource ID is available, resolve it with [resolve-app-id.md](../shared/resolve-app-id.md).
- When a profiler trace is available for a slow operation, invoke the `get-profile-hotpath` skill to get method-level bottleneck data — but only after Code Optimization recommendations have confirmed the operation is worth investigating.
- Cross-reference hot path methods with Code Optimization recommendations for the highest-confidence optimization suggestions.
- When suggesting code optimizations, target the specific methods identified in the hot path and consider the bottleneck type (CPU, I/O, contention).

## References

For the investigation notes format and read/write protocol, see:
- [Investigation Notes](../shared/investigation-notes.md)

For known `az monitor app-insights query` CLI issues, see:
- [az CLI Query Pitfalls](../shared/az-cli-query-pitfalls.md)

For detailed guidance on finding application insights resource, see:
- [Identify Application Insights Resource](references/identify-appinsights-resource.md)

For detailed guidance on analyzing Application Insights Profiler traces, see:
- [Profiler Analysis Guide](references/profiler-analysis-guide.md)

For fetching and interpreting profiler hot path call trees, see:
- [Get Profile Hot Path skill](../get-profile-hotpath/SKILL.md)
