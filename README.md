# Performance Optimization Copilot

A [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) plugin that provides performance optimization skills and Azure monitoring integrations.

[![Watch the video](https://img.youtube.com/vi/uOdFUaCi8is/maxresdefault.jpg)](https://youtu.be/uOdFUaCi8is)

▶ [Watch the demo video](https://youtu.be/uOdFUaCi8is)

## What's Included

### Skills

| Skill | Description |
|-------|-------------|
| **perf-optimization** | Analyzes performance issues using Application Insights telemetry, Code Optimizations, and profiler hot paths to identify CPU, latency, and throughput bottlenecks |
| **agentic-optimization** | Analyzes AI agent telemetry from Application Insights, including anomaly detection, trend analysis, and performance statistics |
| **deep-analysis** | Cross-resource deep analysis of a specific distributed trace, correlating telemetry across multiple Application Insights resources |
| **get-profile-hotpath** | Fetches and displays the hot path call tree from an Application Insights Profiler trace for method-level bottleneck analysis |
| **download-profile-trace** | Downloads raw profiler trace files (.etl, .nettrace) from the Application Insights Profiler dataplane API for offline analysis in PerfView or Visual Studio |
| **download-snapshot** | Downloads snapshot dump files (.dmp) from the Application Insights Snapshot Debugger dataplane API for offline exception analysis in Visual Studio or WinDbg |
| **get-snapshot-debug-info** | Fetches exception details, call stacks, and variable values from a Snapshot Debugger snapshot for method-level root-cause analysis |
| **enable-profiler** | Guides users through enabling the Application Insights Profiler for .NET on their platform when profiler data is missing |
| **enable-snapshot-debugger** | Guides users through enabling the Application Insights Snapshot Debugger for .NET on their platform when snapshot data is missing |

### Agent

- **perf-optimizer** — A performance optimization specialist agent that combines all skills

## Installation

```bash
# Add the marketplace
copilot plugin marketplace add xiaomi7732/performance-optimization-copilot

# Install from the marketplace
copilot plugin install perf-copilot@xiaomi7732/performance-optimization-copilot
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

# Add marketplace and install this plugin
copilot plugin marketplace add xiaomi7732/performance-optimization-copilot
copilot plugin install perf-copilot@xiaomi7732/performance-optimization-copilot
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
├── skills/
│   ├── perf-optimization/SKILL.md               # Performance analysis & optimization skill
│   ├── agentic-optimization/SKILL.md            # AI agent telemetry analysis skill
│   ├── deep-analysis/SKILL.md                   # Cross-resource distributed trace analysis skill
│   ├── get-profile-hotpath/SKILL.md             # Profiler hot path call tree skill
│   ├── download-profile-trace/SKILL.md          # Trace file download skill
│   ├── download-snapshot/SKILL.md               # Snapshot dump download skill
│   ├── get-snapshot-debug-info/SKILL.md         # Snapshot exception inspection skill
│   ├── enable-profiler/SKILL.md                 # Profiler enablement guide skill
│   ├── enable-snapshot-debugger/SKILL.md        # Snapshot Debugger enablement guide skill
│   └── shared/investigation-notes.md            # Shared investigation context template
├── agents/
│   └── perf-optimizer.agent.md                  # Performance optimizer agent
├── README.md
└── LICENSE
```

## License

[MIT](LICENSE)
