# Snapshot File Information

## What is a snapshot dump file?

The downloaded artifact is a memory dump (minidump) captured by Application Insights Snapshot Debugger at the moment an exception was thrown. These snapshots contain the call stack, local variables, and object state at the point of failure — enabling root-cause analysis without needing to reproduce the issue.

## File formats

| Format | Extension | Description |
|---|---|---|
| Minidump | `.dmp` | Windows minidump format. The standard format for Snapshot Debugger captures. |

Snapshot dumps are typically `.dmp` files. Unlike profiler traces, there is no format variation across platforms — all snapshots use the minidump format.

## How to open snapshot files

### Visual Studio (recommended)

1. Open Visual Studio.
2. Go to **File → Open → File** and select the `.dmp` file, or **Debug → Open Dump File**.
3. Visual Studio shows a dump summary with exception info, modules, and threads.
4. Click **Debug with Managed Only** (or **Mixed**) to enter a debugging session.
5. You can inspect the call stack, local variables, and object state at the time of the exception.

### WinDbg

1. Download [WinDbg](https://learn.microsoft.com/windows-hardware/drivers/debugger/) (free, from Microsoft).
2. Open the `.dmp` file: **File → Open Dump File**.
3. Use `!analyze -v` for automatic exception analysis.
4. Use `.loadby sos clr` (for .NET Framework) or `.loadby sos coreclr` (for .NET Core) to load SOS debugging extensions.
5. Use `!clrstack` to view the managed call stack, `!dso` to dump stack objects.

### dotnet-dump (cross-platform)

1. Install: `dotnet tool install -g dotnet-dump`
2. Analyze: `dotnet-dump analyze <file>.dmp`
3. Inside the interactive session:
   - `clrstack` — view managed call stack
   - `dso` — dump stack objects
   - `pe` — print exception details
   - `dumpheap -stat` — heap statistics

## Common use cases

- **Exception analysis** — Inspect the exact state of variables and objects when an exception occurred.
- **Offline debugging** — Debug production issues without access to the running application or Azure portal.
- **Sharing** — Send snapshot files to teammates or support for collaborative root-cause analysis.
- **Complex exceptions** — Investigate exceptions that are difficult to reproduce locally, using real production state.
