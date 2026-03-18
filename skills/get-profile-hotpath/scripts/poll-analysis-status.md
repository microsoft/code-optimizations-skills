# Poll Trace Analysis Status

After triggering the trace analysis, poll the `profileTreeComputeStatus` endpoint until the analysis is complete before fetching the profile tree.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/profileTreeComputeStatus?t={traceLocationId}&f={showFramework}&api-version=2024-03-06-preview&r={redisCacheRegion}
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

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
$showFramework = "false"
$correlationId = [guid]::NewGuid().ToString()

$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
$statusUri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeComputeStatus?t=$encodedTrace&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion"
$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
}

$maxAttempts = 30
$delaySeconds = 2

for ($i = 1; $i -le $maxAttempts; $i++) {
    $status = Invoke-RestMethod -Uri $statusUri -Method GET -Headers $headers
    Write-Host "Poll $i — Status: $($status.status)"

    if ($status.status -eq "Complete") {
        Write-Host "Trace analysis is complete."
        break
    }

    if ($status.status -eq "Failed") {
        Write-Error "Trace analysis failed: $($status | ConvertTo-Json -Depth 5)"
        break
    }

    Start-Sleep -Seconds $delaySeconds
}

if ($i -gt $maxAttempts) {
    Write-Error "Trace analysis did not complete within $maxAttempts attempts."
}
```

## Behaviour

- Poll every 2 seconds, up to 30 attempts (roughly 60 seconds).
- The `status` field in the response indicates progress. Stop polling when it returns `Complete` or `Failed`.
- Once complete, proceed to fetch the root profile tree.
