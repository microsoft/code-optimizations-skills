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
- **Limit**: Maximum number of records to analyze (1–50,000). Defaults to 1000 — suitable for initial exploration; increase for thorough analysis.
- **Time range**: Start and end times for the analysis window (ISO 8601 UTC). **Defaults to the last 24 hours.** Widen if the user wants historical analysis.

### 3. Run the analyze command and present results

Run the script in [run-analyze.md](scripts/run-analyze.md) to execute the `aira.exe analyze` command. The script acquires a fresh access token, invokes the CLI with JSON output, and post-processes the results into a readable summary **with operation IDs extracted** — all in a single run.

> **Access token**: This skill uses the Application Insights data-plane token (`https://api.applicationinsights.io`), which is different from the profiler dataplane token used by other skills. The script handles token acquisition automatically.

> **Execution time**: The analysis may take a while depending on the volume of telemetry data. Inform the user that this may take some time, especially with large `--limit` values or wide time ranges.

The script output contains everything needed to present results and offer deep-dive. Present it to the user with the following interpretation:

1. **Lead with the summary header** — State total records, agent count, and time range.

2. **Highlight per-agent performance** — Call out:
   - Agents with P95 > 5,000ms as high-latency
   - Large gaps between mean and P95 (indicates inconsistent performance / tail latency)
   - Low token counts with high latency (latency is likely in tool calls, not LLM)

3. **Explain the operation breakdown** — The script shows per-operation-type stats:
   - `invoke_agent` — overall agent invocation (parent span)
   - `chat` — LLM model calls (check latency and token counts)
   - `execute_tool` — tool/API calls (often the bottleneck; check `byTool` breakdown)

4. **Interpret trends** — Notable trends (confidence ≥ 0.5) are shown. Explain:
   - Duration increasing → potential regression or growing prompt size
   - Token usage increasing → context window growth, possible cost concern
   - Duration decreasing → improvement or reduced workload

5. **Present anomaly operations for deep-dive** — The script extracts operation IDs from anomaly spikes and displays them in a numbered table. Present this table directly and ask the user which operation they'd like to deep-dive into. Each row includes:
   - Operation ID (needed for `deep-analysis` skill handoff)
   - Duration and severity
   - Span types and model for context

> **Raw JSON**: The script saves the full JSON to `aira-output.json` in the working directory. Let the user know they can inspect this file for the complete data.

### 4. Deep-dive handoff

If the anomaly operations table has entries, ask the user which operation to investigate further:

- **Cross-resource deep analysis** (recommended): Hand off the selected operation ID to the `deep-analysis` skill to trace the operation across downstream services (tools, APIs, databases) and see where time was spent.
- **Response context**: Run `aira.exe response-context --response-id <operationId>` to see the full agent conversation flow for that operation.
- **Compare agent versions**: If the issue correlates with a specific agent version, suggest `aira.exe compare-versions`.

If the anomaly operations table is **empty** (no spikes detected), suggest:

- **Widen the time range** to capture more data and potential anomalies
- **Increase the limit** for more thorough analysis
- **Re-run with a specific agent name** to focus the analysis
- **Check the raw JSON** (`aira-output.json`) for lower-severity anomalies that didn't meet the threshold

### 5. Additional follow-up options

Beyond the deep-dive, offer these follow-up options based on findings:

- **Narrow the analysis**: Re-run with `--agent-name` and/or `--agent-version` filters to focus on a specific agent
- **Adjust the time window**: Narrow or widen the analysis period to isolate issues
- **Cross-reference with profiler data**: If latency issues are found in downstream services, suggest using the `perf-optimization` skill to correlate with profiler traces

## Tips

- Always confirm the Application Insights resource with the user before running the analysis.
- Start with a default analysis (no filters, last 24 hours, limit 1000) to get a broad overview, then narrow down based on findings.
- The script defaults to JSON output (`-o json`) with post-processing that extracts a readable summary and operation IDs in one pass. The raw JSON is saved to `aira-output.json` for user inspection.
- The `--limit` parameter caps the number of telemetry records analyzed. The CLI defaults to 1000. For thorough analysis, increase up to 50,000.
- The script defaults to a 24-hour time window. Widen it for historical analysis; narrow it to isolate recent incidents.
- When comparing agent performance across versions, note the agent name from the results and suggest the user run a follow-up comparison.
- If the CLI returns exit code 1 with "No telemetry records found", check the error message — it now provides actionable guidance on what to try next.
- The goal is to reach "ready for deep-dive" in a single run — present summary + operation IDs together so the user can pick one immediately.

## References

For the investigation notes format and read/write protocol, see:
- [Investigation Notes](../shared/investigation-notes.md)

For finding the Application Insights resource, see:
- [Identify Application Insights Resource](../perf-optimization/references/identify-appinsights-resource.md)

For the full CLI specification (all available commands), see:
- [CLI Specification](references/cli-spec-summary.md)
