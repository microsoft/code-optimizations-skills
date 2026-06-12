# CLI Specification Summary

The `aira.exe` CLI provides commands for querying, analyzing, and comparing AI agent telemetry from Azure Application Insights. This skill primarily uses the `analyze` command, but the full command set is listed here for reference and follow-up investigations.

## Access Token

All commands require an access token for the Application Insights data-plane API:

```powershell
$token = (az account get-access-token --resource "https://api.applicationinsights.io" --query accessToken -o tsv)
```

Pass this via the `--access` parameter.

## Common Options

Most commands share these options:

| Option | Short | Long | Required | Description |
|--------|-------|------|:--------:|-------------|
| Subscription ID | `-s` | `--subscription` | Yes | Azure subscription ID |
| Resource Group | `-g` | `--resource-group` | Yes | Azure resource group name |
| Component Name | `-c` | `--component` | Yes | Application Insights component name |
| Access Token | | `--access` | Yes | Bearer access token |
| Start Time | | `--start-time` | No | Start datetime in UTC (ISO 8601) |
| End Time | | `--end-time` | No | End datetime in UTC (ISO 8601) |
| Output Format | `-o` | `--output` | No | `json` (default), `compact`, or `summary` |

## Available Commands

| Command | Description | Key Additional Options |
|---------|-------------|----------------------|
| `analyze` | Trace analysis with anomaly detection | `--limit`, `--agent-name`, `--agent-version` |
| `percentile` | Percentile latency analysis | `--percentile` (0–100, default 90), `--agent` |
| `evaluation-results` | Raw evaluation scores | `--agent` |
| `evaluation-analysis` | Evaluation anomaly analysis | `--agent` |
| `agent-details` | Agent version metadata | `--agent` |
| `compare-versions` | Diff between agent versions | `--agent` (required), `--version1`, `--version2` |
| `response-context` | Response context lookup | `--response-id` (required) |
| `test` | Test Application Insights connectivity | *(none)* |

### Agent Filter Format

Commands accepting `--agent` use the format:

```
agentName            # matches all versions
agentName:version    # matches a specific version
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Validation / argument error |
| 2 | Unexpected error |
