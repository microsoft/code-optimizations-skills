# Performance Optimization Copilot

A [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) plugin that provides performance optimization skills and Azure monitoring integrations.

## What's Included

### Skills

| Skill | Description |
|-------|-------------|
| **perf-optimization** | Analyzes performance issues using Application Insights telemetry, Code Optimizations, and profiler hot paths to identify CPU, latency, and throughput bottlenecks |
| **get-profile-hotpath** | Fetches and displays the hot path call tree from an Application Insights Profiler trace for method-level bottleneck analysis |
| **download-profile-trace** | Downloads raw profiler trace files (.etl, .netperf) from the Application Insights Profiler dataplane API for offline analysis in PerfView or Visual Studio |

### Agent

- **perf-optimizer** — A performance optimization specialist agent that combines all skills

## Installation

```bash
# Install from GitHub
copilot plugin install xiaomi7732/performance-optimization-copilot

# Or install from a local clone
git clone https://github.com/xiaomi7732/performance-optimization-copilot.git
copilot plugin install ./performance-optimization-copilot
```

## Prerequisites

- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) installed and authenticated
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed and logged in (`az login`)
- An Azure subscription with Application Insights Profiler configured

## Usage

Once installed, the skills are automatically available in Copilot CLI conversations:

```bash
# Investigate a slow endpoint
copilot "Help me find out why my API is slow"

# Analyze a profiler trace
copilot "Get the hot path from my latest profiler trace"

# Download a trace for offline analysis
copilot "Download a profiler trace from my App Insights resource"
```

## Project Structure

```
├── plugin.json                                  # Plugin manifest
├── skills/
│   ├── perf-optimization/SKILL.md               # Performance analysis & optimization skill
│   ├── get-profile-hotpath/SKILL.md             # Profiler hot path call tree skill
│   ├── download-profile-trace/SKILL.md          # Trace file download skill
│   └── shared/investigation-notes.md            # Shared investigation context template
├── agents/
│   └── perf-optimizer.agent.md                  # Performance optimizer agent
├── README.md
└── LICENSE
```

## License

[MIT](LICENSE)
