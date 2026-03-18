# Presenting the Hot Path

After fetching the root tree and all child nodes, present the hot path as a human-readable call tree.

## Interpreting the response

### Key fields

- **`HotPath`**: An array of node indices representing the most expensive execution path in the trace. Walk these indices in order to build the hot path.
- **`WallClockMSec`**: Total wall-clock time of the request. Use this as the denominator when calculating percentages.
- **`TotalCpuTime`**, **`TotalAwaitTime`**, **`TotalBlockedTime`**: Breakdown of how time was spent.

### Node fields

- **`Meta.Label`**: The fully qualified method name. Format is `Assembly!Namespace.Class.Method(args)`. The `OTHER <<...>>` prefix indicates framework/runtime frames. `CPU_TIME` nodes represent raw CPU consumption.
- **`Meta.Index`**: The unique index used to look up this node in the tree.
- **`Values.Metric`**: Inclusive time in milliseconds (includes self + all children).
- **`ChildReferences`**: Indices of child nodes in the call tree.

### Calculating percentages

For each node, compute: `percentage = (node.Values.Metric / rootTree.WallClockMSec) * 100`

## Display format

Present as an indented call tree. Mark hot path nodes. Show time and percentage for each node.

Example output:

```
=== Profiler Hot Path ===
Activity: /#1/1/61035/ | Total: 14.92ms | CPU: 0ms | Blocked: 0ms

14.92ms (100.0%) WeatherForecastController.Get()  [HOT]
 └─14.72ms (98.6%) WeatherForecastHelper.GetForecasts()  [HOT]
    ├─13.83ms (92.6%) Enumerable.ToList()  [HOT]
    │  ├─10.51ms (70.4%) <GetForecasts>b__0() [lambda]  [HOT]
    │  │  ├─ 8.73ms (58.5%) CPU_TIME
    │  │  ├─ 1.61ms (10.8%) DateTime.get_Now()
    │  │  └─ 0.18ms  (1.2%) Random.Next()
    │  └─ 3.32ms (22.2%) CPU_TIME
    ├─ 0.47ms  (3.2%) CPU_TIME
    └─ 0.42ms  (2.8%) Enumerable.Select()
```

### Label cleanup

When displaying `Meta.Label` values:
- Strip `OTHER <<` prefix and `>>` suffix for framework frames.
- Strip assembly prefixes (e.g. `System.Linq!`) for readability — or keep them if the user wants full detail.
- `CPU_TIME` nodes represent raw CPU work within the parent frame.

### Summary

After the call tree, provide a brief analysis:
1. **Bottleneck**: Which method dominates the hot path and its percentage.
2. **Root cause**: Why it's slow (e.g., LINQ materialization, blocking I/O, excessive allocations).
3. **Recommendation**: Concrete fix suggestion if the source code is available.
