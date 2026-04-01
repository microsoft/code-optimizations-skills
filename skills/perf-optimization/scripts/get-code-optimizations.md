# Get Code Optimization Recommendations

Fetches Code Optimization recommendations from the Application Insights Profiler dataplane API. Returns aggregated insights based on profiler data — each entry identifies a method-level bottleneck with impact metrics.

## API

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/insights/rollups?startTime={startTime}&endTime={endTime}&api-version=2024-03-06-preview
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `appId` | Yes | Application Insights app ID (GUID). Resolve from resource ID using [resolve-app-id.md](../../shared/resolve-app-id.md) if needed. |
| `startTime` | Yes | ISO 8601 UTC timestamp — start of analysis window |
| `endTime` | Yes | ISO 8601 UTC timestamp — end of analysis window |

### Response fields

Each item in the response array is an `AggregatedInsightResult`:

| Field | Type | Description |
|-------|------|-------------|
| `key` | string | Unique identifier for this recommendation (hash of function + issue + app) |
| `count` | long | Number of profiler insights aggregated into this entry |
| `appId` | GUID | Application ID |
| `issueId` | string | Issue registry ID |
| `issueCategory` | string | Description of where the issue is (e.g., "CPU", "Blocking", "I/O") |
| `function` | string | Method name identified as the bottleneck |
| `parentFunction` | string | Calling method / component |
| `symbol` | string | Full symbol of the bottleneck method |
| `parentSymbol` | string | Full symbol of the parent |
| `value` | double | Measured performance metric value |
| `criteria` | double | Threshold value the metric exceeded |
| `relation` | string | How value relates to criteria (default: `"<"`) |
| `roleName` | string | Cloud role name |
| `traceOccurrences` | long | Total profiler trace occurrences |
| `timestamp` | DateTime | Most recent occurrence |
| `context` | string[] | Call stack of the issue |
| `isFixable` | bool | Whether the issue has an automatic fix. **Ignore this field** — it is not reliable for investigation purposes |
| `payload` | object | Additional analyzer-specific data |

## Script

```powershell
$appId = "<APP_ID>"
$endTime = (Get-Date).ToUniversalTime()
$startTime = $endTime.AddDays(-1)
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$uri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/insights/rollups" +
  "?startTime=$($startTime.ToString('o'))" +
  "&endTime=$($endTime.ToString('o'))" +
  "&api-version=2024-03-06-preview"

$response = Invoke-RestMethod `
  -Uri $uri `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
  }

# Display results
if ($response.Count -eq 0) {
  Write-Host "No Code Optimization recommendations found for the specified time range."
} else {
  Write-Host "Found $($response.Count) recommendation(s):"
  $i = 1
  $response | ForEach-Object {
    Write-Host "[$i] Issue: $($_.issueCategory) | Function: $($_.function) | Parent: $($_.parentFunction) | Occurrences: $($_.traceOccurrences) | Role: $($_.roleName)"
    $i++
  }
}
```

### Adjusting the time range

The default window is the last 24 hours. For broader analysis, increase the range:

```powershell
# Last 7 days
$startTime = $endTime.AddDays(-7)

# Last 30 days
$startTime = $endTime.AddDays(-30)
```
