---
name: download-profile-trace
description: Download a profiler trace file from Application Insights Profiler. Use this when asked to download, save, or export a profiler trace or .etl/.nettrace file.
---

# Download Profile Trace

This skill downloads a raw profiler trace artifact from the Application Insights Profiler dataplane API. The downloaded file can be opened in PerfView, Visual Studio, or other trace analysis tools.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- The user must provide an Application Insights **app ID** (GUID) or **resource ID**

## Steps

### 1. Check investigation notes

Before asking the user for inputs, check whether `investigation-notes.md` exists in the working directory. If it does, read it for existing Application Insights details (especially **App ID** and **Resource ID**). See [Investigation Notes](../shared/investigation-notes.md) for the file format and rules.

- If an **App ID** is found, present it to the user and ask whether to reuse it or provide a different one.
- If only a **Resource ID** is found (no App ID), resolve the App ID by running the script in [resolve-app-id.md](scripts/resolve-app-id.md), then confirm with the user.
- If the user confirms, skip asking for the App ID in the next step.

### 2. Gather inputs

Ask the user for any values not already obtained from the investigation notes:
- **App ID**: The Application Insights app ID (GUID). If the user provides a resource ID instead, resolve it by running the script in [resolve-app-id.md](scripts/resolve-app-id.md).
- **Time range** (optional): How far back to look for traces. Defaults to 7 days (`P7D`).
- **Output path** (optional): Where to save the downloaded file. Defaults to the current directory.

After all inputs are confirmed, **write or update `investigation-notes.md`** with the App ID and any other resolved values (Resource ID, Subscription ID, Resource Group). See [Investigation Notes](../shared/investigation-notes.md).

### 3. Acquire an access token

Run the script in [get-access-token.md](scripts/get-access-token.md) to acquire a Bearer token for the profiler dataplane.

> **Important — token freshness:** The `$token` variable only exists in the PowerShell session where it was set. If you run subsequent API calls in a different session (or if the variable is lost), you'll get `401 Unauthorized`. **Re-acquire the token in the same command block as each API call** to ensure it's always available. The token itself lasts ~85 minutes, but session-scoping is the more common cause of 401 errors.

### 4. List available profile traces

Run the script in [list-profile-traces.md](scripts/list-profile-traces.md) to call the ingested artifacts endpoint and list available profiler traces.

**Display only the 10 most recent traces by default.** If more traces exist, tell the user the total count and offer to show more. The API can return hundreds of traces for active applications, which produces overwhelming output.

Present the results to the user with:
- Timestamp (`triggerTime` — when the profiling session was triggered)
- Role name
- Role instance (machine/container name)
- Artifact ID (note if null)
- Format (Netperf or Etl)

When constructing the output filename, use the `blobUri` from the selected trace to determine the correct file extension (e.g., `.etl`, `.etl.zip`, `.netperf`). Include the **role name** in the filename to avoid collisions when downloading traces from different resources into the same directory, e.g., `trace-slowcpu-win-app-2026-03-20T214135.etl.zip`.

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
