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

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$response = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/ingested?artifactKind=profile&timeSpan=$timeSpan&api-version=2024-03-06-preview" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
  }

# Show total count and display the 10 most recent traces
# The API can return hundreds of traces for active apps — limit output to avoid overwhelming the user
Write-Host "Found $($response.Count) trace(s). Showing the 10 most recent:"
$i = 1
$response | Select-Object -First 10 | ForEach-Object {
    $id = if ($_.artifactId) { $_.artifactId } else { "(null)" }
    Write-Host "[$i] ArtifactID: $id | Time: $($_.triggerTime) | Role: $($_.roleName) | Instance: $($_.roleInstance) | Format: $($_.format)"
    $i++
}
```

## Response

The response is a JSON array of `IngestedArtifact` objects. Key fields:

| Field | Description |
|---|---|
| `artifactId` | GUID for downloading the trace. **May be `null`** — see note below. |
| `triggerTime` | When the profiling session was triggered (ISO 8601 UTC timestamp) |
| `roleName` | The cloud role name (e.g., `web`, `worker`, app name) |
| `roleInstance` | The machine/container instance that produced the trace |
| `format` | Trace format: `Netperf` (Linux/.NET) or `Etl` (Windows) |
| `blobUri` | Internal blob storage URI for the trace file |
| `artifactKind` | Always `Profile` when filtered |
| `trigger` | What triggered the profiling session |

### When `artifactId` is null

Some traces have `artifactId: null`. This typically occurs with newer profiler versions or certain ingestion paths. When this happens, run the [resolve-trace-identifiers](resolve-trace-identifiers.md) script to query `customEvents` for the artifact ID and/or trace location ID. If that fails, the trace can still be downloaded using the **trace location ID** method described in [download-trace-by-location.md](download-trace-by-location.md).

Present the list to the user and let them choose which trace to download. Note whether `artifactId` is available or null for the selected trace, as this determines which download method to use.
