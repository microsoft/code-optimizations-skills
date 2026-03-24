# Run Agentic Analysis

Executes the `aira.exe analyze` command to perform anomaly detection, trend analysis, and performance statistics on AI agent telemetry from Application Insights.

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
  "-o", "summary"
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
} else {
  # Output the summary result for the agent to interpret
  $result
}
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — results are returned (summary text or JSON depending on `-o` flag) |
| 1 | Validation error or no data found — check stderr for details and actionable guidance |
| 2 | Unexpected error — the CLI encountered an internal failure |

### Reading the results

With `-o summary` (default in this script), the CLI returns a pre-formatted text summary containing:

- **Agent performance table** — All agents sorted by P95 duration, with call counts, latency stats, anomaly counts, and average token usage
- **Anomalies** — High-severity spikes (severity ≥ 3.0) with operation context, model, and operation ID for drill-down
- **Trends** — Notable trends (confidence ≥ 0.5) showing metric direction and change rate

Present this summary directly to the user. For raw JSON data (e.g., for follow-up queries), re-run with `-o json`.

### No results?

If the command returns exit code 1 with "No telemetry records found":

- **Check credentials** — Ensure `az login` was run and the account has access to the Application Insights resource
- **Verify resource details** — Confirm the subscription ID, resource group, and component name are correct
- **Widen the time range** — Set `$startTime` further back to capture more telemetry
- **Increase the limit** — Try a larger `$limit` value
- **Check for agent data** — The Application Insights resource may not have AI agent telemetry. Verify agent instrumentation is active.
