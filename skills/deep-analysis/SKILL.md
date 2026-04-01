---
name: deep-analysis
description: Cross-resource deep analysis of a specific distributed trace. Takes an operation ID and correlates telemetry across multiple Application Insights resources to build a unified picture of a distributed operation.
---

# Deep Analysis

This skill performs cross-resource deep analysis of a specific distributed trace. Given an operation ID (from any skill's output or from the user), it discovers related Application Insights resources, queries each for correlated telemetry, and presents a unified timeline showing where time was spent and what went wrong.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- A primary Application Insights resource must be identified (in `investigation-notes.md` or provided by the user)
- An **operation ID** to investigate (typically surfaced by the `agentic-optimization` or `perf-optimization` skill)

## Steps

### 1–2. Check investigation notes and gather inputs

Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

In addition to the standard App ID and resource identity fields, this skill requires:

- **Operation ID**: The distributed trace operation ID to investigate. This is typically:
  - An operation ID from an anomaly flagged by the `agentic-optimization` skill
  - A request ID from a slow request surfaced by the `perf-optimization` skill
  - An operation ID provided directly by the user (e.g., from Application Insights transaction search)

If the user doesn't have an operation ID, suggest they first run the `agentic-optimization` or `perf-optimization` skill to identify interesting operations.

### 3. Discover related resources

Check whether `investigation-notes.md` has a **"Related Resources"** section with previously discovered resources.

- If **related resources exist** → present them to the user and ask whether to reuse or re-discover.
- If **no related resources** → run [discover-related-resources.md](../shared/discover-related-resources.md) to find downstream App Insights resources. This uses 4 targeted strategies (same resource group, dependency IKey correlation, shared workspace, local config scan).

> **AI agent workloads**: For AI agent scenarios, dependency telemetry often has `target=unknown` (type=AI), making dependency-based discovery ineffective. The **local config scan** (strategy 3d) is typically the most reliable — tool endpoints and connection strings are usually in the source code. Also note that downstream resources may be in a **different subscription** than the agent — the discovery script uses cross-subscription Resource Graph queries to handle this.

After discovery, confirm the list of resources with the user. Each resource should have a role label (e.g., "Agent host", "Tool: SearchAPI").

### 4. Fetch operation context from primary resource

Query the primary App Insights resource for the full trace of the given operation ID. This establishes the baseline view of the distributed operation.

> ⚠️ Before running queries, review [az CLI query pitfalls](../shared/az-cli-query-pitfalls.md).

#### 4a. Query requests, dependencies, and exceptions for the operation

```powershell
$resourceId = "<PRIMARY_RESOURCE_ID>"
$operationId = "<OPERATION_ID>"

# Fetch all telemetry for this operation: requests, dependencies, exceptions, traces
$query = "union requests, dependencies, exceptions, traces | where operation_Id == '$operationId' | project timestamp, itemType, name, duration, resultCode, target, type, operation_ParentId, id, problemId, message | order by timestamp asc"

$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset "P7D" `
  --output json 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: Query failed for primary resource."
  Write-Host $result
} else {
  $parsed = $result | ConvertFrom-Json
  $rows = $parsed.tables[0].rows
  Write-Host "Found $($rows.Count) telemetry item(s) for operation $operationId in primary resource"
}
```

#### 4b. If using agentic-optimization — also fetch agent-specific context

If the operation originated from an AI agent analysis (e.g., flagged by the `agentic-optimization` skill), also run:

```powershell
# Use aira.exe response-context for richer agent-specific context
$token = (az account get-access-token --resource "https://api.applicationinsights.io" --query accessToken -o tsv)

$scriptDir = "$PSScriptRoot\..\agentic-optimization\scripts"
$exePath = Join-Path $scriptDir "aira.exe"

& $exePath response-context `
  -s "$subscriptionId" -g "$resourceGroup" -c "$componentName" `
  --access "$token" `
  --response-id "$operationId" `
  -o json
```

> This step is optional — skip it if the operation is not from an AI agent workload or if `aira.exe` is not available.

### 5. Correlate across downstream resources

For each related resource in the investigation notes, query for telemetry correlated to the same operation ID. The Application Insights SDK propagates operation IDs across service boundaries when distributed tracing is enabled.

```powershell
$relatedResourceId = "<RELATED_RESOURCE_ID>"
$operationId = "<OPERATION_ID>"

$query = "union requests, dependencies, exceptions, traces | where operation_Id == '$operationId' | project timestamp, itemType, name, duration, resultCode, target, type, operation_ParentId, id, problemId, message | order by timestamp asc"

$result = az monitor app-insights query `
  --apps "$relatedResourceId" `
  --analytics-query "$query" `
  --offset "P7D" `
  --output json 2>&1

if ($LASTEXITCODE -eq 0) {
  $parsed = $result | ConvertFrom-Json
  $rows = $parsed.tables[0].rows
  Write-Host "Found $($rows.Count) telemetry item(s) in resource: <RESOURCE_NAME>"
} else {
  Write-Host "WARNING: Query failed for resource <RESOURCE_NAME>. The operation may not have reached this service."
}
```

Run this for each related resource. Collect all results.

Additionally, for each related resource that has telemetry for this operation:
- **Check for profiler traces** — query `customEvents` for `ServiceProfilerSample` events covering the operation's time window. If found, note this for the user — they can use `get-profile-hotpath` for method-level analysis.
- **Check for exceptions** — highlight any exceptions correlated to the operation.

```powershell
$relatedResourceId = "<RELATED_RESOURCE_ID>"
$operationId = "<OPERATION_ID>"

# Derive the operation's time window from the telemetry fetched above.
# Use the min/max timestamps from the operation's events, with a 2-minute buffer
# on each side to account for profiler sampling intervals.
# $operationStart and $operationEnd should be ISO 8601 UTC strings computed from
# the earliest and latest timestamps in the operation's telemetry results.
$operationStart = "<ISO 8601 UTC — earliest event timestamp minus 2 minutes>"
$operationEnd = "<ISO 8601 UTC — latest event timestamp plus 2 minutes>"

# Check for profiler coverage in this time window
$profilerQuery = "customEvents | where name == 'ServiceProfilerSample' | where timestamp between (datetime('$operationStart') .. datetime('$operationEnd')) | take 1"

$profilerResult = az monitor app-insights query `
  --apps "$relatedResourceId" `
  --analytics-query "$profilerQuery" `
  --offset "P7D" `
  --output json 2>&1

if ($LASTEXITCODE -eq 0) {
  $parsed = $profilerResult | ConvertFrom-Json
  $rows = $parsed.tables[0].rows
  if ($rows.Count -gt 0) {
    Write-Host "Profiler trace available for this time window in resource: <RESOURCE_NAME>"
  }
}
```

### 6. Present cross-resource findings

Merge all telemetry from the primary and related resources into a **unified timeline**. Present it to the user with:

1. **Timeline view** — All events ordered by timestamp, annotated with which resource they came from and their role label:
   ```
   [00:00.000] Agent host     | REQUEST  POST /api/chat              (2,450ms)
   [00:00.050] Agent host     | DEPENDENCY  SearchAPI.Search         (1,200ms) → Tool: SearchAPI
   [00:00.060] Tool: SearchAPI| REQUEST  POST /search                (1,180ms)
   [00:00.070] Tool: SearchAPI| DEPENDENCY  Azure Cognitive Search   (950ms)
   [00:01.300] Agent host     | DEPENDENCY  OpenAI.ChatCompletion   (800ms)
   [00:02.200] Agent host     | REQUEST  POST /api/chat completed    (2,450ms)
   ```

2. **Time breakdown** — Where was time spent? Show percentage per resource/dependency:
   ```
   Total: 2,450ms
     SearchAPI call:     1,200ms (49%)  ← profiler available
     OpenAI call:          800ms (33%)
     Agent processing:     450ms (18%)
   ```

3. **Issues found** — Highlight:
   - Exceptions or error status codes
   - Dependencies with unusually high latency
   - Missing telemetry gaps (time unaccounted for)
   - Resources where the operation ID was NOT found (possible instrumentation gap)

4. **Profiler availability** — For resources with profiler data covering this time window, note that method-level analysis is available.

### 6b. Source code analysis for bottleneck tool calls

When the cross-resource analysis identifies a **tool call or API call** as the dominant bottleneck (e.g., >50% of total operation time), scan the local codebase for the tool's implementation to identify the root cause.

This is especially valuable for AI agent workloads where the agent and its tools are often in the same repository.

1. **Identify the tool name** from the telemetry (e.g., `execute_tool remote_openapi.GetUserFunc_GetUsers`)
2. **Search the codebase** for the function implementation — look for matching function names, API route definitions, or OpenAPI operation IDs
3. **Examine the implementation** for common bottlenecks:
   - Slow SQL queries (missing indexes, N+1 queries, `WAITFOR DELAY`, full table scans)
   - Unoptimized external API calls (missing caching, sequential instead of parallel calls)
   - Large data transfers (returning all rows without pagination)
   - Blocking I/O (synchronous calls in async contexts)
4. **Present findings** to the user with the specific code location and a concrete optimization recommendation

> If the source code is not available in the working directory, inform the user and suggest they provide the repository path or examine the code manually.

### 7. Suggest next steps

Based on the findings, offer actionable follow-ups:

- **Profiler deep-dive**: If a downstream resource has profiler data (detected in step 5's profiler check) → offer to invoke `get-profile-hotpath` immediately, passing the trace location ID from the `ServiceProfilerSample` event's `customDimensions.ServiceProfilerContent` field. This provides method-level call tree analysis without requiring the user to switch skills manually.
- **Performance optimization**: If a downstream resource shows high latency → suggest `perf-optimization` targeting that resource
- **Code optimizations**: If a downstream resource has Code Optimization recommendations → suggest fetching them
- **Compare agent versions**: If the issue correlates with a specific agent version → suggest `aira.exe compare-versions`
- **Widen investigation**: If the operation ID wasn't found in some related resources → the trace may not propagate there; suggest checking instrumentation or trying a different operation

## Tips

- Start with the primary resource context (step 4) before querying downstream resources — this gives you the dependency call graph to guide which resources matter most.
- Not all related resources will have telemetry for a given operation. This is expected — the agent may not call every downstream service on every request.
- If distributed tracing headers aren't propagated, the operation ID won't match across resources. In this case, fall back to time-based correlation (query by timestamp range instead of operation ID).
- The timeline view is most useful when presented as a compact table or tree. Avoid overwhelming the user with raw telemetry — summarize and highlight.

## References

- [Discover Related Resources](../shared/discover-related-resources.md)
- [Investigation Notes](../shared/investigation-notes.md)
- [az CLI Query Pitfalls](../shared/az-cli-query-pitfalls.md)
- [Standard Skill Preamble](../shared/standard-skill-preamble.md)
- [Resolve App ID](../shared/resolve-app-id.md)
