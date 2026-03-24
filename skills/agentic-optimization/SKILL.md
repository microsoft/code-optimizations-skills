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

### 3. Run the analyze command

Run the script in [run-analyze.md](scripts/run-analyze.md) to execute the `aira.exe analyze` command. The script acquires a fresh access token and invokes the CLI with the gathered parameters.

> **Access token**: This skill uses the Application Insights data-plane token (`https://api.applicationinsights.io`), which is different from the profiler dataplane token used by other skills. The script handles token acquisition automatically.

> **Execution time**: The analysis may take a while depending on the volume of telemetry data. Inform the user that this may take some time, especially with large `--limit` values or wide time ranges.

### 4. Interpret and present the results

The script uses `--output summary` by default, which returns a pre-formatted text summary. Present this output directly to the user — no additional parsing is needed.

When presenting results, follow this structure:

1. **Lead with the summary header** — State total records, agent count, and time range.

2. **Highlight the agent performance table** — The table is sorted by P95 duration descending. Call out:
   - Agents with P95 > 5,000ms as high-latency
   - Agents with zero token counts (may indicate orchestration overhead, not LLM calls)
   - Agents with only 1 call (insufficient data for trends)

3. **Flag anomalies** — The summary lists high-severity anomalies (severity ≥ 3.0). For each:
   - Explain the impact (e.g., "4,515ms spike on an agent averaging 2,000ms")
   - Note the operation and model for context
   - Offer to drill deeper with `response-context --response-id <id>`

4. **Interpret trends** — Notable trends (confidence ≥ 0.5) are listed. Explain:
   - Duration increasing → potential regression or growing prompt size
   - Token usage increasing → context window growth, possible cost concern
   - Duration decreasing → improvement or reduced workload

5. **Provide actionable recommendations** — Based on findings, suggest:
   - Which agents or versions to investigate further
   - Whether to compare agent versions (`compare-versions` command)
   - Whether to drill into specific responses (`response-context` command)
   - Whether to widen/narrow the time range for more context

> **Need raw JSON?** If deeper programmatic analysis is needed, re-run the script with `-o json` instead of `-o summary`.

### 5. Follow-up investigation

Based on the analysis results, offer the user follow-up options:

- **Deep-dive into a specific agent**: Re-run the analysis with `--agent-name` and/or `--agent-version` filters
- **Adjust the time window**: Narrow or widen the analysis period to isolate issues
- **Cross-reference with profiler data**: If latency issues are found, suggest using the `perf-optimization` skill to correlate with profiler traces

## Tips

- Always confirm the Application Insights resource with the user before running the analysis.
- Start with a default analysis (no filters, last 24 hours, limit 1000) to get a broad overview, then narrow down based on findings.
- Use `--output summary` (the default in the script) for LLM-friendly output. Switch to `--output json` only when you need raw data for programmatic follow-up.
- The `--limit` parameter caps the number of telemetry records analyzed. The CLI defaults to 1000. For thorough analysis, increase up to 50,000.
- The script defaults to a 24-hour time window. Widen it for historical analysis; narrow it to isolate recent incidents.
- When comparing agent performance across versions, note the agent name from the results and suggest the user run a follow-up comparison.
- If the CLI returns exit code 1 with "No telemetry records found", check the error message — it now provides actionable guidance on what to try next.

## References

For the investigation notes format and read/write protocol, see:
- [Investigation Notes](../shared/investigation-notes.md)

For finding the Application Insights resource, see:
- [Identify Application Insights Resource](../perf-optimization/references/identify-appinsights-resource.md)

For the full CLI specification (all available commands), see:
- [CLI Specification](references/cli-spec-summary.md)
