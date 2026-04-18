# Get Snapshot Debugger Metadata

Call the `snapshotDebuggerMetadata` endpoint to retrieve the `redisCacheRegion` value. This value is required for all subsequent debug info and download status APIs.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/snapshotDebuggerMetadata?api-version=2025-03-19-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `perf-copilot/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Re-acquire token in the same command block — see skills/shared/get-access-token.md
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$metadataResponse = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/snapshotDebuggerMetadata?api-version=2025-03-19-preview" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
  }

$redisCacheRegion = $metadataResponse.redisCacheRegion
Write-Host "redisCacheRegion: $redisCacheRegion"
```

## Response

```json
{
  "redisCacheRegion": "prod-eastus2-vlvh6fe7r2qse"
}
```

Store the `redisCacheRegion` value — it is passed as the `r` query parameter in all subsequent calls.
