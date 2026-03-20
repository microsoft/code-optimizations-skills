# Download Trace by Artifact ID

Download a profiler trace artifact by its artifact ID. This method requires a **non-null `artifactId`** from the trace listing. If `artifactId` is null, use the [trace location ID method](download-trace-by-location.md) instead.

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

## PowerShell script

```powershell
$appId = "<APP_ID>"
$artifactId = "<ARTIFACT_ID>"
# Derive a meaningful filename from the trace timestamp, e.g., "trace-2026-03-20T214135.etl"
# Check the blobUri from the listing to determine the correct file extension (.etl, .etl.zip, .netperf)
$outputPath = "<OUTPUT_FILE_PATH>"
$correlationId = [guid]::NewGuid().ToString()

$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
}

# The endpoint returns a 302 redirect to a SAS-protected blob URL.
# PowerShell follows the redirect automatically, and the SAS token
# in the URL handles authentication — no special handling needed.
Invoke-WebRequest `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/$artifactId`?api-version=2024-03-06-preview" `
  -Method GET `
  -Headers $headers `
  -OutFile $outputPath

Write-Host "Trace saved to: $outputPath"
```

## Error handling

| Status | Meaning |
|---|---|
| 302 → 200 | Success — redirect followed automatically, file downloaded |
| 400 | Bad request — check artifact ID format |
| 404 | Artifact not found — the ID may be wrong or the artifact may have expired |
| 401 | Token expired — re-acquire with `get-access-token.md` |
