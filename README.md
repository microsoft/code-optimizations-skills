# Optix

***Opt***imize · Diagnos***t***ics · F***ix*** — a [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) plugin for Azure Application Insights monitoring and performance optimization.

[![Watch the video](https://img.youtube.com/vi/uOdFUaCi8is/maxresdefault.jpg)](https://youtu.be/uOdFUaCi8is)

▶ [Watch the demo video](https://youtu.be/uOdFUaCi8is)

## What's Included

### Skills

Skills are organized into three categories that form a natural workflow: **Setup** → **Explore** → **Investigate**.

#### 🔧 Setup — "Am I ready?"

Ensure Azure monitoring tools are enabled and configured before you start.

| Skill | Description |
|-------|-------------|
| **enable-profiler** | Guides users through enabling the Application Insights Profiler for .NET on their platform when profiler data is missing |
| **enable-snapshot-debugger** | Guides users through enabling the Application Insights Snapshot Debugger for .NET on their platform when snapshot data is missing |

#### 🔍 Exploring — "What's wrong?"

Discover performance issues, anomalies, and optimization opportunities across your application.

| Skill | Description |
|-------|-------------|
| **perf-optimization** | Analyzes performance issues using Application Insights telemetry, Code Optimizations, and profiler hot paths to identify CPU, latency, and throughput bottlenecks |
| **agentic-optimization** | Analyzes AI agent telemetry from Application Insights, including anomaly detection, trend analysis, and performance statistics |

#### 🔬 Investigating — "Why is it wrong?"

Drill into specific issues — profiler traces, snapshots, and distributed operations.

| Skill | Description |
|-------|-------------|
| **get-profile-hotpath** | Fetches and displays the hot path call tree from an Application Insights Profiler trace for method-level bottleneck analysis |
| **get-snapshot-debug-info** | Fetches exception details, call stacks, and variable values from a Snapshot Debugger snapshot for method-level root-cause analysis |
| **deep-analysis** | Cross-resource deep analysis of a specific distributed trace, correlating telemetry across multiple Application Insights resources |
| **download-profile-trace** | Downloads raw profiler trace files (.etl, .nettrace) from the Application Insights Profiler dataplane API for offline analysis in PerfView or Visual Studio |
| **download-snapshot** | Downloads snapshot dump files (.dmp) from the Application Insights Snapshot Debugger dataplane API for offline exception analysis in Visual Studio or WinDbg |

### Agent

- **optix-optimizer** — A performance optimization specialist agent that combines all skills

## Installation

```bash
# Add the marketplace
copilot plugin marketplace add xiaomi7732/performance-optimization-copilot

# Install all skills + agent (recommended)
copilot plugin install optix@xiaomi7732/performance-optimization-copilot

# Or install by category (each includes the optix-optimizer agent)
copilot plugin install optix-explore@xiaomi7732/performance-optimization-copilot       # Exploring skills + agent
copilot plugin install optix-investigate@xiaomi7732/performance-optimization-copilot    # Investigating skills + agent
copilot plugin install optix-setup@xiaomi7732/performance-optimization-copilot          # Setup skills + agent
```

## Prerequisites

- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) installed and authenticated
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed and logged in (`az login`)
- An Azure subscription with Application Insights configured (Profiler for performance analysis, Snapshot Debugger for exception debugging)

### Quick Install (Windows)

```powershell
# Install GitHub Copilot CLI
winget install GitHub.CopilotCLI

# Install Azure CLI
winget install Microsoft.AzureCLI

# Authenticate
copilot auth login
az login

# Add marketplace and install all skills + agent
copilot plugin marketplace add xiaomi7732/performance-optimization-copilot
copilot plugin install optix@xiaomi7732/performance-optimization-copilot
```

## Usage

Once installed, the skills are automatically available in Copilot CLI conversations:

```bash
# Investigate a slow endpoint
copilot "Help me find out why my API is slow"

# Analyze a profiler trace
copilot "Get the hot path from my latest profiler trace"

# Download a trace for offline analysis
copilot "Download a profiler trace from my App Insights resource"

# Enable the profiler on your app
copilot "Help me enable the Application Insights Profiler"

# Download a snapshot for offline debugging
copilot "Download a snapshot dump from my App Insights resource"

# Inspect exception details from a snapshot
copilot "Show me the exception, call stack and relevant variables from my latest snapshot"

# Enable the Snapshot Debugger on your app
copilot "Help me enable the Snapshot Debugger"

# Analyze AI agent performance
copilot "Analyze my AI agent telemetry for anomalies"

# Deep analysis of a distributed trace
copilot "Do a deep analysis of operation ID abc-123"
```

## Project Structure

```
├── plugin.json                                  # Plugin manifest
├── marketplace.json                             # Marketplace manifest (optix, optix-explore, optix-investigate, optix-setup)
├── skills/
│   ├── perf-optimization/SKILL.md               # [exploring] Performance analysis & optimization
│   ├── agentic-optimization/SKILL.md            # [exploring] AI agent telemetry analysis
│   ├── get-profile-hotpath/SKILL.md             # [investigating] Profiler hot path call tree
│   ├── get-snapshot-debug-info/SKILL.md         # [investigating] Snapshot exception inspection
│   ├── deep-analysis/SKILL.md                   # [investigating] Cross-resource distributed trace analysis
│   ├── download-profile-trace/SKILL.md          # [investigating] Trace file download
│   ├── download-snapshot/SKILL.md               # [investigating] Snapshot dump download
│   ├── enable-profiler/SKILL.md                 # [setup] Profiler enablement guide
│   ├── enable-snapshot-debugger/SKILL.md        # [setup] Snapshot Debugger enablement guide
│   └── shared/investigation-notes.md            # Shared investigation context template
├── agents/
│   └── optix-optimizer.agent.md                  # Performance optimizer agent
├── README.md
└── LICENSE
```

## License

[MIT](LICENSE)
