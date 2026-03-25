---
name: perf-optimization
description: Guide for analyzing performance issues based on profiler and code optimizations, including CPU, latency, and throughput. Use this when asked to investigate performance bottlenecks or optimize application performance.
---

# Analysis

When asked to analyze performance issues based on profiler data, follow these steps:

1. **Check investigation notes and gather inputs** — Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in [Identify Application Insights Resource](references/identify-appinsights-resource.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values. If only a resource ID is available, resolve the app ID using [resolve-app-id.md](../shared/resolve-app-id.md).

3. **Query for slow requests with profiler traces** — Start by querying Application Insights for recent slow requests, especially those with `ServiceProfilerSample` events associated. Run the script in [query-slow-requests.md](scripts/query-slow-requests.md) to find the slowest requests that have profiler trace coverage. This gives you a concrete picture of what's slow and what has profiler data available for deeper analysis. The default lookback is 24 hours — adjust the `$lookbackHours` parameter to widen or narrow the window as needed.

   > **Why start here**: This step surfaces real slow requests with profiler traces attached, so you can prioritize which operations to investigate. Use the results to guide the Code Optimization and hot path analysis steps that follow.

   > **⚠️ CLI query pitfalls**: The `az monitor app-insights query` CLI has known issues that cause silent failures. Before running or modifying the query script, read [az CLI query pitfalls](../shared/az-cli-query-pitfalls.md). Key points: (1) `--offset` is **mandatory** — without it the CLI applies a 1-hour server-side filter that overrides KQL `ago()`, (2) always use `--output json` — `--output table` silently drops results for join queries, (3) flatten KQL to a single line to avoid here-string truncation.

   > **⚠️ No profiler data?** If this query returns zero results, check for profiler activity by counting both `ServiceProfilerIndex` (session-level) and `ServiceProfilerSample` (request-level) events:
   > - **Neither event type exists** → the profiler is not enabled. Skip steps 5 and 6, and recommend the `enable-profiler` skill.
   > - **`ServiceProfilerIndex` exists but no `ServiceProfilerSample`** → the profiler IS running sessions but captured zero request-level samples (e.g., low traffic, no requests during profiling windows). Skip steps 5 and 6 (Code Optimizations and hot path both require request-level samples), but do NOT recommend enabling the profiler — it is already enabled. Instead, suggest the user generate more traffic and wait for the next profiling cycle.
   > - In either case, you may still analyze request telemetry (durations, error rates, operation names) from the `requests` table to give the user a high-level picture of what's slow, but without `ServiceProfilerSample` data, method-level analysis is not possible.

4. **Present findings and let the user choose** — After collecting slow request results from step 3, present the findings to the user with investigation recommendations. Do not proceed automatically — let the user decide which request(s) to investigate.

   **How to present the results:**
   - Summarize the slow requests in a clear, ranked list.
   - For the top candidates (typically 2–3), provide a short rationale explaining **why** each is worth investigating. Consider factors such as:
     - **Duration** — the slowest requests are often the highest-impact targets.
     - **Frequency** — an operation that appears multiple times suggests a systemic issue rather than a one-off spike.
     - **Error codes** — non-200 status codes combined with high latency may indicate a different class of problem (e.g., retries, timeouts).
     - **Operation name** — if a known critical endpoint appears, call that out.
   - Explicitly recommend which request(s) you would investigate first, and why.
   - Ask the user which request(s) they would like to proceed with.

   > **Why ask the user**: The user may have domain context you don't — they may know that a particular endpoint is low-priority, or that a specific operation is already being worked on. Letting them choose avoids wasting time on the wrong target.

   > **If only one result**: If the query returned a single slow request, still present it with context and confirm with the user before proceeding.

5. **Query Code Optimizations data** — Run the script in [get-code-optimizations.md](scripts/get-code-optimizations.md) to fetch AI-powered recommendations from the profiler dataplane API. This is cheap and fast — it often points directly to the right methods without needing deeper analysis.

   > **⚠️ Skip this step if no request-level profiler data exists**: Code Optimizations are generated from profiler trace data. If no `ServiceProfilerSample` events were found (regardless of whether `ServiceProfilerIndex` sessions exist), skip this step — the API will return empty results. If no `ServiceProfilerIndex` events exist either, recommend the `enable-profiler` skill.

   > **If no recommendations are found** (but profiler data does exist): This may happen when the profiler hasn't collected enough data yet. Try these fallback steps:
   > 1. **Widen the time range** — increase `$startTime` to cover the last 7 or 30 days instead of 24 hours.
   > 2. **Verify the profiler is active** — check that Application Insights Profiler is enabled and has recent profiling sessions. If step 3 returned no results either, the profiler may not be enabled.
   > 3. **Fall back to manual trace analysis** — skip to step 6 and invoke the `get-profile-hotpath` skill directly. Use the slow request IDs from step 3 (if available) to analyze the most expensive operations without Code Optimization guidance.

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
3. **Match with Code Optimization recommendations**: Cross-reference the hot path methods with the recommendations from [get-code-optimizations.md](scripts/get-code-optimizations.md) for prioritized, data-backed fixes.
4. **Target code changes**: If source code is available, navigate to the methods identified in the hot path and apply targeted optimizations.

> **Note on log queries**: If you need to query Application Insights logs (requests, dependencies, performanceCounters tables) for additional context beyond what [query-slow-requests.md](scripts/query-slow-requests.md) provides, use the Azure portal, Azure CLI (`az monitor app-insights query`), or the Azure Monitor REST API directly. This skill focuses on profiler-based analysis via the dataplane API.

### Example workflow

```
1. Check investigation-notes.md for previously identified App Insights resource
2. If found, confirm with user; if not, identify and write to investigation notes
3. Resolve app ID from resource ID if needed
4. Query for slow requests with profiler traces (query-slow-requests.md)
5. If zero profiler events (no ServiceProfilerIndex): recommend enable-profiler skill → stop
   If ServiceProfilerIndex exists but no ServiceProfilerSample: profiler is running but no request samples → advise on traffic/triggers → stop
6. Present ranked results with rationales; ask user which request(s) to investigate
7. Run get-code-optimizations.md to fetch Code Optimization recommendations
8. Identify the top operations worth deep-diving (from steps 6–7)
9. Invoke get-profile-hotpath skill with the app ID and trace location ID
10. Receive hot path call tree (e.g., WeatherForecastController.Get → 70% in ToList lambda)
11. Combine hot path + recommendations into prioritized action plan
12. Suggest code changes targeting the hot path bottleneck methods
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
