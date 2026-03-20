# Trace File Information

## What is a profiler trace file?

The downloaded artifact is a raw profiler trace captured by Application Insights Profiler. These traces contain detailed method-level timing, CPU samples, and thread activity for a profiling session.

## File formats

| Format | Extension | Description |
|---|---|---|
| ETL (Event Trace Log) | `.etl` | Windows ETW trace format. The most common format for .NET Framework and .NET on Windows. |
| NetPerf / NetTrace | `.netperf`, `.nettrace` | Cross-platform .NET trace format. Common for .NET on Linux containers (e.g., AKS). |

The actual format depends on the platform where the profiled application runs.

## How to open trace files

### PerfView (recommended for .etl)

1. Download [PerfView](https://github.com/microsoft/perfview/releases) (free, from Microsoft).
2. Open the `.etl` file in PerfView.
3. Navigate to **Thread Time** → **Call Tree** or **Flame Graph** for CPU analysis.
4. Use **When** to focus on specific time ranges within the trace.

### Visual Studio Diagnostic Tools

1. Open Visual Studio.
2. Go to **Debug → Performance Profiler** or simply **File → Open** the `.etl` file.
3. Visual Studio renders a timeline with CPU usage and the call tree.

### dotnet-trace (for .nettrace)

1. Install: `dotnet tool install -g dotnet-trace`
2. Convert to SpeedScope format: `dotnet-trace convert <file>.nettrace --format speedscope`
3. Open the converted JSON in [SpeedScope](https://www.speedscope.app/).

### Chromium Trace Viewer

1. Convert the trace to Chromium JSON format using `dotnet-trace convert`.
2. Open `chrome://tracing` in Chrome/Edge and load the JSON.

## Common use cases

- **Offline analysis** — Investigate performance issues without access to the Azure portal.
- **Sharing** — Send trace files to teammates or support for collaborative debugging.
- **Advanced tooling** — Use PerfView's advanced features (GC analysis, JIT stats, custom grouping) not available in the portal.
- **Archival** — Keep trace files for historical comparison after they expire from Application Insights.
