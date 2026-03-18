# Get Child Nodes

The root profile tree only includes the top 1–2 levels of nodes inline. Remaining nodes referenced in `ChildReferences` must be fetched using the `profileTreeChildren` endpoint.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/profileTreeChildren?t={traceLocationId}&c={childIndex1}&c={childIndex2}&...&f={showFramework}&api-version=2024-03-06-preview&r={redisCacheRegion}
```

### Query parameters

| Parameter | Description |
|---|---|
| `t` | The trace location ID (same URL-encoded value as the root call) |
| `c` | A child node index to fetch (repeat for each index, e.g. `c=32&c=33&c=34`) |
| `f` | `false` to hide framework frames, `true` to show them |
| `api-version` | `2024-03-06-preview` |
| `r` | The `redisCacheRegion` from the metadata endpoint |

### Headers

Same as the root tree call (`Authorization` and `x-ms-client-request-id`).

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
$showFramework = "false"
$correlationId = [guid]::NewGuid().ToString()

# pendingIndices: array of node index strings to fetch, e.g. @("32", "33", "34")
$pendingIndices = @("<INDEX1>", "<INDEX2>")

$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
$childParams = ($pendingIndices | ForEach-Object { "c=$([System.Uri]::EscapeDataString($_))" }) -join "&"

$childNodes = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeChildren?t=$encodedTrace&$childParams&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
  }

# childNodes is a JSON array of node objects
foreach ($node in $childNodes) {
    Write-Host "[$($node.Meta.Index)] $($node.Values.Metric)ms - $($node.Meta.Label)"
}
```

## Response

A JSON **array** of node objects. Each node has the same structure as described in [get-profile-tree.md](get-profile-tree.md) (with `Meta`, `Values`, `ChildReferences`, `Nodes`).

## Iteration strategy

Repeat fetching until all hot path nodes are loaded:

1. Start with the `HotPath` indices from the root tree response.
2. Collect all indices that appear in `ChildReferences` but are not yet loaded.
3. Call `profileTreeChildren` with those pending indices.
4. From the returned nodes, collect any new `ChildReferences` not yet loaded.
5. Repeat (up to ~10 rounds) until no more pending indices remain.

This ensures the full hot path is expanded and can be displayed as a complete call tree.
