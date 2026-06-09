# Trigger Debug Info Computation

POST to the `debugInfo` endpoint to trigger the debug info computation for a snapshot. This extracts the exception information, call stack frames, and variable indices from the snapshot dump.

## Request

```
POST https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/debugInfo?api-version=2025-03-19-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `Content-Type` | `application/json` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `optix/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

### Request body

```json
{
  "stampId": "{stampId}",
  "snapshotId": "{snapshotId}",
  "snapshotTimestamp": "{snapshotTimestamp}",
  "redisCacheRegion": "{redisCacheRegion}"
}
```

## PowerShell script

```powershell
$appId = "<APP_ID>"
$stampId = "<STAMP_ID>"
$snapshotId = "<SNAPSHOT_ID>"
$snapshotTimestamp = "<SNAPSHOT_TIMESTAMP>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Re-acquire token in the same command block — see skills/shared/get-access-token.md
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$body = @{
    stampId = $stampId
    snapshotId = $snapshotId
    snapshotTimestamp = $snapshotTimestamp
    redisCacheRegion = $redisCacheRegion
} | ConvertTo-Json

$skipPoll = $false
$debugInfo = $null

try {
    $triggerResponse = Invoke-WebRequest `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/debugInfo?api-version=2025-03-19-preview" `
      -Method POST -Headers @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
        "User-Agent" = $userAgent
      } -Body $body `
      -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction SilentlyContinue
} catch {
    if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
        $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($_.Exception.Response.Headers.Location)"
        Write-Host "Debug info cached (302 exception). Following redirect..."
        $debugInfo = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers @{
            "Authorization" = "Bearer $token"
            "x-ms-client-request-id" = [guid]::NewGuid().ToString()
            "User-Agent" = $userAgent
        }
        Write-Host "Debug info retrieved from cache."
        $skipPoll = $true
    } else {
        throw
    }
}

if ($skipPoll) {
    # 302 was already handled in the catch block
} elseif ($triggerResponse.StatusCode -eq 302) {
    $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($triggerResponse.Headers['Location'])"
    Write-Host "Debug info cached. Following redirect..."
    $debugInfo = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers @{
        "Authorization" = "Bearer $token"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
        "User-Agent" = $userAgent
    }
    Write-Host "Debug info retrieved from cache."
    $skipPoll = $true
} elseif ($triggerResponse.StatusCode -eq 202) {
    Write-Host "Computation triggered (202). Proceed to poll for completion."
} else {
    Write-Host "Trigger returned status: $($triggerResponse.StatusCode)"
}
```

## Response

| Status | Meaning | Next step |
|---|---|---|
| 202 | Computation triggered — job created | Poll `debugInfoComputeStatus` |
| 302 | Result cached — redirect to result | Follow redirect manually with auth header |
| 400 | Bad request — check input parameters | Fix and retry |
| 403 | Forbidden — insufficient permissions | Check access |
