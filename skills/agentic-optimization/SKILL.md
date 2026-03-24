---
name: agentic-optimization
description: Analyze AI agent telemetry from Application Insights, including anomaly detection, trend analysis, and performance statistics. Use this when asked to analyze AI agent performance, detect anomalies in agent telemetry, or review agent trace data.
---

# Agentic Optimization

This skill analyzes AI agent telemetry traces from Application Insights using the `aira.exe` CLI tool. It performs anomaly detection, trend analysis, and generates performance statistics to help identify issues in AI agent behavior.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- The user must provide Application Insights resource details: **Subscription ID**, **Resource Group**, and **Component Name**

## Steps

### 1–2. Check investigation notes and gather inputs

Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

In addition to the standard App ID, this skill requires the following Application Insights identity fields:

- **Subscription ID**: Azure subscription GUID
- **Resource Group**: Resource group containing the Application Insights resource
- **Component Name**: The Application Insights component name (resource name)

These are typically available in `investigation-notes.md`. If only a Resource ID is available, parse the subscription ID, resource group, and component name from the ARM resource ID format:

```
/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/microsoft.insights/components/{componentName}
```

If none of the above are available, follow [Identify Application Insights Resource](../perf-optimization/references/identify-appinsights-resource.md) to locate the resource.

Optional inputs — ask the user if they want to narrow the analysis:
- **Agent name**: Filter by a specific agent name
- **Agent version**: Filter by a specific agent version
- **Limit**: Maximum number of records to analyze (1–50,000)
- **Time range**: Start and end times for the analysis window (ISO 8601 UTC)

### 3. Run the analyze command

Run the script in [run-analyze.md](scripts/run-analyze.md) to execute the `aira.exe analyze` command. The script acquires a fresh access token and invokes the CLI with the gathered parameters.

> **Access token**: This skill uses the Application Insights data-plane token (`https://api.applicationinsights.io`), which is different from the profiler dataplane token used by other skills. The script handles token acquisition automatically.

> **Execution time**: The analysis may take a while depending on the volume of telemetry data. Inform the user that this may take some time, especially with large `--limit` values or wide time ranges.

### 4. Interpret and present the results

The `analyze` command returns JSON output containing anomaly detection results, trend analysis, and performance statistics for the targeted AI agent telemetry.

When presenting results to the user:

1. **Summarize key findings** — Start with a high-level overview: how many anomalies were detected, what the overall performance trends look like, and whether there are any critical issues.

2. **Highlight anomalies** — If anomalies are detected, present them clearly with:
   - What metric or behavior is anomalous
   - The severity or impact
   - When the anomaly occurred
   - Possible contributing factors

3. **Present performance statistics** — Show relevant performance metrics such as latency distributions, throughput, error rates, and token usage patterns.

4. **Show trend analysis** — If trends are present, describe whether performance is improving, degrading, or stable over time.

5. **Provide actionable recommendations** — Based on the findings, suggest concrete next steps:
   - Which agents or versions to investigate further
   - Whether to compare agent versions (suggest the `compare-versions` command for follow-up)
   - Whether to drill into specific responses (suggest using `response-context` for detailed investigation)
   - Code or configuration changes that could address identified issues

### 5. Follow-up investigation

Based on the analysis results, offer the user follow-up options:

- **Deep-dive into a specific agent**: Re-run the analysis with `--agent-name` and/or `--agent-version` filters
- **Adjust the time window**: Narrow or widen the analysis period to isolate issues
- **Cross-reference with profiler data**: If latency issues are found, suggest using the `perf-optimization` skill to correlate with profiler traces

## Tips

- Always confirm the Application Insights resource with the user before running the analysis.
- Start with a default analysis (no filters) to get a broad overview, then narrow down based on findings.
- The `--limit` parameter caps the number of telemetry records analyzed. For initial exploration, a smaller limit (e.g., 1000) gives faster results. For thorough analysis, increase the limit or omit it.
- When comparing agent performance across versions, note the agent name from the results and suggest the user run a follow-up comparison.
- The `--output compact` format is useful when piping results to other tools, but use the default `json` format for human-readable analysis.

## References

For the investigation notes format and read/write protocol, see:
- [Investigation Notes](../shared/investigation-notes.md)

For finding the Application Insights resource, see:
- [Identify Application Insights Resource](../perf-optimization/references/identify-appinsights-resource.md)

For the full CLI specification (all available commands), see:
- [CLI Specification](references/cli-spec-summary.md)
