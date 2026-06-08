---
name: download-profile-trace
category: investigating
description: Download a profiler trace file from Application Insights Profiler. Use this when asked to download, save, or export a profiler trace or .etl/.nettrace file.
---

# Download Profile Trace

This skill downloads a raw profiler trace artifact from the Application Insights Profiler dataplane API. The downloaded file can be opened in PerfView, Visual Studio, or other trace analysis tools.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- The user must provide an Application Insights **app ID** (GUID) or **resource ID**

## Steps

### 1–2. Check investigation notes and gather inputs

Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

In addition to the standard App ID, this skill requires:
- **Time range** (optional): How far back to look for traces. Defaults to 7 days (`P7D`).
- **Output path** (optional): Where to save the downloaded file. Defaults to the current directory.

### 3. Acquire an access token

Run the script in [get-access-token.md](../shared/get-access-token.md) to acquire a Bearer token for the profiler dataplane. See the **token freshness and session scoping** guidance in that document — re-acquire the token in the same command block as each API call.

### 4. List available profile traces

Run the script in [list-profile-traces.md](scripts/list-profile-traces.md) to call the ingested artifacts endpoint and list available profiler traces.

**Display only the 10 most recent traces by default.** If more traces exist, tell the user the total count and offer to show more. The API can return hundreds of traces for active applications, which produces overwhelming output.

Present the results to the user with:
- Timestamp (`triggerTime` — when the profiling session was triggered)
- Role name
- Role instance (machine/container name)
- Artifact ID (note if null)
- Format (Etl, Nettrace, or Netperf)

When constructing the output filename, derive the file extension from **two** fields:

1. **`format`** → base extension: `Etl` → `.etl`, `Nettrace` → `.nettrace`, `Netperf` → `.netperf`
2. **`blobUri`** → compression: if the URI ends in `.zip`, append `.zip` to the base extension

> ⚠️ Do **not** use the `blobUri` extension as-is for the filename. The `blobUri` may show `.etl.zip` even when `format` is `Nettrace`, which would produce a misleading filename. Always use `format` for the base extension and `blobUri` only to detect `.zip` compression.

Include the **role name** in the filename to avoid collisions when downloading traces from different resources into the same directory, e.g., `trace-myapp-2026-03-20T214135.nettrace.zip`.

Let the user pick which trace to download. If there's only one result, confirm it with the user before proceeding.

### 5. Download the selected trace

Choose the download method based on whether the selected trace has an `artifactId`:

#### 5a. If `artifactId` is available (not null)

Run the script in [download-trace.md](scripts/download-trace.md) with the selected `artifactId`. The script:
1. Calls the artifact download endpoint (`GET /artifacts/{artifactId}`)
2. Handles the 302 redirect to get the blob download URL
3. Downloads the trace file to the specified output path

#### 5b. If `artifactId` is null

First, run the script in [resolve-trace-identifiers.md](scripts/resolve-trace-identifiers.md) to query Application Insights `customEvents` for the `ServiceProfilerSample` event matching the selected trace. This can resolve:

- **Artifact ID** (from `ServiceProfilerContext`) — if found, use the standard download in step 5a
- **Trace location ID** (from `ServiceProfilerContent`) — if found, use the trace location download below

If an **artifact ID** is resolved, go back to step 5a and download using that artifact ID.

If only a **trace location ID** is resolved, use [download-trace-by-location.md](scripts/download-trace-by-location.md) to download. The trace location ID is a pipe-delimited v1 string:

```
v1|{stampId}|{appId}|{machineName}|{processId}|{etlFileSessionId}
```

The script:
1. Calls `POST /artifacts/byArtifactLocation?t={traceLocationId}` to get a SAS-protected download URL
2. Downloads the trace file from the returned URL

If **neither identifier** is resolved from the query, ask the user for the trace location ID or artifact ID manually.

### 6. Present the result

After downloading, tell the user:
- Where the file was saved
- The file size
- If the file is a `.zip`, remind the user to extract it before analysis
- How to open it — see [trace-file-info.md](references/trace-file-info.md) for guidance on tools and formats

## Response format

See [trace-file-info.md](references/trace-file-info.md) for information about trace file formats and how to open them.
