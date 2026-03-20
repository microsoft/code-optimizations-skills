# List Profile Traces

Call the ingested artifacts endpoint to list available profiler trace files.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/artifacts/ingested?artifactKind=profile&timeSpan={timeSpan}&api-version=2024-03-06-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |

### Query Parameters

| Parameter | Required | Description |
|---|---|---|
| `artifactKind` | Yes | Set to `profile` to list profiler traces |
| `timeSpan` | No | ISO 8601 duration for lookback (default: `PT24H` / 24 hours). Use `P7D` for 7 days, `P30D` for 30 days. |
| `role` | No | Filter by role name (e.g., `web`, `worker`) |
| `startTime` | No | Custom range start (ISO 8601). Must also specify `endTime`. Cannot combine with `timeSpan`. |
| `endTime` | No | Custom range end (ISO 8601). Must also specify `startTime`. Cannot combine with `timeSpan`. |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$timeSpan = "P7D"
$correlationId = [guid]::NewGuid().ToString()

$response = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/ingested?artifactKind=profile&timeSpan=$timeSpan&api-version=2024-03-06-preview" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
  }

# Display results
$response | ForEach-Object {
    Write-Host "ID: $($_.artifactId) | Time: $($_.createdTimeUtc) | Role: $($_.roleName) | Machine: $($_.machineName)"
}
```

## Response

The response is a JSON array of `IngestedArtifact` objects. Key fields:

| Field | Description |
|---|---|
| `artifactId` | GUID — use this to download the trace |
| `createdTimeUtc` | When the trace was captured |
| `roleName` | The role (e.g., web, worker) |
| `machineName` | The machine that produced the trace |
| `artifactKind` | Always `profile` when filtered |

Present the list to the user and let them choose which trace to download.
