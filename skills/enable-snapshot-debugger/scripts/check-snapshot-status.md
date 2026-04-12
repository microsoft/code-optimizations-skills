# Check Snapshot Debugger Status

Queries Application Insights for two types of telemetry to determine whether the Snapshot Debugger is enabled and actively collecting snapshots.

The Snapshot Debugger emits two types of signals:

| Signal | Event | Description |
|---|---|---|
| **Heartbeat** (Collector running) | `AppInsightsSnapshotCollectorLogs` custom event with `EventName: Heartbeat` | Emitted every ~30 minutes by the Snapshot Collector process. Proves the collector is running even if no snapshots have been captured. Contains stats like `TrackExceptionCalls`, `FirstChanceExceptions`, `SnapshotRateLimitExceeded`. |
| **Snapshot captured** | Exception with `ai.snapshot.id` custom dimension | Added to exception telemetry when a snapshot is actually captured and uploaded. Proves the full pipeline is working end-to-end. |

A heartbeat can exist **without** any snapshot-tagged exceptions — this means the collector is running but either no exceptions have been thrown, or exceptions haven't reached the snapshot threshold (default: same exception must occur twice).

## Query

### Tier 1: Check for snapshot-tagged exceptions

```kql
exceptions
| where timestamp > ago(7d)
| where customDimensions has 'ai.snapshot.id'
| extend snapshotId = tostring(customDimensions['ai.snapshot.id']),
         stampId = tostring(customDimensions['ai.snapshot.stampid'])
| summarize SnapshotCount = count(),
            LastSnapshot = max(timestamp),
            UniqueExceptions = dcount(type)
  by type
| order by SnapshotCount desc
```

### Tier 2: Check for collector heartbeat

```kql
customEvents
| where timestamp > ago(7d)
| where name == 'AppInsightsSnapshotCollectorLogs'
| extend eventName = tostring(customDimensions.EventName)
| where eventName == 'Heartbeat'
| summarize HeartbeatCount = count(),
            LastHeartbeat = max(timestamp),
            TrackExceptionCalls = sum(toint(customMeasurements.TrackExceptionCalls)),
            FirstChanceExceptions = sum(toint(customMeasurements.FirstChanceExceptions))
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `resourceId` | — | Application Insights resource ID (full ARM path) or app ID (GUID). |
| `lookbackDays` | `7` | How many days to look back. Use `30` for a wider check. |

## Script

> ⚠️ Read [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md) before modifying this script.

```powershell
$resourceId = "<RESOURCE_ID>"
$lookbackDays = 7
$offset = if ($lookbackDays -le 1) { "P1D" } elseif ($lookbackDays -le 7) { "P7D" } else { "P30D" }

# --- Tier 1: Check for snapshot-tagged exceptions ---
$query1 = "exceptions | where timestamp > ago(${lookbackDays}d) | where customDimensions has 'ai.snapshot.id' | extend snapshotId = tostring(customDimensions['ai.snapshot.id']) | summarize SnapshotCount = count(), LastSnapshot = max(timestamp), UniqueExceptions = dcount(type) by type | order by SnapshotCount desc"

$result1 = az monitor app-insights query --apps "$resourceId" --analytics-query "$query1" --offset $offset --output json 2>&1
$snapshotRows = $null
$totalSnapshots = 0

if ($result1 -and $result1 -notmatch "ERROR") {
    try {
        $parsed1 = $result1 | ConvertFrom-Json
        $snapshotRows = $parsed1.tables[0].rows
        foreach ($row in $snapshotRows) { $totalSnapshots += $row[1] }
    } catch { }
}

# --- Tier 2: Check for collector heartbeat ---
$query2 = "customEvents | where timestamp > ago(${lookbackDays}d) | where name == 'AppInsightsSnapshotCollectorLogs' | extend eventName = tostring(customDimensions.EventName) | where eventName == 'Heartbeat' | summarize HeartbeatCount = count(), LastHeartbeat = max(timestamp), TrackExceptionCalls = sum(toint(customMeasurements.TrackExceptionCalls)), FirstChanceExceptions = sum(toint(customMeasurements.FirstChanceExceptions))"

$result2 = az monitor app-insights query --apps "$resourceId" --analytics-query "$query2" --offset $offset --output json 2>&1
$heartbeatCount = 0
$lastHeartbeat = $null
$trackExceptionCalls = 0
$firstChanceExceptions = 0

if ($result2 -and $result2 -notmatch "ERROR") {
    try {
        $parsed2 = $result2 | ConvertFrom-Json
        $hbRows = $parsed2.tables[0].rows
        if ($hbRows -and $hbRows.Count -gt 0) {
            $heartbeatCount = $hbRows[0][0]
            $lastHeartbeat = $hbRows[0][1]
            $trackExceptionCalls = $hbRows[0][2]
            $firstChanceExceptions = $hbRows[0][3]
        }
    } catch { }
}

# --- Interpret results ---
if ($totalSnapshots -gt 0) {
    Write-Host "Snapshot Debugger is ACTIVE and capturing snapshots."
    Write-Host ""
    foreach ($row in $snapshotRows) {
        Write-Host "  Exception: $($row[0])"
        Write-Host "    Snapshots: $($row[1]) | Last: $($row[2]) | Unique: $($row[3])"
    }
    Write-Host ""
    Write-Host "Total snapshots in the last $lookbackDays days: $totalSnapshots"
    if ($heartbeatCount -gt 0) {
        Write-Host "Collector heartbeats: $heartbeatCount (last: $lastHeartbeat)"
    }
} elseif ($heartbeatCount -gt 0) {
    Write-Host "Snapshot Collector IS RUNNING but has NOT captured any snapshots."
    Write-Host ""
    Write-Host "  Heartbeats: $heartbeatCount (last: $lastHeartbeat)"
    Write-Host "  TrackException calls observed: $trackExceptionCalls"
    Write-Host "  FirstChance exceptions observed: $firstChanceExceptions"
    Write-Host ""
    if ($trackExceptionCalls -eq 0 -and $firstChanceExceptions -eq 0) {
        Write-Host "No exceptions have been thrown. The collector is running but has nothing to snapshot."
        Write-Host "Suggestion: generate traffic that triggers exceptions, then wait 10-15 minutes."
    } else {
        Write-Host "Exceptions ARE being thrown but no snapshots were captured."
        Write-Host "Possible reasons:"
        Write-Host "  1. Exceptions haven't reached the snapshot threshold (default: same exception must occur twice)"
        Write-Host "  2. The daily snapshot limit (50) has been reached"
        Write-Host "  3. The rate limit (1 per 10 minutes) is throttling captures"
        Write-Host "  4. Memory or access issues preventing minidump creation"
    }
    Write-Host ""
    Write-Host "The Snapshot Debugger IS enabled. Do NOT recommend re-enabling."
} else {
    Write-Host "No Snapshot Debugger activity found in the last $lookbackDays days."
    Write-Host "The Snapshot Debugger is NOT enabled."
    Write-Host ""
    Write-Host "Proceed with enablement steps."
}
```

## Interpreting results

| Snapshot-tagged exceptions | Collector heartbeat | Meaning | Next step |
|---|---|---|---|
| Found | Found | Full success — collector running and capturing snapshots | Proceed with `get-snapshot-debug-info` or `download-snapshot` |
| **None** | Found | Collector is running but no snapshots captured | Do NOT re-enable. Check exception threshold, rate limits, or wait for exceptions to occur |
| **None** | **None** | Snapshot Debugger is not enabled | Proceed with enablement steps |

### Key insight: heartbeat without snapshots

The `AppInsightsSnapshotCollectorLogs` heartbeat with `EventName: Heartbeat` is emitted every ~30 minutes regardless of whether exceptions occur. Its `customMeasurements` contain diagnostic counters:

| Measurement | Description |
|---|---|
| `TrackExceptionCalls` | Number of `TrackException` calls seen since last heartbeat |
| `FirstChanceExceptions` | Number of first-chance exceptions observed |
| `SnapshotRateLimitExceeded` | Number of times the rate limit prevented a snapshot |
| `SnapshotDailyRateLimitReached` | Number of times the daily limit (50) was hit |
| `CannotSnapshotDueToMemoryUsage` | Number of times memory was too high to snapshot |
| `CollectionPlanComplete` | Number of completed collection plans |

These counters help diagnose *why* no snapshots are being captured when the collector IS running.

## Widening the check

If the default 7-day window returns zero, try 30 days before concluding the Snapshot Debugger is disabled:

```powershell
$lookbackDays = 30
$offset = "P30D"
```
