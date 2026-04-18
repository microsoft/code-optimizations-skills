# Snapshot Identifiers

This document describes the identifiers used by the Snapshot Debugger dataplane API to locate and retrieve snapshot data.

## Required identifiers

The Snapshot Debugger APIs require three identifiers to uniquely locate a snapshot:

| Identifier | Query param | Description | Example |
|---|---|---|---|
| **stampId** | `st` | Azure stamp (deployment region) identifier | `westus2-ey2ahqc2dsyvq` |
| **snapshotId** | `sn` | GUID uniquely identifying the snapshot capture | `a075ba6a-3c05-4da8-9566-2a9c05def54a` |
| **snapshotTimestamp** | `t` | ISO 8601 DateTime when the snapshot was captured | `2026-03-20T21:55:35.9066175Z` |

These are passed as query parameters (`st`, `sn`, `t`) on GET requests, and in the JSON body on POST requests. When used in query parameters, URL-encode the `snapshotTimestamp` value (it contains colons and periods).

## v2 artifact location format

Snapshot artifacts in the ingestion pipeline use a v2 pipe-delimited location string:

```
v2|{stampId}|{appId}|Dump|{artifactId}|.dmp
```

Example:

```
v2|westus2-ey2ahqc2dsyvq|d40e2d66-4e93-47c2-881e-71a758e09f54|Dump|a075ba6a3c054da895662a9c05def54a|.dmp
```

| Index | Field | Description |
|---|---|---|
| 0 | Version | Always `v2` |
| 1 | Stamp ID | Regional deployment identifier |
| 2 | App ID | Application Insights app ID (GUID) |
| 3 | Artifact kind | Always `Dump` for snapshots |
| 4 | Artifact ID | Snapshot ID (GUID, no dashes) |
| 5 | Extension | `.dmp` |

## Extracting identifiers from the artifact listing

When using the `GET /api/apps/{appId}/artifacts/ingested?artifactKind=Dump` endpoint:

- **snapshotId**: Use the `artifactId` field directly (this is the snapshot GUID, without dashes — e.g., `0185cc9fd902434190dcc01ed8e2d7cd`)
- **snapshotTimestamp**: Use the `triggerTime` field (when the snapshot was captured)
- **stampId**: **Not directly available in the listing response.** Must be extracted from exception telemetry — see below.

## Extracting stampId from exception telemetry

The `stampId` is stored in Application Insights exception telemetry as the `ai.snapshot.stampid` custom dimension. Query for it:

```kql
exceptions
| where customDimensions has 'ai.snapshot.id'
| extend snapshotId = tostring(customDimensions['ai.snapshot.id']),
         stampId = tostring(customDimensions['ai.snapshot.stampid'])
| project timestamp, snapshotId, stampId, type, outerMessage
| order by timestamp desc
| take 10
```

### PowerShell script

> ⚠️ Read [az CLI query pitfalls](az-cli-query-pitfalls.md) before modifying this script. Key requirements: `--offset` is mandatory, use `--output json`, and flatten KQL to a single line.

```powershell
$appId = "<APP_ID>"
$resourceId = "<RESOURCE_ID>"  # Use resource ID for az monitor app-insights query
$timeSpan = "P7D"

$query = "exceptions | where customDimensions has 'ai.snapshot.id' | extend snapshotId = tostring(customDimensions['ai.snapshot.id']), stampId = tostring(customDimensions['ai.snapshot.stampid']) | project timestamp, snapshotId, stampId, type, outerMessage | order by timestamp desc | take 10"

$result = az monitor app-insights query --apps $resourceId --analytics-query $query --offset $timeSpan --output json | ConvertFrom-Json
$result.tables[0].rows | ForEach-Object {
    Write-Host "Time: $($_[0]) | SnapshotId: $($_[1]) | StampId: $($_[2]) | Exception: $($_[3])"
}
```

The `stampId` format is typically `{region}-{stampSuffix}`, e.g., `canadacentral-a4vf5h53fdrrq`.

> **Note**: The `snapshotId` from exception telemetry (`ai.snapshot.id`) is in compact GUID format (no dashes), matching what the `artifactId` field uses in the artifact listing. Both formats are accepted by the API.

## URL encoding

When passing `snapshotTimestamp` as a query parameter (`t`), URL-encode the value:

```powershell
$encodedTimestamp = [System.Uri]::EscapeDataString($snapshotTimestamp)
# "2026-03-20T21:55:35.9066175Z" → "2026-03-20T21%3A55%3A35.9066175Z"
```

The `stampId` and `snapshotId` typically do not require URL encoding (they contain only alphanumeric characters, dashes, and hyphens).
