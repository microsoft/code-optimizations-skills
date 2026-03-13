---
name: memory-analysis
description: Guide for analyzing memory usage and detecting memory leaks. Use this when asked to investigate memory issues, high memory consumption, or memory leaks.
---

# Memory Analysis

When asked to analyze memory usage or investigate memory leaks, follow this process:

1. **Identify the runtime** and determine which memory analysis tools are available.
2. **Recommend appropriate tools** for the stack:
   - .NET: dotnet-dump, dotnet-gcdump, Visual Studio Memory Profiler
   - Node.js: --inspect with Chrome DevTools, heapdump, memwatch-next
   - Java: jmap, Eclipse MAT, VisualVM
   - Python: tracemalloc, objgraph, memory_profiler
3. **If Azure Monitor is configured**, use the Azure MCP server tools to:
   - Query memory metrics for the target resource
   - Check activity logs for out-of-memory events
   - Analyze Log Analytics data for memory-related diagnostics
4. **Guide through heap analysis** — look for:
   - Objects that grow without bound (leak indicators)
   - Large object allocations
   - Pinned objects preventing garbage collection
   - Finalizer queue buildup
5. **Provide remediation guidance** with code examples where possible.

## Tips

- Take multiple snapshots over time to identify trends.
- Compare heap snapshots before and after the suspected operation.
- Check for common patterns: event handler leaks, static collections, unclosed streams.
