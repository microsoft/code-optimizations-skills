---
name: perf-optimization
description: Guide for analyzing performance issues based on profiler and code optimizations, including CPU, latency, and throughput. Use this when asked to investigate performance bottlenecks or optimize application performance.
---

# Analysis

When asked to analyze performance issues based on profiler data, follow these steps:

1. **Check investigation notes** — Check whether `investigation-notes.md` exists in the working directory. If it does, read it for existing Application Insights resource details (resource ID, app ID, subscription, resource group). Present any found values to the user and ask whether to reuse them or provide new ones. See [Investigation Notes](../shared/investigation-notes.md) for the file format and rules.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in [Identify Application Insights Resource](references/identify-appinsights-resource.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values. If only a resource ID is available, resolve the app ID using [resolve-app-id.md](scripts/resolve-app-id.md).

3. **Query Code Optimizations data** — Run the script in [get-code-optimizations.md](scripts/get-code-optimizations.md) to fetch AI-powered recommendations from the profiler dataplane API. This is cheap and fast — it often points directly to the right methods without needing deeper analysis.

4. **Get recommendation details** — For the most impactful recommendations from step 3, run [get-recommendation-detail.md](scripts/get-recommendation-detail.md) to get AI-generated fix guidance for each.

5. **Fetch profiler hot path for targeted operations** — Once you've identified the most impactful operations from steps 3–4, use the `get-profile-hotpath` skill to retrieve the call tree and hot path for specific traces. This is an expensive operation — only invoke it for operations that warrant deep investigation. See [Leveraging Profiler Hot Path Data](#leveraging-profiler-hot-path-data) for details.

6. **Putting data together to identify performance improvement opportunities** — Correlate the hot path bottlenecks with code optimization recommendations to prioritize fixes.

7. **Try provide code edits to optimize the performance** — When source code is available, suggest concrete code changes targeting the methods identified in the hot path.

## Leveraging Profiler Hot Path Data

The `get-profile-hotpath` skill provides method-level profiler trace data. Invoke it to get the hot path call tree for a specific profiler trace, then use the results here for deeper analysis.

### When to use the hot path data

- Fetch the hot path only **after** code optimization recommendations have identified specific operations worth investigating — it is an expensive operation per request.
- Use it to get method-level detail on **targeted** slow operations already surfaced by telemetry.
- Cross-reference hot path methods with Code Optimization recommendations for actionable fixes.

### How to use the hot path results

The `get-profile-hotpath` skill returns a call tree with timing data. Use it as follows:

1. **Identify the dominant method**: The hot path highlights the most expensive execution path. Focus optimization efforts on the methods consuming the most inclusive time (highest `Values.Metric`).
2. **Classify the bottleneck type**: Check `TotalCpuTime`, `TotalAwaitTime`, and `TotalBlockedTime` from the root tree to determine if the issue is CPU-bound, I/O-bound, or contention-bound.
3. **Match with Code Optimization recommendations**: Cross-reference the hot path methods with the recommendations from [get-code-optimizations.md](scripts/get-code-optimizations.md) and detail from [get-recommendation-detail.md](scripts/get-recommendation-detail.md) for prioritized, data-backed fixes.
4. **Target code changes**: If source code is available, navigate to the methods identified in the hot path and apply targeted optimizations.

> **Note on log queries**: If you need to query Application Insights logs (requests, dependencies, performanceCounters tables) for additional context, use the Azure portal, Azure CLI (`az monitor app-insights query`), or the Azure Monitor REST API directly. This skill focuses on profiler-based analysis via the dataplane API.

### Example workflow

```
1. Check investigation-notes.md for previously identified App Insights resource
2. If found, confirm with user; if not, identify and write to investigation notes
3. Resolve app ID from resource ID if needed
4. Run get-code-optimizations.md to fetch Code Optimization recommendations
5. Run get-recommendation-detail.md for the top recommendations to get AI fix guidance
6. Identify the top operations worth deep-diving
7. Invoke get-profile-hotpath skill with the app ID and trace location ID
8. Receive hot path call tree (e.g., WeatherForecastController.Get → 70% in ToList lambda)
9. Combine hot path + recommendations into prioritized action plan
10. Suggest code changes targeting the hot path bottleneck methods
```

## Tips

- Always confirm the Application Insights resource with the user before proceeding with analysis.
- The app ID (GUID) is required for all dataplane API calls. If only a resource ID is available, resolve it with [resolve-app-id.md](scripts/resolve-app-id.md).
- When a profiler trace is available for a slow operation, invoke the `get-profile-hotpath` skill to get method-level bottleneck data — but only after Code Optimization recommendations have confirmed the operation is worth investigating.
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
