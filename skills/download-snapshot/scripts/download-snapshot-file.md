# Download Snapshot File

Download a snapshot dump artifact by its artifact ID. The `artifactId` comes from the snapshot listing (see [list-snapshots.md](list-snapshots.md)).

The API returns a **302 redirect** to a SAS-protected blob URL. Since the SAS token in the redirect URL provides its own authentication, PowerShell can follow the redirect automatically — no special redirect handling is needed.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/artifacts/{artifactId}?api-version=2024-03-06-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `optix/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$artifactId = "<ARTIFACT_ID>"
# Include the role name in the filename to avoid collisions, e.g., "snapshot-myapp-2026-03-20T214135.dmp"
$outputPath = "<OUTPUT_FILE_PATH>"
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
}

# The endpoint returns a 302 redirect to a SAS-protected blob URL.
# PowerShell follows the redirect automatically, and the SAS token
# in the URL handles authentication — no special handling needed.
Invoke-WebRequest `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/$artifactId`?api-version=2024-03-06-preview" `
  -Method GET `
  -Headers $headers `
  -OutFile $outputPath

Write-Host "Snapshot saved to: $outputPath"
```

## Error handling

| Status | Meaning |
|---|---|
| 302 → 200 | Success — redirect followed automatically, file downloaded |
| 400 | Bad request — check artifact ID format |
| 404 | Artifact not found — the ID may be wrong or the snapshot may have expired |
| 401 | Token expired — re-acquire with `get-access-token.md` |
