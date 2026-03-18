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

$analysisResponse = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreedefinitions?api-version=2024-03-06-preview" `
  -Method POST `
  -Headers @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "x-ms-client-request-id" = $correlationId
  } `
  -Body $body

Write-Host "Trace analysis triggered successfully."
```

This step must complete before fetching the root profile tree with a GET request.
