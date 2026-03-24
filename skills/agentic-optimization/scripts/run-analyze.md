# Run Agentic Analysis

Executes the `aira.exe analyze` command to perform anomaly detection, trend analysis, and performance statistics on AI agent telemetry from Application Insights.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `subscriptionId` | Yes | Azure subscription ID (GUID) |
| `resourceGroup` | Yes | Azure resource group name |
| `componentName` | Yes | Application Insights component name |
| `agentName` | No | Filter by agent name |
| `agentVersion` | No | Filter by agent version |
| `limit` | No | Maximum number of records to analyze (1–50,000) |
| `startTime` | No | Start datetime in UTC (ISO 8601) |
| `endTime` | No | End datetime in UTC (ISO 8601) |

## Script

```powershell
$subscriptionId = "<SUBSCRIPTION_ID>"
$resourceGroup = "<RESOURCE_GROUP>"
$componentName = "<COMPONENT_NAME>"

# Optional filters — set to $null or remove the corresponding parameter lines below if not needed
$agentName = $null      # e.g., "my-agent"
$agentVersion = $null   # e.g., "1.0.0"
$limit = $null          # e.g., 1000
$startTime = $null      # e.g., "2026-03-01T00:00:00Z"
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

$args = @(
  "analyze"
  "-s", $subscriptionId
  "-g", $resourceGroup
  "-c", $componentName
  "--access", $token
)

if ($agentName) {
  $args += "--agent-name", $agentName
}

if ($agentVersion) {
  $args += "--agent-version", $agentVersion
}

if ($limit) {
  $args += "--limit", $limit
}

if ($startTime) {
  $args += "--start-time", $startTime
}

if ($endTime) {
  $args += "--end-time", $endTime
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

$result = & $exePath @args 2>&1

$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
  Write-Host "ERROR: aira.exe exited with code $exitCode"
  Write-Host $result
} else {
  # Output the JSON result for the agent to interpret
  $result
}
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — results are returned as JSON |
| 1 | Validation or argument error — check the error message for missing or invalid parameters |
| 2 | Unexpected error — the CLI encountered an internal failure |

### Reading the results

The `analyze` command returns JSON output (pretty-printed by default). The response contains analysis results including:

- **Anomaly detection** — Identifies unusual patterns in agent telemetry (latency spikes, error rate changes, throughput drops)
- **Trend analysis** — Shows performance trends over the analysis window
- **Performance statistics** — Aggregated metrics for the analyzed agent telemetry

Parse the JSON output to extract key findings. Focus on:

1. Anomalies with high severity or impact
2. Performance degradation trends
3. Agents or versions with outlier metrics

### No results?

If the command returns empty results or an error:

- **Check credentials** — Ensure `az login` was run and the account has access to the Application Insights resource
- **Verify resource details** — Confirm the subscription ID, resource group, and component name are correct
- **Widen the time range** — Set `$startTime` further back to capture more telemetry
- **Check for agent data** — The Application Insights resource may not have AI agent telemetry. Verify agent instrumentation is active.
- **Reduce the limit** — If the query times out, try a smaller `$limit` value
