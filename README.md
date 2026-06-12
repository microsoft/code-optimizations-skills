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
| **error-exploration** | Explores errors in Application Insights — exceptions, failed requests, and failed dependencies — and recommends which issues to fix based on frequency, trend, blast radius, and severity |

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
copilot plugin marketplace add microsoft/code-optimizations-skills
copilot plugin install optix@microsoft/code-optimizations-skills
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

# Explore errors and failures
copilot "What errors are happening in my application?"

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
│   ├── error-exploration/SKILL.md               # [exploring] Error analysis & prioritization
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

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Data Collection

The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services. You may turn off the telemetry as described in the repository. There are also some features in the software that may enable you and Microsoft to collect data from users of your applications. If you use these features, you must comply with applicable law, including providing appropriate notices to users of your applications together with a copy of Microsoft’s privacy statement. Our privacy statement is located at https://go.microsoft.com/fwlink/?LinkID=824704. You can learn more about data collection and use in the help documentation and our privacy statement. Your use of the software operates as your consent to these practices.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

## License

[MIT](LICENSE)
