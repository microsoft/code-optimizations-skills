---
name: enable-profiler
description: Guide users through enabling the Application Insights Profiler for .NET on their platform. Use this when asked to enable the profiler, set up profiling, or when profiler data is missing.
---

# Enable Application Insights Profiler

When asked to enable the Application Insights Profiler for .NET, or when another skill (e.g., `perf-optimization`) determines that no profiler data exists, follow these steps:

1. **Check investigation notes and gather inputs** — Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

2. **Identify the Application Insights resource** — If the investigation notes didn't have the resource or the user wants a different one, follow the steps in the [Standard Skill Preamble](../shared/standard-skill-preamble.md). After the resource is confirmed, **write or update `investigation-notes.md`** with the confirmed values. If only a resource ID is available, resolve the app ID using [resolve-app-id.md](../shared/resolve-app-id.md).

3. **Check if the profiler is already active** — Run the script in [check-profiler-status.md](scripts/check-profiler-status.md) to query for both `ServiceProfilerIndex` (session-level) and `ServiceProfilerSample` (request-level) events.
   - If both event types are found → the profiler is already enabled and capturing request data — inform the user and stop.
   - If only `ServiceProfilerIndex` events exist (no `ServiceProfilerSample`) → the profiler IS running but is not capturing request-level samples. This is typically a traffic or trigger issue, not an enablement issue. Inform the user the profiler is enabled, and suggest checking traffic volume and trigger thresholds rather than re-enabling.
   - If neither event type is found → the profiler is not enabled. Proceed to step 4.

4. **Check local source code for existing profiler configuration** — Before asking the user environment questions, inspect the source code in the working directory to determine whether the profiler is already configured in code and whether the connection string matches the target resource.

   **4a. Check for profiler NuGet packages and code:**
   - Search `*.csproj` files for profiler NuGet references:
     - `Microsoft.ApplicationInsights.Profiler.AspNetCore` (classic SDK / EventPipe)
     - `Azure.Monitor.OpenTelemetry.Profiler` (OpenTelemetry / EventPipe)
   - Search `Program.cs` or `Startup.cs` for profiler registration calls:
     - `AddServiceProfiler` (classic SDK)
     - `AddAzureMonitorProfiler` (OpenTelemetry)

   **4b. If profiler code IS present — run connection string match check:**
   The profiler is configured in code but producing no events on the target resource. A common cause is a **connection string mismatch** — the app may be sending data to a different App Insights resource. Run [check-connection-string-match.md](../shared/check-connection-string-match.md) to compare the app's configured connection string against the target resource.
   - If a **mismatch** is detected → present it to the user as a possible explanation (see the troubleshooting guidance in `check-connection-string-match.md`). Note that connection strings are often overridden at deployment time, so a source-code mismatch does not necessarily mean the app is sending data elsewhere. Ask the user to confirm which scenario applies before deciding next steps. **Do not proceed with enablement steps** until the mismatch is resolved or confirmed as a non-issue.
   - If connection strings **match** → the profiler is configured and pointing to the correct resource, but not producing data for another reason. Continue to step 5.
   - If **no connection strings are found locally** → the app's connection string may be set via environment variables, App Service configuration, or CI/CD at deployment time. Cannot verify from source code alone. Continue to step 5 and consider asking the user how the connection string is configured.

   **4c. Infer environment from source code:**
   When source code is available, attempt to infer the answers to the environment questions below before asking them. This avoids redundant questions when the answers are already visible:
   - **Runtime**: Check `<TargetFramework>` in `*.csproj` — values like `net6.0`, `net8.0`, `net9.0`, `net10.0` indicate .NET (modern); `net48`, `net472` indicate .NET Framework.
   - **Hosting**: Check for `*.bicep` or ARM template files — look for `kind: 'linux'` vs `kind: 'app'`, `Microsoft.Web/sites` (App Service), `Microsoft.ContainerInstance` (ACI), `Microsoft.App/containerApps` (Container Apps).
   - **SDK**: Check `*.csproj` for `Azure.Monitor.OpenTelemetry.AspNetCore` (OTel) vs `Microsoft.ApplicationInsights.AspNetCore` (classic).

   If all three answers can be inferred, present them to the user for confirmation and skip the corresponding questions in step 5. If any are ambiguous, ask only the questions that couldn't be inferred.

   **4d. If profiler code is NOT present** → proceed to step 5 to determine the environment and provide full enablement instructions.

5. **Determine the user's environment** — Ask the user any questions not already answered by source code inspection in step 4 (use multiple-choice where possible):

   **Question 1** (if runtime not inferred): What .NET runtime does your application target?
   - `.NET (modern)` — .NET 6, .NET 8, or later
   - `.NET Framework` — .NET Framework 4.x

   **Question 2** (if hosting not inferred): Where is your application hosted?
   - Azure App Service (Windows)
   - Azure App Service (Linux)
   - Containers (AKS, Container Apps, Container Instances)
   - Azure Functions (App Service plan)
   - Azure Virtual Machines or Virtual Machine Scale Sets
   - Azure Service Fabric
   - Other / not sure

   **Question 3** (if SDK not inferred, and .NET modern with EventPipe applicable): Which Application Insights SDK are you using?
   - Azure Monitor OpenTelemetry distribution (`Azure.Monitor.OpenTelemetry.AspNetCore`)
   - Classic Application Insights SDK (`Microsoft.ApplicationInsights.AspNetCore`)
   - Not sure / not set up yet

6. **Select the profiler agent and provide enablement instructions** — Based on the user's answers (or inferred values from step 4), determine the correct profiler agent and fetch the relevant enablement documentation.

   ### Selecting the profiler agent

   First, determine the correct agent using the selection guide. **Fetch online first, fall back to local**:
   - Try: `web_fetch` with URL `https://github.com/Azure/azuremonitor-opentelemetry-profiler-net/blob/main/docs/ProfilerAgentSelectionGuide.md` and `max_length: 5000`
   - If fetch fails: read [profiler-agent-selection-guide.md](references/profiler-agent-selection-guide.md)

   Apply the decision tree:

   | .NET Runtime | Hosting | Profiler Agent | Code Change Required? |
   |---|---|---|---|
   | .NET Framework | Any Windows Azure service | **ETW** | No |
   | .NET (modern) | App Service (Windows) | **ETW** (simplest) or **EventPipe** | No for ETW; Yes for EventPipe |
   | .NET (modern) | App Service (Linux) | **EventPipe** | Yes |
   | .NET (modern) | Containers (AKS, Container Apps, ACI) | **EventPipe** | Yes |
   | .NET (modern) | Azure Functions (App Service plan) | **ETW** | No |
   | .NET (modern) | VMs / VMSS | **ETW** or **EventPipe** | No for ETW; Yes for EventPipe |
   | .NET (modern) | Service Fabric | **ETW** | No |

   > ⚠️ **Do NOT use both ETW and EventPipe at the same time** — the combined overhead is not recommended.

   ### Fetching enablement instructions

   Based on the selected agent and platform, fetch **only the one relevant page**. Use `max_length: 5000` for all `web_fetch` calls:

   | Agent | Platform | Online URL | Local fallback |
   |---|---|---|---|
   | ETW | App Service (Windows) | `https://learn.microsoft.com/en-us/azure/azure-monitor/profiler/profiler` | [enablement-overview.md](references/enablement-overview.md) |
   | ETW | Azure Functions | `https://learn.microsoft.com/en-us/azure/azure-monitor/profiler/profiler-azure-functions` | [enablement-overview.md](references/enablement-overview.md) |
   | ETW | VMs / VMSS | `https://learn.microsoft.com/en-us/azure/azure-monitor/profiler/profiler-vm` | [enablement-overview.md](references/enablement-overview.md) |
   | ETW | Service Fabric | `https://learn.microsoft.com/en-us/azure/azure-monitor/profiler/profiler-servicefabric` | [enablement-overview.md](references/enablement-overview.md) |
   | EventPipe | App Service (Linux) | `https://learn.microsoft.com/en-us/azure/azure-monitor/profiler/profiler-aspnetcore-linux` | [enablement-overview.md](references/enablement-overview.md) |
   | EventPipe | Containers | `https://learn.microsoft.com/en-us/azure/azure-monitor/profiler/profiler-containers` | [enablement-overview.md](references/enablement-overview.md) |
   | EventPipe | Any (OTel SDK) | `https://github.com/Azure/azuremonitor-opentelemetry-profiler-net` | [enablement-overview.md](references/enablement-overview.md) |

   Present the enablement instructions to the user in a clear, step-by-step format. Include:
   - Prerequisites (e.g., "Always on" for App Service, Basic tier or higher)
   - The specific steps to enable the profiler
   - Any required NuGet packages and code changes (for EventPipe)
   - How to verify the profiler is running (log output to look for)

   > **Tip — Copilot-based enablement**: For EventPipe with the OTel SDK, the user can alternatively use a Copilot prompt file to enable the profiler automatically. See: `https://github.com/Azure/azuremonitor-opentelemetry-profiler-net/blob/main/docs/AddAzureMonitorProfilerWithCoPilot.md`

7. **Verify the profiler is producing data** — After the user has enabled the profiler and generated some traffic, re-run the [check-profiler-status.md](scripts/check-profiler-status.md) script to confirm profiler events are appearing. The profiler typically takes 2–5 minutes to start producing traces after enablement.

   - If both `ServiceProfilerIndex` and `ServiceProfilerSample` events are found → full success. The profiler is capturing request-level data.
   - If only `ServiceProfilerIndex` events appear → the profiler is running sessions but not capturing individual requests. This is normal if traffic is low — suggest the user generate more traffic and wait for the next profiling window.
   - If no events appear after the expected wait time, suggest troubleshooting:
   - Verify the connection string is correct
   - Check the application logs for profiler startup messages
   - Ensure there is traffic hitting the application
   - For EventPipe: enable debug logging by setting log level for `Microsoft.ServiceProfiler` and `Microsoft.ApplicationInsights.Profiler` to `Debug`

   Once both event types are confirmed, suggest the user re-run the `perf-optimization` skill to investigate performance issues with the now-available profiler data.

## Key facts

- The profiler adds **5–15% CPU/memory overhead** when actively collecting traces (default: 30s every hour)
- Profiler data is automatically deleted after **15 days**
- Only **one profiler** can be attached per web app
- Code Optimizations and hot path analysis both depend on profiler data — without it, these features return no results

## References

- [Profiler Agent Selection Guide](references/profiler-agent-selection-guide.md)
- [Enablement Overview](references/enablement-overview.md)
- [Check Profiler Status](scripts/check-profiler-status.md)
- [Investigation Notes](../shared/investigation-notes.md)
- [resolve-app-id.md](../shared/resolve-app-id.md)
- [az CLI Query Pitfalls](../shared/az-cli-query-pitfalls.md)
