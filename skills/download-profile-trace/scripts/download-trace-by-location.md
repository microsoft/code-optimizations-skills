# Download Trace by Trace Location ID

Download a profiler trace artifact using a **trace location ID** instead of an artifact ID. Use this method when `artifactId` is null in the trace listing. The API returns a JSON response containing a SAS-protected download URL.

## When to use

Use this method when:
- The trace listing returns `artifactId: null` for the selected trace and the [resolve-trace-identifiers](resolve-trace-identifiers.md) query did not return an artifact ID
- You have a trace location ID from the resolve query (`ServiceProfilerContent`) or from another source (e.g., Application Insights portal URL)

## Trace location ID format

The trace location ID is a pipe-delimited v1 string. See [trace-location-id-format.md](../../shared/trace-location-id-format.md) for the full format specification, field descriptions, and examples.

The API accepts both the 6-field prefix form (for downloading a full trace session) and the 9-field full form (for a specific activity). When the trace location ID comes from `ServiceProfilerContent` in the resolve step, it is typically the full 9-field form. Pass it as-is — there is no need to truncate it.
```

## Request

```
POST https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/artifacts/byArtifactLocation?t={traceLocationId}&api-version=2025-03-19-preview
```

> **Important:** This endpoint requires the trace location ID in **two places**:
> 1. The `t` query parameter (for controller model binding)
> 2. A JSON request body with `{"traceLocationId": "..."}` (for the authorization filter that validates the app ID)
>
> Omitting the body causes a `400 Bad Request` with `"Artifact location properties can't be fetched."`.
> Omitting the query parameter causes a `400` with `"The traceLocationId field is required."`.

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `Content-Type` | `application/json` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `perf-copilot/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

### Query Parameters

| Parameter | Required | Description |
|---|---|---|
| `t` | Yes | The trace location ID (URL-encoded) |
| `api-version` | Yes | Must be `2025-03-19-preview` or later |

### Request Body

```json
{
  "traceLocationId": "v1|{stampId}|{appId}|{machineName}|{processId}|{etlFileSessionId}|..."
}
```

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"  # e.g., "v1|stampid|appid|machine|1874|2026-03-20T21:55:35.9066175Z|/#1874/1/189/|2026-03-20T21:55:36.0751543Z|2026-03-20T21:55:39.0792972Z"
# Include the role name to avoid collisions when downloading from multiple resources,
# e.g., "trace-slowcpu-win-app-2026-03-20T214135.etl.zip"
# Check the blobUri from the listing to determine the correct file extension (.etl, .etl.zip, .netperf)
$outputPath = "<OUTPUT_FILE_PATH>"
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$encodedLocationId = [System.Uri]::EscapeDataString($traceLocationId)

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
}

# The body is required for the authorization filter; the query param is required for controller binding
$body = @{ traceLocationId = $traceLocationId } | ConvertTo-Json

# Step 1: Get the SAS-protected download URL
$response = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/byArtifactLocation?t=$encodedLocationId&api-version=2025-03-19-preview" `
  -Method POST `
  -Headers $headers `
  -Body $body

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
