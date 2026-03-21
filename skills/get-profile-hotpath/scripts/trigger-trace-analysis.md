# Trigger Trace Analysis

After retrieving the `redisCacheRegion` from the metadata endpoint, trigger a trace analysis by POSTing to the `profileTreeDefinitions` endpoint. This prepares the trace data for subsequent retrieval.

## Request

```
POST https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/profileTreedefinitions?api-version=2024-03-06-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `Content-Type` | `application/json` |
| `x-ms-client-request-id` | A new GUID for correlation |

### Request body

```json
{
  "traceLocationId": "<TRACE_LOCATION_ID>",
  "showFrameworkDependencies": false,
  "redisCacheRegion": "<REDIS_CACHE_REGION>"
}
```

| Field | Description |
|---|---|
| `traceLocationId` | The full `ServiceProfilerContent` string for the trace |
| `showFrameworkDependencies` | `false` to hide framework frames, `true` to show them |
| `redisCacheRegion` | The `redisCacheRegion` value obtained from the metadata endpoint |

## Redirect behaviour (important)

When the analysis results already exist, the POST returns a **302 redirect**. See [302-redirect-handling.md](../../shared/302-redirect-handling.md) for the full explanation and workaround pattern.

**Workaround**: Disable automatic redirects with `-MaximumRedirection 0`. If the response is a 302, extract the `Location` header and manually call that URL with the `Authorization` header. If the response is 200, the analysis was just triggered — proceed to [poll-analysis-status.md](poll-analysis-status.md).

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
$correlationId = [guid]::NewGuid().ToString()

$body = @{
    traceLocationId = $traceLocationId
    showFrameworkDependencies = $false
    redisCacheRegion = $redisCacheRegion
} | ConvertTo-Json

$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
}

# Disable auto-redirect to avoid auth header being stripped on 302
$response = Invoke-WebRequest `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreedefinitions?api-version=2024-03-06-preview" `
  -Method POST `
  -Headers $headers `
  -ContentType "application/json" `
  -Body $body `
  -MaximumRedirection 0 `
  -SkipHttpErrorCheck

if ($response.StatusCode -eq 302) {
    # Results already exist — follow the redirect manually with the auth header
    $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($response.Headers['Location'])"
    Write-Host "Analysis cached. Following redirect: $redirectUrl"
    $rootTree = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers $headers
    Write-Host "Activity: $($rootTree.ActivityId) | Wall: $($rootTree.WallClockMSec)ms"
} elseif ($response.StatusCode -eq 202) {
    Write-Host "Analysis triggered (202 Accepted). Poll for completion, then fetch the profile tree with a GET."
} else {
    Write-Error "Unexpected status: $($response.StatusCode) — $($response.Content)"
}
```
