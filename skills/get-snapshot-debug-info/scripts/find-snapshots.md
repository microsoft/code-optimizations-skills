# Find Snapshots

List available snapshots and let the user pick one. This is the **default entry point** for the `get-snapshot-debug-info` skill — users typically don't have snapshot identifiers upfront.

This script lists recent snapshots from the ingested artifacts endpoint, then enriches the list with exception type information from Application Insights telemetry so the user can make an informed choice.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/artifacts/ingested?artifactKind=Dump&timeSpan={timeSpan}&api-version=2024-03-06-preview
```

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |
| `User-Agent` | `perf-copilot/{version} (commit:{hash})` — see [user-agent.md](../../shared/user-agent.md) |

## PowerShell script

This script does two things in one block:
1. Lists recent snapshot artifacts from the dataplane API
2. Queries exception telemetry to enrich each snapshot with its exception type and `stampId`

```powershell
$appId = "<APP_ID>"
$lookbackDays = 7
$timeSpan = "P${lookbackDays}D"
$offset = if ($lookbackDays -le 1) { "P1D" } elseif ($lookbackDays -le 7) { "P7D" } else { "P30D" }
$correlationId = [guid]::NewGuid().ToString()
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

# --- Step 1: List snapshot artifacts ---
$response = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/artifacts/ingested?artifactKind=Dump&timeSpan=$timeSpan&api-version=2024-03-06-preview" `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
  }

Write-Host "Found $($response.Count) snapshot(s)."

# --- Step 2: Query exception telemetry for snapshot metadata (type + stampId) ---
$query = "exceptions | where timestamp > ago(${lookbackDays}d) | where customDimensions has 'ai.snapshot.id' | extend snapshotId = tostring(customDimensions['ai.snapshot.id']), stampId = tostring(customDimensions['ai.snapshot.stampid']) | project snapshotId, stampId, type, outerMessage"

$exResult = az monitor app-insights query --app $appId --analytics-query $query --offset $offset --output json 2>$null | ConvertFrom-Json
$exMap = @{}
if ($exResult.tables[0].rows) {
    foreach ($row in $exResult.tables[0].rows) {
        $exMap[$row[0]] = @{ stampId = $row[1]; type = $row[2]; message = $row[3] }
    }
}

# --- Step 3: Present enriched list ---
Write-Host "Showing the 10 most recent:"
$i = 1
$response | Select-Object -First 10 | ForEach-Object {
    $sid = $_.artifactId -replace '-', ''
    $exInfo = $exMap[$sid]
    $exType = if ($exInfo) { $exInfo.type } else { "(unknown)" }
    Write-Host "[$i] Time: $($_.triggerTime) | Role: $($_.roleName) | Exception: $exType | ArtifactID: $($_.artifactId)"
    $i++
}
```

## Extracting snapshot identifiers

After the user selects a snapshot from the list, extract the identifiers needed for the debug info API. See [snapshot-identifiers.md](../../shared/snapshot-identifiers.md) for the full format specification.

From the listing response and the exception telemetry query (already loaded in `$exMap`):
- **`snapshotId`**: Use the `artifactId` field from the selected artifact (compact format without dashes)
- **`snapshotTimestamp`**: Use the `triggerTime` field from the selected artifact
- **`stampId`**: Look up the `stampId` from `$exMap` using the compact artifact ID as the key

```powershell
# After user picks, e.g., item 1:
$selected = ($response | Select-Object -First 10)[0]  # Adjust index based on user's choice
$snapshotId = $selected.artifactId -replace '-', ''
$snapshotTimestamp = $selected.triggerTime
$stampId = $exMap[$snapshotId].stampId

Write-Host "snapshotId: $snapshotId"
Write-Host "snapshotTimestamp: $snapshotTimestamp"
Write-Host "stampId: $stampId"
```

If the `stampId` is not found in `$exMap` (the exception telemetry query didn't return a match for this snapshot), fall back to querying directly:

```powershell
$query = "exceptions | where customDimensions has 'ai.snapshot.id' | extend sid = tostring(customDimensions['ai.snapshot.id']), stampId = tostring(customDimensions['ai.snapshot.stampid']) | where sid == '$snapshotId' | project stampId | take 1"

$result = az monitor app-insights query --app $appId --analytics-query $query --offset $timeSpan --output json | ConvertFrom-Json
$stampId = $result.tables[0].rows[0][0]
Write-Host "StampId: $stampId"
```

Present the extracted identifiers to the user for confirmation before proceeding to the debug info pipeline.
