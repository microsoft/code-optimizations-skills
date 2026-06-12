# Run Agentic Analysis

Executes the `aira.exe analyze` command to perform anomaly detection, trend analysis, and performance statistics on AI agent telemetry from Application Insights.

Uses `-o json` to get the full structured output including operation IDs from anomaly spikes. The script post-processes the JSON to display a readable summary **and** extract operation IDs ready for deep-dive handoff — all in a single run.

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `subscriptionId` | Yes | — | Azure subscription ID (GUID) |
| `resourceGroup` | Yes | — | Azure resource group name |
| `componentName` | Yes | — | Application Insights component name |
| `agentName` | No | all agents | Filter by agent name |
| `agentVersion` | No | all versions | Filter by agent version |
| `limit` | No | 1000 | Maximum number of records to analyze (1–50,000) |
| `startTime` | No | 24 hours ago | Start datetime in UTC (ISO 8601) |
| `endTime` | No | now | End datetime in UTC (ISO 8601) |

## Script

```powershell
$subscriptionId = "<SUBSCRIPTION_ID>"
$resourceGroup = "<RESOURCE_GROUP>"
$componentName = "<COMPONENT_NAME>"

# Optional filters — set to $null or remove the corresponding parameter lines below if not needed
$agentName = $null      # e.g., "my-agent"
$agentVersion = $null   # e.g., "1.0.0"
$limit = 1000           # Default 1000. Increase for thorough analysis, decrease for faster results.
$startTime = (Get-Date).ToUniversalTime().AddHours(-24).ToString("yyyy-MM-ddTHH:mm:ssZ")  # Last 24 hours
$endTime = $null        # e.g., "2026-03-24T00:00:00Z"

# Acquire access token for Application Insights data-plane API.
# Always re-acquire in the same command block to avoid cross-session variable scoping issues.
$token = (az account get-access-token --resource "https://api.applicationinsights.io" --query accessToken -o tsv)

if (-not $token) {
  Write-Host "ERROR: Failed to acquire access token. Ensure you are logged in (az login) and have access to the subscription."
  return
}

# Build the command arguments
$scriptDir = "$PSScriptRoot"
$exePath = Join-Path $scriptDir "aira.exe"

$cmdArgs = @(
  "analyze"
  "-s", $subscriptionId
  "-g", $resourceGroup
  "-c", $componentName
  "--access", $token
  "-o", "json"
)

if ($agentName) {
  $cmdArgs += "--agent-name", $agentName
}

if ($agentVersion) {
  $cmdArgs += "--agent-version", $agentVersion
}

if ($limit) {
  $cmdArgs += "--limit", $limit
}

if ($startTime) {
  $cmdArgs += "--start-time", $startTime
}

if ($endTime) {
  $cmdArgs += "--end-time", $endTime
}

# Run the analysis
Write-Host "Running agentic analysis..."
Write-Host "  Subscription: $subscriptionId"
Write-Host "  Resource Group: $resourceGroup"
Write-Host "  Component: $componentName"
if ($agentName) { Write-Host "  Agent Name: $agentName" }
if ($agentVersion) { Write-Host "  Agent Version: $agentVersion" }
if ($limit) { Write-Host "  Limit: $limit" }
if ($startTime) { Write-Host "  Start Time: $startTime" }
if ($endTime) { Write-Host "  End Time: $endTime" }
Write-Host ""

$result = & $exePath @cmdArgs 2>&1

$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
  Write-Host "ERROR: aira.exe exited with code $exitCode"
  Write-Host $result
  return
}

# Save raw JSON to working directory for user inspection
$rawStr = $result -join "`n"
$rawStr | Out-File -FilePath "aira-output.json" -Encoding utf8
Write-Host "Raw JSON saved to aira-output.json"
Write-Host ""

# Parse and display structured summary
$json = $rawStr | ConvertFrom-Json
$summary = $json.summary

Write-Host "=== SUMMARY ==="
Write-Host "  Records: $($summary.totalRecords) | Agents: $($summary.uniqueAgents) | Operations: $($summary.uniqueOperations)"
Write-Host "  Time range: $($summary.startTime) to $($summary.endTime)"
Write-Host ""

# Per-agent performance and anomaly extraction
$allSpikes = @()

foreach ($agentName in ($json.analysisResults | Get-Member -MemberType NoteProperty).Name) {
  $agent = $json.analysisResults.$agentName
  $dur = $agent.duration
  $stats = $dur.statisticalSummary

  Write-Host "=== AGENT: $agentName ==="
  Write-Host ("  Calls: {0} | Mean: {1:N0}ms | Median: {2:N0}ms | P95: {3:N0}ms | Max: {4:N0}ms" -f $stats.count, $stats.mean, $stats.median, $stats.p95, $stats.max)

  # Operation breakdown
  $ops = $dur.operationDistributionResult.operationMetrics
  if ($ops) {
    Write-Host "  --- Operation Breakdown ---"
    foreach ($opName in ($ops | Get-Member -MemberType NoteProperty).Name) {
      $op = $ops.$opName
      Write-Host ("    {0,-30} calls={1,-6} avg={2,8:N0}ms  max={3,8:N0}ms" -f $opName, $op.count, $op.avg, $op.max)
      # Show tool breakdown if present
      if ($op.byTool) {
        foreach ($toolName in ($op.byTool | Get-Member -MemberType NoteProperty).Name) {
          $tool = $op.byTool.$toolName
          Write-Host ("      Tool: {0,-40} avg={1,8:N0}ms  max={2,8:N0}ms" -f $toolName, $tool.avg, $tool.max)
        }
      }
    }
  }

  # Trend
  $trend = $dur.trendResult
  if ($trend -and $trend.confidence -ge 0.5) {
    Write-Host ("  Trend: {0} (confidence={1:P0}, changeRate={2:P1})" -f $trend.trendDirection, $trend.confidence, $trend.changeRate)
  }

  # Collect anomaly spikes with operation IDs
  foreach ($spike in $dur.anomalyResult.spikes) {
    $ctx = $spike.context
    $allSpikes += [PSCustomObject]@{
      Agent       = $agentName
      OperationId = $ctx.operationId
      Operation   = $ctx.aiOperationName
      Model       = $ctx.model
      ResponseId  = $ctx.responseId
      Duration    = [math]::Round($spike.value)
      Severity    = [math]::Round($spike.severity, 2)
    }
  }

  Write-Host ""
}

# Display anomaly spikes with operation IDs for deep-dive
if ($allSpikes.Count -gt 0) {
  # Deduplicate by operationId
  $uniqueOps = $allSpikes | Group-Object -Property OperationId | ForEach-Object {
    $group = $_.Group | Sort-Object -Property Duration -Descending
    $top = $group[0]
    [PSCustomObject]@{
      OperationId = $top.OperationId
      ResponseId  = $top.ResponseId
      Agent       = $top.Agent
      MaxDuration = $top.Duration
      MaxSeverity = ($group | Measure-Object -Property Severity -Maximum).Maximum
      SpanTypes   = ($group | ForEach-Object { $_.Operation }) -join ", "
      Model       = ($group | Where-Object { $_.Model } | Select-Object -First 1).Model
    }
  } | Sort-Object -Property MaxDuration -Descending

  Write-Host "=== ANOMALY OPERATIONS (ready for deep-dive) ==="
  Write-Host ("{0,-5} {1,-36} {2,-36} {3,12} {4,10} {5,-30} {6}" -f "#", "Operation ID", "Response ID", "Duration(ms)", "Severity", "Span Types", "Model")
  Write-Host ("-" * 150)

  $i = 1
  foreach ($op in $uniqueOps) {
    Write-Host ("{0,-5} {1,-36} {2,-36} {3,12} {4,10} {5,-30} {6}" -f $i, $op.OperationId, $op.ResponseId, $op.MaxDuration, $op.MaxSeverity, $op.SpanTypes, $op.Model)
    $i++
  }
} else {
  Write-Host "=== ANOMALY OPERATIONS ==="
  Write-Host "  No anomaly spikes with operation IDs detected."
  Write-Host "  Tip: Widen the time range, increase --limit, or lower the anomaly threshold for more results."
}
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — results are returned as JSON |
| 1 | Validation error or no data found — check stderr for details and actionable guidance |
| 2 | Unexpected error — the CLI encountered an internal failure |

### Reading the results

The script outputs a structured summary extracted from the JSON result:

1. **Summary header** — Record count, agent count, operation count, time range
2. **Per-agent performance** — Call count, mean/median/P95/max latency
3. **Operation breakdown** — Per-operation-type stats (invoke_agent, chat, execute_tool) with tool-level detail
4. **Trends** — Direction and confidence for notable trends
5. **Anomaly operations table** — Deduplicated list of operation IDs from anomaly spikes, sorted by duration, ready for deep-dive handoff

The raw JSON is also saved to `aira-output.json` in the working directory for the user to inspect.

### No results?

If the command returns exit code 1 with "No telemetry records found":

- **Check credentials** — Ensure `az login` was run and the account has access to the Application Insights resource
- **Verify resource details** — Confirm the subscription ID, resource group, and component name are correct
- **Widen the time range** — Set `$startTime` further back to capture more telemetry
- **Increase the limit** — Try a larger `$limit` value
- **Check for agent data** — The Application Insights resource may not have AI agent telemetry. Verify agent instrumentation is active.

### `responseId` vs `operationId`

The anomaly table displays both **Operation ID** and **Response ID**. These are different identifiers:

- **Operation ID** (`operationId`): The distributed tracing correlation ID. Use this with `deep-analysis` to trace across resources and with `az monitor app-insights query` to find related telemetry.
- **Response ID** (`responseId`): The AI agent response identifier. Use this with `aira.exe response-context --response-id <responseId>` to fetch the agent's conversation flow and tool invocations.

> ⚠️ Do not use the `operationId` as the `--response-id` argument — `aira.exe response-context` expects the response ID, not the operation ID. Using the wrong identifier returns empty results (`[]`).
