# List Snapshots

Call the ingested artifacts endpoint to list available snapshot dump files.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/artifacts/ingested?artifactKind=Dump&timeSpan={timeSpan}&api-version=2024-03-06-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `optix/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

### Query parameters

| Parameter | Required | Description |
|---|---|---|
| `artifactKind` | Yes | Set to `Dump` to list snapshot dumps |
| `timeSpan` | No | ISO 8601 duration for lookback (default: `PT24H` / 24 hours). Use `P7D` for 7 days, `P30D` for 30 days. |
| `role` | No | Filter by role name (e.g., `web`, `worker`) |
| `startTime` | No | Custom range start (ISO 8601). Must also specify `endTime`. Cannot combine with `timeSpan`. |
| `endTime` | No | Custom range end (ISO 8601). Must also specify `startTime`. Cannot combine with `timeSpan`. |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$timeSpan = "P7D"
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$response = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/ingested?artifactKind=Dump&timeSpan=$timeSpan&api-version=2024-03-06-preview" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
  }

# Show total count and display the 10 most recent snapshots
# The API can return many snapshots for active apps — limit output to avoid overwhelming the user
Write-Host "Found $($response.Count) snapshot(s). Showing the 10 most recent:"
$i = 1
$response | Select-Object -First 10 | ForEach-Object {
    $id = if ($_.artifactId) { $_.artifactId } else { "(null)" }
    Write-Host "[$i] ArtifactID: $id | Time: $($_.triggerTime) | Role: $($_.roleName) | Instance: $($_.roleInstance)"
    $i++
}
```

## Response

The response is a JSON array of `IngestedArtifact` objects. Key fields:

| Field | Description |
|---|---|
| `artifactId` | GUID for downloading the snapshot. |
| `triggerTime` | When the snapshot was captured (ISO 8601 UTC timestamp) |
| `roleName` | The cloud role name (e.g., `web`, `worker`, app name) |
| `roleInstance` | The machine/container instance that produced the snapshot |
| `blobUri` | Internal blob storage URI for the snapshot file |
| `artifactKind` | Always `Dump` when filtered |

Present the list to the user and let them choose which snapshot to download.
