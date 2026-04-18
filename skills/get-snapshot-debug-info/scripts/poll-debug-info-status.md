# Poll Debug Info Compute Status

Poll the `debugInfoComputeStatus` endpoint until the debug info computation completes. Use this after `trigger-debug-info.md` returns 202.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/debugInfoComputeStatus?st={stampId}&sn={snapshotId}&t={snapshotTimestamp}&r={redisCacheRegion}&api-version=2025-03-19-preview
```

### Query parameters

| Parameter | Short form | Description |
|---|---|---|
| StampId | `st` | Azure stamp identifier |
| SnapshotId | `sn` | Snapshot GUID |
| SnapshotTimestamp | `t` | Snapshot capture timestamp (URL-encoded) |
| RedisCacheRegion | `r` | Redis cache region from metadata |

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `perf-copilot/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

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

$encodedTimestamp = [System.Uri]::EscapeDataString($snapshotTimestamp)
$statusUri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/debugInfoComputeStatus?st=$stampId&sn=$snapshotId&t=$encodedTimestamp&r=$redisCacheRegion&api-version=2025-03-19-preview"
$maxAttempts = 45
$delaySeconds = 2

for ($i = 1; $i -le $maxAttempts; $i++) {
    try {
        $pollResponse = Invoke-WebRequest -Uri $statusUri -Method GET -Headers @{
            "Authorization" = "Bearer $token"
            "x-ms-client-request-id" = [guid]::NewGuid().ToString()
            "User-Agent" = $userAgent
        } -MaximumRedirection 0 -SkipHttpErrorCheck
    } catch {
        if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
            $location = $_.Exception.Response.Headers.Location
            if ($location -match "debugInfoComputeErrors") {
                Write-Error "Poll $i - Computation failed (302 redirect to errors endpoint: $location)."
                return
            }
            Write-Host "Poll $i - Computation complete (302)."
            break
        }
        throw
    }

    if ($pollResponse.StatusCode -eq 401) {
        Write-Host "Poll $i - 401, refreshing token..."
        $token = az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv
        Start-Sleep -Seconds $delaySeconds
        continue
    }

    if ($pollResponse.StatusCode -eq 302) {
        $location = $pollResponse.Headers['Location']
        if ($location -match "debugInfoComputeErrors") {
            Write-Error "Poll $i - Computation failed (302 redirect to errors endpoint: $location)."
            return
        }
        Write-Host "Poll $i - Computation complete (302 redirect)."
        break
    }

    if ($pollResponse.StatusCode -ne 200) {
        Write-Host "Poll $i - Status: $($pollResponse.StatusCode)"
        Start-Sleep -Seconds $delaySeconds
        continue
    }

    $status = $pollResponse.Content | ConvertFrom-Json
    Write-Host "Poll $i - Status: $($status.status)"
    if ($status.status -eq "Complete") { break }
    if ($status.status -eq "Failed") { Write-Error "Debug info computation failed."; return }
    Start-Sleep -Seconds $delaySeconds
}

if ($i -gt $maxAttempts) {
    Write-Error "Polling timed out after $maxAttempts attempts. The computation may still be running — wait and retry, or re-trigger."
    return
}
```

## Response

| Status | Meaning |
|---|---|
| 200 | Job still running — `status` field contains progress (`Running`, `Complete`, `Failed`) |
| 302 | Job complete — redirect to `debugInfo` (success) or `debugInfoComputeErrors` (failure) |
| 401 | Token expired — refresh and retry |
| 404 | Job not found — may need to re-trigger |

## Notes

- The script uses `try-catch` for 302 redirect handling, as PowerShell throws exceptions on 302 even with `-SkipHttpErrorCheck` when `-MaximumRedirection 0` is set. See [302-redirect-handling.md](../../shared/302-redirect-handling.md) for details.
- The polling loop handles 401 by refreshing the token automatically.
- Default: 45 attempts × 2 seconds = ~90 seconds max wait time.
