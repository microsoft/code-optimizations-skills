# Snapshot Debugger Enablement Overview

> **Sources**:
> - https://learn.microsoft.com/en-us/azure/azure-monitor/snapshot-debugger/snapshot-debugger
> - https://learn.microsoft.com/en-us/azure/azure-monitor/snapshot-debugger/snapshot-debugger-app-service
> - https://learn.microsoft.com/en-us/azure/azure-monitor/snapshot-debugger/snapshot-debugger-vm
> **Last synced**: 2026-04-09
> **Note**: This is a local fallback copy. The SKILL.md instructs the agent to fetch the latest platform-specific page online first.

## Supported environments

| Platform | Supported | Method |
|---|---|---|
| Azure App Service (Windows) | Yes | Portal toggles (codeless) |
| Azure Functions (App Service plan) | Yes | Portal toggles (codeless) |
| Azure Cloud Services | Yes | NuGet package + code |
| Azure VMs / VMSS | Yes | NuGet package + code |
| Azure Service Fabric | Yes | NuGet package + code |
| On-premises Windows machines | Yes | NuGet package + code |
| Linux / Containers | **Not supported** | — |

**Runtime support**:
- .NET Framework 4.6.2 and newer
- .NET 6.0 or later on Windows

## App Service (Windows) — codeless, no code change

1. Navigate to your App Service in the [Azure portal](https://portal.azure.com/)
2. Select **Monitoring → Application Insights**
3. Click **Turn on Application Insights** (or select an existing resource)
4. Under the **.NET** tab, set Collection level to **Recommended**
5. Switch both **Snapshot Debugger** toggles to **On**
6. Click **Apply**

**Prerequisites**:
- **Basic tier or higher** — Free and Shared tiers don't have enough memory/disk for snapshots
- The Consumption plan for Functions is **not supported**
- **Always on** is recommended for consistent snapshot collection

**Cross-subscription / manual app settings** (when not using the portal toggle):

| App Setting | Value |
|---|---|
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | From App Insights Overview page |
| `SnapshotDebugger_EXTENSION_VERSION` | `~1` or `disabled` |
| `DiagnosticServices_EXTENSION_VERSION` | `~3` |

## Azure Functions — codeless, no code change

Same as App Service. Enable via the Azure Portal. Requires **App Service plan** (not Consumption plan).

## VMs / VMSS / Cloud Services / Service Fabric / On-premises — NuGet package

### Step 1: Install the NuGet package

```bash
dotnet add package Microsoft.ApplicationInsights.SnapshotCollector
```

### Step 2: Configure Application Insights

Ensure Application Insights is set up in your application:

```csharp
// Program.cs
builder.Services.AddApplicationInsightsTelemetry();
```

The Snapshot Collector NuGet package auto-registers itself as a telemetry processor. In most cases, no explicit `AddSnapshotCollector()` call is needed.

### Step 3: Configure snapshot collection (optional)

Add to `appsettings.json` to customize behavior:

```json
{
  "ApplicationInsights": {
    "ConnectionString": "<YOUR_CONNECTION_STRING>"
  },
  "SnapshotCollectorConfiguration": {
    "IsEnabled": true,
    "ThresholdForSnapshotting": 1,
    "MaximumSnapshotsRequired": 3,
    "SnapshotsPerTenMinutesLimit": 1,
    "MaximumCollectionPlanSize": 50,
    "IsEnabledInDeveloperMode": false
  }
}
```

### Step 4: Publish symbols

Symbol files (`.pdb`) must be available alongside the application DLLs for the Snapshot Debugger to decode variables and provide source-level debugging:

- Visual Studio 2017 15.2+ publishes symbols for release builds by default
- For older versions, add to your `.pubxml`: `<ExcludeGeneratedDebugSymbol>False</ExcludeGeneratedDebugSymbol>`
- Symbols must be in the same folder as the application `.dll` (typically `wwwroot/bin`)

## Verifying snapshots are collected

1. Trigger an exception in the application (the same exception must occur **twice** — `ThresholdForSnapshotting` default is 1 additional occurrence)
2. Wait **10–15 minutes** for the snapshot to be uploaded
3. Check for snapshot-tagged exceptions in Application Insights:

```kql
exceptions
| where timestamp > ago(1h)
| where customDimensions has 'ai.snapshot.id'
| project timestamp, type, outerMessage,
    snapshotId = tostring(customDimensions['ai.snapshot.id'])
```

Look for these log messages in application logs:

```
SnapshotCollector - accepting exception
SnapshotCollector - triggering snapshot
Finished snapshot upload. Exit code: 0
```

## Troubleshooting

- **No snapshots after enabling**: Ensure exceptions are being thrown and reported via `TrackException`. The same exception must occur twice before a snapshot is created.
- **50 snapshot daily limit**: Check if the limit has been reached. Reset happens at midnight UTC.
- **Symbols missing**: Variables will show as "Cannot obtain value" if PDB files are not deployed.
- **Deoptimization**: On App Service, the Snapshot Debugger can deoptimize throwing methods. For other environments, some local variables may not be visible in Release builds.
- **RBAC**: The user must have the `Application Insights Snapshot Debugger` role to view snapshots.

## Key constraints

- Minimal overhead — snapshots via suspended process clones
- Default: snapshot after **2 occurrences** of the same exception
- Maximum **50 snapshots per day**
- Rate limit: **1 snapshot per 10 minutes** (configurable)
- Snapshot data deleted after **15 days**
- **Windows only** — Linux and containers not supported
- Snapshots may contain **personal data** in variable values
