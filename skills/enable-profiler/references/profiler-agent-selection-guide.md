# Profiler Agent Selection Guide

> **Source**: https://github.com/Azure/azuremonitor-opentelemetry-profiler-net/blob/main/docs/ProfilerAgentSelectionGuide.md
> **Last synced**: 2026-03-25
> **Note**: This is a local fallback copy. The SKILL.md instructs the agent to fetch the latest version online first.

Two profiling technologies are supported: **ETW** and **EventPipe**.

- **ETW** works only on Windows. Runs out-of-process. No code changes needed. Heavier trace files.
- **EventPipe** works wherever the .NET runtime exists. Runs in-process. Requires NuGet package + code changes. Lightweight.

## Decision tree

### .NET Framework → ETW

If targeting [.NET Framework](https://dotnet.microsoft.com/download/dotnet-framework), use **ETW**. Supported on:
- Azure App Service
- Azure Functions
- Azure Cloud Service
- Azure Service Fabric
- Azure Virtual Machines and Virtual Machine Scale Sets

### .NET (modern) → ETW or EventPipe

If targeting [.NET](https://dotnet.microsoft.com/download/dotnet) (.NET 6, .NET 8, etc.):

- **Linux or containers** (AKS, Container Apps, ACI) → use **EventPipe**
- **Windows Azure services** → either ETW (simpler, no code changes) or EventPipe (lighter, in-proc)

> ⚠️ Do NOT use both profilers at the same time — the combined overhead is not recommended.

### EventPipe SDK choice

Two flavors of EventPipe profiler exist, depending on your Application Insights SDK:

| SDK | Profiler Package | Setup Method |
|-----|-----------------|--------------|
| [Azure Monitor OpenTelemetry distribution](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-enable?tabs=aspnetcore) | `Azure.Monitor.OpenTelemetry.Profiler` | `.AddAzureMonitorProfiler()` |
| [Classic Application Insights SDK](https://learn.microsoft.com/azure/azure-monitor/app/asp-net-core) | `Microsoft.ApplicationInsights.Profiler.AspNetCore` | `.AddServiceProfiler()` |

## Quick reference

| .NET Runtime | Platform | Agent | Code Change? |
|---|---|---|---|
| .NET Framework | Any Windows Azure service | ETW | No |
| .NET (modern) | App Service (Windows) | ETW or EventPipe | No / Yes |
| .NET (modern) | App Service (Linux) | EventPipe | Yes |
| .NET (modern) | Containers | EventPipe | Yes |
| .NET (modern) | Azure Functions | ETW | No |
| .NET (modern) | VMs / VMSS | ETW or EventPipe | No / Yes |
| .NET (modern) | Service Fabric | ETW | No |
