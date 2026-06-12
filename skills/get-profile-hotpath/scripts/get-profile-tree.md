# Get Profile Tree (Root)

Call the `profileTreeDefinitions` endpoint to get the root call tree and hot path for a profiler trace.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/profileTreeDefinitions?t={traceLocationId}&f={showFramework}&api-version=2024-03-06-preview&r={redisCacheRegion}
```

### Query parameters

| Parameter | Description |
|---|---|
| `t` | The trace location ID (URL-encoded `ServiceProfilerContent` value) |
| `f` | `false` to hide framework frames, `true` to show them |
| `api-version` | `2024-03-06-preview` |
| `r` | The `redisCacheRegion` from the metadata endpoint |

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `optix/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
$showFramework = "false"
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)

$rootTree = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeDefinitions?t=$encodedTrace&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
  }

Write-Host "Activity: $($rootTree.ActivityId)| Wall: $($rootTree.WallClockMSec)ms"
Write-Host "HotPath indices: $($rootTree.HotPath -join ', ')"
```

## Response structure

The response is a JSON object with these key fields:

| Field | Description |
|---|---|
| `Nodes` | Array of root-level call tree nodes |
| `HotPath` | Array of node **indices** forming the hot path (most expensive path) |
| `WallClockMSec` | Total wall-clock time of the request in milliseconds |
| `TotalCpuTime` | Total CPU time in milliseconds |
| `TotalAwaitTime` | Total async await time |
| `TotalBlockedTime` | Total blocked/synchronous wait time |
| `ActivityId` | The profiler activity path (e.g. `/#1/1/61035/`) |
| `Language` | Programming language (e.g. `C#`) |
| `MachineName` | The machine/container that served the request |

Each **Node** has:

| Field | Description |
|---|---|
| `Meta.Label` | The method/frame name |
| `Meta.Index` | The unique node index (string) |
| `Meta.Type` | `Activity`, `StackFrame`, etc. |
| `Values.Metric` | Inclusive time in milliseconds |
| `ChildReferences` | Array of child node indices (may not be inline — see [get-child-nodes.md](get-child-nodes.md)) |
| `Nodes` | Array of inline child nodes (may be empty even if `ChildReferences` is not) |

**Important**: The root response typically only includes the top 1–2 levels of nodes inline. If `ChildReferences` lists indices that are not present in `Nodes`, you must fetch them with the `profileTreeChildren` API.
