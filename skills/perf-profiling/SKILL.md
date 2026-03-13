---
name: perf-profiling
description: Guide for profiling application performance. Use this when asked to profile an application, identify slow code paths, or analyze CPU/request latency.
---

# Performance Profiling

When asked to profile or investigate application performance issues, follow this process:

1. **Identify the runtime and framework** of the target application (e.g., .NET, Node.js, Java, Python).
2. **Check for existing profiling configuration** in the project (e.g., `launchSettings.json`, diagnostic tools config).
3. **Recommend appropriate profiling tools** for the stack:
   - .NET: dotnet-trace, dotnet-counters, Visual Studio Profiler, Application Insights Profiler
   - Node.js: clinic.js, 0x, node --prof
   - Java: async-profiler, JFR (Java Flight Recorder)
   - Python: cProfile, py-spy, scalene
4. **If Azure Application Insights is configured**, use the Azure MCP server tools to:
   - List code optimization recommendations
   - Query performance metrics and request durations
   - Analyze slow dependencies
5. **Summarize findings** with actionable optimization suggestions ranked by expected impact.

## Tips

- Always establish a baseline measurement before suggesting optimizations.
- Focus on the hot path — optimize the code that runs most frequently.
- Consider both CPU-bound and I/O-bound bottlenecks.
