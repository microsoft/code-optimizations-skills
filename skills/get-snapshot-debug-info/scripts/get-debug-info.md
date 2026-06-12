# Get Debug Info

Fetch the computed debug info (exception information and call stack frames) from the `debugInfo` GET endpoint. Use this after the computation has completed (polling returned `Complete` or 302).

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/debugInfo?st={stampId}&sn={snapshotId}&t={snapshotTimestamp}&r={redisCacheRegion}&api-version=2025-03-19-preview
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
| `User-Agent` | `optix/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

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

$debugInfo = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/debugInfo?st=$stampId&sn=$snapshotId&t=$encodedTimestamp&r=$redisCacheRegion&api-version=2025-03-19-preview" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
    "User-Agent" = $userAgent
  }

Write-Host "Exception: $($debugInfo.exceptionInfo.Id) — $($debugInfo.exceptionInfo.Description)"
Write-Host "Stack frames: $($debugInfo.stackFrames.Count)"

# Output the full JSON for parsing
$debugInfo | ConvertTo-Json -Depth 10
```

## Response

The response is a `DebugInfo` object:

```json
{
  "exceptionInfo": {
    "Code": 3221225477,
    "Description": "Attempted to read or write protected memory. This is often an indication that other memory is corrupt.",
    "Id": "System.AccessViolationException"
  },
  "stackFrames": [
    {
      "Name": "MyApp.Controllers.HomeController.Index()",
      "File": "HomeController.cs",
      "Line": 42,
      "Variables": [0, 1, 2],
      "CodeSnippet": 1,
      "CodeSnippetLine": 42,
      "CodeSnippetKey": "abc123"
    },
    {
      "Name": "Microsoft.AspNetCore.Mvc.Internal.ActionMethodExecutor.Execute()",
      "File": null,
      "Line": null,
      "Variables": [],
      "CodeSnippet": null,
      "CodeSnippetLine": null,
      "CodeSnippetKey": null
    }
  ]
}
```

### Key fields

| Field | Description |
|---|---|
| `exceptionInfo.Code` | Exception code (e.g., `0xC0000005` for access violation) |
| `exceptionInfo.Description` | Human-readable exception message |
| `exceptionInfo.Id` | Exception type (fully qualified name) |
| `stackFrames[].Name` | Fully qualified method name |
| `stackFrames[].File` | Source file name (may be null for framework code) |
| `stackFrames[].Line` | Source line number (may be null) |
| `stackFrames[].Variables` | Array of variable indices — use these to fetch variable values via the `/variables` endpoint |

The `Variables` array contains integer indices that reference variables in the snapshot's variable store. Use the [get-variables.md](get-variables.md) script to fetch the actual variable names, values, and types.
