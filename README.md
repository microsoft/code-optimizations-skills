# Performance Optimization Copilot

A [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) plugin that provides performance optimization skills and Azure monitoring integrations.

## What's Included

### Skills

| Skill | Description |
|-------|-------------|
| **perf-profiling** | Guides through profiling workflows for CPU, latency, and request performance |
| **memory-analysis** | Assists with memory leak detection, heap analysis, and GC diagnostics |
| **load-testing** | Helps set up and analyze load/stress tests with common tools |

### MCP Server

- **azure-perf-monitoring** — Azure MCP server scoped to:
  - **Application Insights** — performance recommendations, request metrics, dependency analysis
  - **Azure Monitor** — resource metrics, activity logs, Log Analytics queries

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
- [Node.js](https://nodejs.org/) (for the Azure MCP server via `npx`)
- An Azure subscription with Application Insights and/or Azure Monitor configured (for MCP tools)

## Usage

Once installed, the skills are automatically available in Copilot CLI conversations:

```bash
# Ask about profiling
copilot "How do I profile my .NET application?"

# Ask about memory issues
copilot "Help me investigate a memory leak in my Node.js app"

# Ask about load testing
copilot "Set up a k6 load test for my API"
```

## Project Structure

```
├── plugin.json                       # Plugin manifest
├── .mcp.json                         # Azure MCP server configuration
├── skills/
│   ├── perf-profiling/SKILL.md       # Performance profiling skill
│   ├── memory-analysis/SKILL.md      # Memory analysis skill
│   └── load-testing/SKILL.md         # Load testing skill
├── agents/
│   └── perf-optimizer.agent.md       # Performance optimizer agent
├── .github/
│   └── plugin/
│       └── marketplace.json          # Marketplace manifest
├── README.md
└── LICENSE
```

## License

[MIT](LICENSE)
