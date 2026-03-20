# Download Trace by Trace Location ID

Download a profiler trace artifact using a **trace location ID** instead of an artifact ID. Use this method when `artifactId` is null in the trace listing. The API returns a JSON response containing a SAS-protected download URL.

## When to use

Use this method when:
- The trace listing returns `artifactId: null` for the selected trace
- You have a trace location ID from another source (e.g., Application Insights portal URL)

## Trace location ID format

The trace location ID is a pipe-delimited string with the following structure:

```
v1|{stampId}|{appId}|{machineName}|{processId}|{etlFileSessionId}
```

| Part | Description |
|---|---|
| `v1` | Version identifier (always `v1` for this format) |
| `stampId` | The stamp/deployment identifier for the Application Insights backend |
| `appId` | The Application Insights app ID (GUID, lowercase with hyphens) |
| `machineName` | The machine or container instance name (maps to `roleInstance` from the trace listing) |
| `processId` | The process ID (integer, must be non-zero; use `1` if unknown) |
| `etlFileSessionId` | The profiling session start time in UTC (ISO 8601 format, maps to `triggerTime` from the trace listing) |

### Example

```
v1|mystamp|d40e2d66-4e93-47c2-881e-71a758e09f54|8666f5e97d3e|1|2026-03-20T21:41:35.8314098Z
```

## Request

```
POST https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/artifacts/byArtifactLocation?t={traceLocationId}&api-version=2025-03-19-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |

### Query Parameters

| Parameter | Required | Description |
|---|---|---|
| `t` | Yes | The trace location ID (URL-encoded) |
| `api-version` | Yes | Must be `2025-03-19-preview` or later |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"  # e.g., "v1|stampid|appid|machine|1|2026-03-20T21:41:35.8314098Z"
# Derive a meaningful filename from the trace timestamp, e.g., "trace-2026-03-20T214135.etl.zip"
# Check the blobUri from the listing to determine the correct file extension (.etl, .etl.zip, .netperf)
$outputPath = "<OUTPUT_FILE_PATH>"
$correlationId = [guid]::NewGuid().ToString()

$encodedLocationId = [System.Uri]::EscapeDataString($traceLocationId)

$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
}

# Step 1: Get the SAS-protected download URL
$response = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/byArtifactLocation?t=$encodedLocationId&api-version=2025-03-19-preview" `
  -Method POST `
  -Headers $headers

$downloadUrl = $response.downloadUrl
Write-Host "Download URL obtained."

# Step 2: Download the trace file using the SAS URL
Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath

Write-Host "Trace saved to: $outputPath"
```

## Error handling

| Status | Meaning |
|---|---|
| 200 | Success — response contains `downloadUrl` with SAS-protected blob URL |
| 400 | Bad request — check trace location ID format |
| 403 | Forbidden — the app ID in the trace location doesn't match the request |
| 404 | Artifact not found — the trace may have expired or the location ID is incorrect |
| 401 | Token expired — re-acquire with `get-access-token.md` |
