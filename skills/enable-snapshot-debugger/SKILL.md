---
name: enable-snapshot-debugger
category: setup
description: Guide users through enabling the Application Insights Snapshot Debugger for .NET on their platform. Use this when asked to enable the snapshot debugger, set up snapshot collection, or when snapshot data is missing.
---

# Enable Application Insights Snapshot Debugger

When asked to enable the Application Insights Snapshot Debugger for .NET, or when another skill (e.g., `get-snapshot-debug-info`, `download-snapshot`) determines that no snapshot data exists, follow these steps:

1. **Check investigation notes and gather inputs** — Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in the [Standard Skill Preamble](../shared/standard-skill-preamble.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values. If only a resource ID is available, resolve the app ID using [resolve-app-id.md](../shared/resolve-app-id.md).

3. **Check if the Snapshot Debugger is already active** — Run the script in [check-snapshot-status.md](scripts/check-snapshot-status.md) which performs a two-tier check:
   - **Tier 1**: Queries for exceptions with `ai.snapshot.id` custom dimensions (proves snapshots are being captured end-to-end).
   - **Tier 2**: Queries for `AppInsightsSnapshotCollectorLogs` heartbeat events (proves the Snapshot Collector process is running, even without any captured snapshots).

   Interpret the results:
   - If **snapshot-tagged exceptions** are found → the Snapshot Debugger is fully active. Inform the user and stop.
   - If **heartbeat events** are found but **no snapshots** → the Snapshot Collector IS running but hasn't captured snapshots yet. This is normal when: the debugger was just enabled, traffic is low, no exceptions have been thrown, or exceptions haven't reached the snapshot threshold (default: same exception must occur twice). Do NOT recommend re-enabling. Instead, explain the situation and suggest generating traffic that triggers exceptions.
   - If **neither** is found → the Snapshot Debugger is not enabled. Proceed to step 4.

4. **Check local source code for existing Snapshot Debugger configuration** — Before asking the user environment questions, inspect the source code in the working directory.

   **4a. Check for Snapshot Collector NuGet packages and code:**
   - Search `*.csproj` files for:
     - `Microsoft.ApplicationInsights.SnapshotCollector`
   - Search `Program.cs` or `Startup.cs` for:
     - `AddSnapshotCollector` (Classic SDK explicit registration)
   - Note: On App Service (Windows), Snapshot Debugger can be enabled **without** the NuGet package — it's preinstalled in the App Service runtime and controlled via portal toggles.

   **4b. If Snapshot Collector code IS present — run connection string match check:**
   The Snapshot Debugger is configured in code but producing no events on the target resource. A common cause is a **connection string mismatch**. Run [check-connection-string-match.md](../shared/check-connection-string-match.md) to compare the app's configured connection string against the target resource.
   - If a **mismatch** is detected → present it to the user. Connection strings are often overridden at deployment time, so a source-code mismatch doesn't necessarily mean data is going elsewhere. Ask the user to confirm before proceeding.
   - If connection strings **match** → the Snapshot Debugger is configured and pointing to the correct resource, but not producing data for another reason. Continue to step 5.
   - If **no connection strings are found locally** → the connection string may be set via environment variables or App Service configuration. Cannot verify from source code alone. Continue to step 5.

   **4c. Infer environment from source code:**
   When source code is available, attempt to infer environment answers:
   - **Runtime**: Check `<TargetFramework>` in `*.csproj` — `net6.0`, `net8.0`, etc. = .NET (modern); `net48`, `net472` = .NET Framework.
   - **Hosting**: Check for `*.bicep` or ARM templates — look for `Microsoft.Web/sites` (App Service), container resources, etc.

   If answers can be inferred, present them to the user for confirmation and skip the corresponding questions in step 5.

   **4d. If Snapshot Collector code is NOT present** → proceed to step 5.

5. **Determine the user's environment** — Ask any questions not already answered by source code inspection:

   **Question 1** (if runtime not inferred): What .NET runtime does your application target?
   - `.NET (modern)` — .NET 6, .NET 8, or later
   - `.NET Framework` — .NET Framework 4.6.2 or later

   **Question 2** (if hosting not inferred): Where is your application hosted?
   - Azure App Service (Windows)
   - Azure Functions (App Service plan)
   - Azure Cloud Services
   - Azure Virtual Machines or Virtual Machine Scale Sets
   - Azure Service Fabric
   - Other / on-premises

   > **Note**: Snapshot Debugger currently supports **Windows** environments only. Linux and containers are not supported.

6. **Provide enablement instructions** — Based on the user's answers, fetch the relevant enablement documentation and provide step-by-step instructions.

   ### Fetching enablement instructions

   **Fetch online first, fall back to local**. Use `max_length: 5000` for all `web_fetch` calls:

   | Platform | Online URL | Local fallback |
   |---|---|---|
   | App Service (Windows) | `https://learn.microsoft.com/en-us/azure/azure-monitor/snapshot-debugger/snapshot-debugger-app-service` | [enablement-overview.md](references/enablement-overview.md) |
   | Azure Functions | `https://learn.microsoft.com/en-us/azure/azure-monitor/snapshot-debugger/snapshot-debugger-function-app` | [enablement-overview.md](references/enablement-overview.md) |
   | VMs / VMSS / Cloud Services / Service Fabric / On-premises | `https://learn.microsoft.com/en-us/azure/azure-monitor/snapshot-debugger/snapshot-debugger-vm` | [enablement-overview.md](references/enablement-overview.md) |

   ### Enablement methods by platform

   | Platform | Method | Code Change? |
   |---|---|---|
   | App Service (Windows) | Azure Portal toggles (codeless) | No |
   | Azure Functions (App Service plan) | Azure Portal toggles (codeless) | No |
   | VMs / VMSS / Cloud Services | NuGet package + code | Yes |
   | Service Fabric | NuGet package + code | Yes |
   | On-premises | NuGet package + code | Yes |

   Present the enablement instructions to the user in a clear, step-by-step format. Include:
   - Prerequisites (Basic tier or higher for App Service, symbol files published)
   - The specific portal steps or code changes required
   - The `Microsoft.ApplicationInsights.SnapshotCollector` NuGet package (for code-based enablement)
   - How to verify snapshots are being collected
   - The `Application Insights Snapshot Debugger` RBAC role requirement

   **For App Service (codeless)**:
   1. Navigate to App Service in the Azure portal
   2. Select **Monitoring → Application Insights**
   3. Turn on Application Insights (or select existing resource)
   4. Under the .NET tab, switch both **Snapshot Debugger** toggles to **On**
   5. Click **Apply**

   **For code-based enablement (VMs, VMSS, Service Fabric, on-premises)**:

   ```bash
   dotnet add package Microsoft.ApplicationInsights.SnapshotCollector
   ```

   ```csharp
   // In Program.cs or Startup.cs
   builder.Services.AddApplicationInsightsTelemetry();
   // Snapshot Collector is auto-registered as a telemetry processor
   // when the NuGet package is installed. No explicit AddSnapshotCollector() needed
   // in most cases — the package auto-discovers via TelemetryProcessor configuration.
   ```

   Alternatively, configure in `appsettings.json`:
   ```json
   {
     "ApplicationInsights": {
       "ConnectionString": "<YOUR_CONNECTION_STRING>"
     },
     "SnapshotCollectorConfiguration": {
       "IsEnabled": true,
       "ThresholdForSnapshotting": 1,
       "MaximumSnapshotsRequired": 3,
       "SnapshotsPerTenMinutesLimit": 1
     }
   }
   ```

7. **Verify the Snapshot Debugger is producing data** — After the user has enabled the Snapshot Debugger:
   - The application must throw an exception **twice** for the same problem before a snapshot is created (default `ThresholdForSnapshotting: 1` means 1 *additional* occurrence after the first).
   - Wait 10–15 minutes for snapshots to be uploaded.
   - Re-run the [check-snapshot-status.md](scripts/check-snapshot-status.md) script to confirm snapshot-tagged exceptions are appearing.

   If no snapshots appear after the expected wait time, suggest troubleshooting:
   - Verify the connection string is correct
   - Ensure exceptions are actually being thrown (check the `exceptions` table)
   - Check that symbols (.pdb files) are published alongside the application
   - Verify the user has the `Application Insights Snapshot Debugger` RBAC role
   - For App Service: ensure the app is on Basic tier or higher
   - Check application logs for Snapshot Collector startup messages

   Once snapshots are confirmed, suggest the user run the `get-snapshot-debug-info` skill to inspect exception details, or `download-snapshot` to get the dump file for offline analysis.

## Key facts

- Snapshots are captured on **first-chance exceptions** that are also reported via `TrackException`
- Default: snapshot created after the same exception occurs **twice** (`ThresholdForSnapshotting: 1`)
- Maximum **50 snapshots per day** can be uploaded
- Snapshot data is stored for **15 days**
- **Windows only** — Linux and containers are not currently supported
- Minimal CPU/memory overhead — snapshots are created via suspended process clones
- Only one Snapshot Collector per application
- Snapshots may contain **personal data** in variable values — stored in the same region as the Application Insights resource

## References

- [Enablement Overview](references/enablement-overview.md)
- [Check Snapshot Status](scripts/check-snapshot-status.md)
- [Investigation Notes](../shared/investigation-notes.md)
- [resolve-app-id.md](../shared/resolve-app-id.md)
- [az CLI Query Pitfalls](../shared/az-cli-query-pitfalls.md)
