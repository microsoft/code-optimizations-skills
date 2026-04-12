# Get Variables

Fetch variable names, values, and types from the snapshot's variable store. Each stack frame contains an array of variable indices — this script resolves those indices to actual variable data.

Variables can have child references (nested objects). This script supports fetching **2 levels deep** (top-level variables + their immediate children) to balance detail with output size.

## Request

```
POST https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/variables?api-version=2025-03-19-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `Content-Type` | `application/json` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `perf-copilot/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

### Request body

```json
{
  "stampId": "{stampId}",
  "snapshotId": "{snapshotId}",
  "snapshotTimestamp": "{snapshotTimestamp}",
  "redisCacheRegion": "{redisCacheRegion}",
  "indices": [0, 1, 2, 3]
}
```

## PowerShell script

```powershell
$appId = "<APP_ID>"
$stampId = "<STAMP_ID>"
$snapshotId = "<SNAPSHOT_ID>"
$snapshotTimestamp = "<SNAPSHOT_TIMESTAMP>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
$variableIndices = @(0, 1, 2, 3)  # From a stack frame's Variables array
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

$body = @{
    stampId = $stampId
    snapshotId = $snapshotId
    snapshotTimestamp = $snapshotTimestamp
    redisCacheRegion = $redisCacheRegion
    indices = $variableIndices
} | ConvertTo-Json

$variables = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/variables?api-version=2025-03-19-preview" `
  -Method POST `
  -Headers @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
    "User-Agent" = $userAgent
  } `
  -Body $body

# Display top-level variables
foreach ($v in $variables) {
    Write-Host "$($v.name) ($($v.type)) = $($v.value)"
}

# Output full JSON for further processing
$variables | ConvertTo-Json -Depth 5
```

## Response

The response is a JSON array of `Variable` objects:

```json
[
  {
    "id": 0,
    "name": "this",
    "value": "{MyApp.Controllers.HomeController}",
    "type": "HomeController",
    "children": [10, 11, 12]
  },
  {
    "id": 1,
    "name": "request",
    "value": "{Microsoft.AspNetCore.Http.DefaultHttpRequest}",
    "type": "HttpRequest",
    "children": [20, 21, 22]
  }
]
```

### Key fields

| Field | Description |
|---|---|
| `id` | Variable index (matches the index from the request) |
| `name` | Variable name (e.g., `this`, `request`, `count`) |
| `value` | Display value (e.g., `"hello"`, `42`, `{TypeName}`) |
| `type` | Variable type name |
| `children` | Array of child variable indices for nested objects. Use these indices in a second request to expand. |

## Expanding child variables (level 2)

To get one level of child details, collect all `children` indices from the top-level variables and make a second request:

```powershell
# Collect all child indices from top-level variables
$childIndices = @()
foreach ($v in $variables) {
    if ($v.children -and $v.children.Count -gt 0) {
        $childIndices += $v.children
    }
}
$childIndices = @($childIndices | Select-Object -Unique)

if ($childIndices.Count -gt 0) {
    $childBody = @{
        stampId = $stampId
        snapshotId = $snapshotId
        snapshotTimestamp = $snapshotTimestamp
        redisCacheRegion = $redisCacheRegion
        indices = $childIndices
    } | ConvertTo-Json

    $childVariables = Invoke-RestMethod `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/variables?api-version=2025-03-19-preview" `
      -Method POST `
      -Headers @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
        "User-Agent" = $userAgent
      } `
      -Body $childBody

    $childVariables | ConvertTo-Json -Depth 5
}
```

## Error handling

| Status | Meaning |
|---|---|
| 200 | Success — array of variables returned |
| 400 | Bad request — `indices` array is empty or malformed |
| 404 | Variables not found — the snapshot may have expired or computation hasn't run |
| 401 | Token expired — re-acquire with `get-access-token.md` |
