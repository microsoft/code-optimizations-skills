---
name: error-exploration
category: exploring
description: Explore errors in Application Insights — exceptions, failed requests, and failed dependencies. Use this when asked to find errors, investigate failures, identify reliability issues, or recommend which errors to fix.
---

# Analysis

When asked to explore errors or investigate failures in Application Insights, follow these steps:

1. **Check investigation notes and gather inputs** — Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in [Identify Application Insights Resource](../perf-optimization/references/identify-appinsights-resource.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values. If only a resource ID is available, resolve the app ID using [resolve-app-id.md](../shared/resolve-app-id.md).

3. **Query for exceptions** — Run the script in [query-exceptions.md](scripts/query-exceptions.md) to find the most frequent exceptions, grouped by type and calling method. The query includes trend analysis (increasing/decreasing/stable) and problem IDs for drill-down. The default lookback is 24 hours — adjust the `$lookbackHours` parameter to widen or narrow the window as needed.

   > **⚠️ CLI query pitfalls**: Before running or modifying any query script, read [az CLI query pitfalls](../shared/az-cli-query-pitfalls.md). Key points: (1) `--offset` is **mandatory**, (2) always use `--output json`, (3) flatten KQL to a single line.

4. **Query for failed requests** — Run the script in [query-failed-requests.md](scripts/query-failed-requests.md) to find failed HTTP requests (status code ≥ 400 or `success == false`), grouped by operation name and result code. This surfaces user-facing failures with duration statistics that can reveal timeout patterns.

5. **Query for failed dependencies** — Run the script in [query-failed-dependencies.md](scripts/query-failed-dependencies.md) to find failed dependency calls (HTTP, SQL, storage, etc.), grouped by type, target, and result code. The query includes `AffectedOperations` to measure blast radius — how many distinct operations are impacted by each dependency failure.

   > **Running all three queries**: Run steps 3, 4, and 5 in sequence. Each query targets a different telemetry table and provides a different perspective on errors. Together, they give a comprehensive picture of the application's error landscape.

6. **Present unified error report and recommend priorities** — After collecting results from all three queries, synthesize the findings into a prioritized error report. Use the [Error Prioritization Guide](references/error-prioritization-guide.md) to rank errors by impact. Present the report to the user with clear recommendations.

   **How to present the results:**
   - **Lead with a summary** — State the total counts across all three categories (e.g., "Found 12 exception groups, 8 failed request patterns, and 5 failed dependency groups in the last 24 hours").
   - **Highlight the top 2–3 issues to fix** — For each, explain:
     - What the error is (type, operation, target)
     - How often it occurs and the trend direction
     - Why it matters (user impact, blast radius, severity class)
     - What to investigate next
   - **Correlate across categories** — Look for patterns where exceptions, failed requests, and failed dependencies are related (e.g., a `TimeoutException` in the caller correlates with a failed HTTP dependency to the same target). These correlated patterns are the most actionable.
   - **Rank by composite priority** — Use the prioritization framework: 🔴 Fix immediately (increasing 5xx, cascading failures), 🟡 Fix soon (stable high-frequency errors), 🟢 Monitor (decreasing trends, expected 4xx).

   > **Why present before deep-diving**: The user may have context about which errors are known issues, which are expected, and which are the most impactful. Let them choose what to investigate further.

7. **Offer deep-dive options** — Based on the user's selection, offer these investigation paths:

   - **View exception details**: Query for full stack traces and variable context for a specific exception group. Use the `problemId` to filter: `exceptions | where problemId == "<PROBLEM_ID>" | take 5 | project timestamp, outerMessage, details`.
   - **Trace a specific failed request**: Use the `deep-analysis` skill with a specific operation ID to see the full distributed trace for a failed request — including all dependency calls and their timing.
   - **Investigate performance + errors**: If failed requests also show high latency, hand off to the `perf-optimization` skill to correlate error patterns with profiler data and identify whether the failures are timeout-related.
   - **Check downstream dependency health**: For failed dependencies, investigate whether the target service has its own App Insights resource. If so, suggest using the `deep-analysis` skill to trace the operation from the caller's perspective into the downstream service.
   - **Widen the time range**: If the current results show a trend, offer to re-run the queries with a wider lookback (7 or 30 days) to establish a historical baseline.

## Tips

- Always confirm the Application Insights resource with the user before proceeding with analysis.
- Start with the default 24-hour lookback for an overview, then narrow or widen based on findings.
- When presenting results, focus on actionable insights rather than raw data. The user wants to know "what's broken and what should I fix first," not just "here are the numbers."
- Correlating across error categories produces the most valuable insights. A failed dependency that causes exceptions that cause request failures tells a clear story.
- Not all 4xx errors are problems — 404s on optional resources, 401s before authentication, and 409s on idempotent retries may be expected. Ask the user before classifying these as issues.
- **Distributed trace analysis**: If a failed request involves calls to downstream services, suggest the `deep-analysis` skill with the operation ID to trace the full request flow across services.
- **Performance correlation**: If errors cluster around specific operations that are also slow, suggest the `perf-optimization` skill to check whether the errors are timeout-related.

## References

For the investigation notes format and read/write protocol, see:
- [Investigation Notes](../shared/investigation-notes.md)

For known `az monitor app-insights query` CLI issues, see:
- [az CLI Query Pitfalls](../shared/az-cli-query-pitfalls.md)

For detailed guidance on finding Application Insights resources, see:
- [Identify Application Insights Resource](../perf-optimization/references/identify-appinsights-resource.md)

For how to rank and prioritize errors, see:
- [Error Prioritization Guide](references/error-prioritization-guide.md)
