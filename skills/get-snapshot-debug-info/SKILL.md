---
name: get-snapshot-debug-info
description: Fetch exception details, call stack, and variable values from an Application Insights Snapshot Debugger snapshot. Use this when asked to inspect a snapshot, view exception info, debug an exception, or see variable values from a crash.
---

# Get Snapshot Debug Info

This skill fetches the exception information, call stack, and variable values from an Application Insights Snapshot Debugger snapshot using the dataplane REST API directly.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- The user must provide an Application Insights **app ID** (GUID) or **resource ID**

## Steps

### 1–2. Check investigation notes and gather inputs

Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

### 3. List available snapshots and let the user pick one

Unless the user already has specific snapshot identifiers (`stampId`, `snapshotId`, `snapshotTimestamp`) that they want to inspect, **start by listing recent snapshots** so the user can pick one interactively.

Run the script in [find-snapshots.md](scripts/find-snapshots.md) to:
1. Call the ingested artifacts endpoint to list recent snapshot dumps
2. Present the 10 most recent snapshots with timestamp, role name, and exception type
3. Let the user pick one

After the user selects a snapshot, **resolve the snapshot identifiers**:
- **`snapshotId`**: The `artifactId` from the selected artifact
- **`snapshotTimestamp`**: The `triggerTime` from the selected artifact
- **`stampId`**: Query exception telemetry for the `ai.snapshot.stampid` custom dimension matching the selected snapshot (see [find-snapshots.md](scripts/find-snapshots.md) for the KQL query)

See [snapshot-identifiers.md](../shared/snapshot-identifiers.md) for the full format specification.

### 4–8. Fetch the debug info (combined pipeline)

For efficiency, use the combined pipeline script [get-debug-info-pipeline.md](scripts/get-debug-info-pipeline.md) which performs steps 4–8 in a single PowerShell block: token acquisition → metadata → trigger debug info computation → poll for completion → fetch debug info → fetch variables. This is the **preferred approach** — it reduces tool calls from 5–6 down to 1–2.

> **User communication**: The debug info pipeline may take **1–2 minutes** for snapshots being processed for the first time (triggering computation, polling for completion, fetching variables). Before starting the pipeline, inform the user that this is a multi-step process and they should expect to wait. Provide periodic status updates based on the script's output (e.g., "Computation triggered, polling for completion...", "Fetching variables for 5 stack frames..."). If the snapshot was previously analyzed, cached results return in seconds.

If you need finer control or want to debug individual steps, the granular scripts below remain available.

<details>
<summary>Individual steps (4–8) for debugging</summary>

### 4. Acquire an access token

Run the script in [get-access-token.md](../shared/get-access-token.md) to acquire a Bearer token for the dataplane. See the **token freshness and session scoping** guidance in that document — re-acquire the token in the same command block as each API call. This is especially critical during the polling loop in step 5, which may run for over a minute.

### 5. Fetch the Redis cache region

Run the script in [get-snapshot-metadata.md](scripts/get-snapshot-metadata.md) to call the `snapshotDebuggerMetadata` endpoint and extract the `redisCacheRegion` value.

### 6. Trigger debug info computation

Run the script in [trigger-debug-info.md](scripts/trigger-debug-info.md) to POST to the `debugInfo` endpoint. This triggers the debug info computation using the `stampId`, `snapshotId`, `snapshotTimestamp`, and `redisCacheRegion`.

> **302 redirect handling**: When the debug info results already exist, the POST returns a 302 redirect. The script disables auto-redirect (`-MaximumRedirection 0`) and manually follows the `Location` header with the `Authorization` header preserved. If you get the debug info back directly from the 302 path, you can skip step 7.

### 7. Poll for computation completion

If step 6 returned 202 (computation newly triggered), run the script in [poll-debug-info-status.md](scripts/poll-debug-info-status.md) to poll the `debugInfoComputeStatus` endpoint until the computation is complete. This must succeed before fetching the debug info.

### 8. Fetch the debug info result

Run the script in [get-debug-info.md](scripts/get-debug-info.md) to call the `debugInfo` GET endpoint. This returns the exception information and call stack frames with variable indices.

### 9. Fetch variables

Run the script in [get-variables.md](scripts/get-variables.md) to POST variable indices to the `variables` endpoint. This returns variable names, values, types, and child references for 2 levels of depth.

</details>

### 10. Present the debug info

Once the debug info and variables are loaded, present the result using the format described in [present-debug-info.md](references/present-debug-info.md).

## Response format

See [present-debug-info.md](references/present-debug-info.md) for how to interpret the debug info JSON and display the exception, call stack, and variables.

## Troubleshooting

### 401 Unauthorized during polling (302 redirect)

The most common cause of 401 errors during the polling loop (step 7) is **302 redirect auth stripping**. When the computation completes, the status endpoint returns a 302 redirect to the debug info result. PowerShell's `Invoke-RestMethod` automatically follows the redirect but strips the `Authorization` header, causing a 401 on the redirected URL.

The updated polling script in [poll-debug-info-status.md](scripts/poll-debug-info-status.md) handles this by using `Invoke-WebRequest -MaximumRedirection 0` to detect the 302 as a completion signal without following it.

If you still see persistent 401s after the script update:

1. Verify the user is logged in: `az account show`
2. Re-authenticate: `az login`
3. Ensure the correct subscription is selected: `az account set --subscription <subscription-id>`
4. Try acquiring the token manually: `az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com"`

### Computation still "Running" after polling timeout

If the `debugInfoComputeStatus` endpoint still returns `Running` after the polling loop exhausts all attempts (default: 45 attempts / ~90 seconds):

1. **Wait and retry** — large snapshots take longer to process. Wait 30–60 seconds, then re-acquire a fresh token and try a direct GET on the `debugInfo` endpoint (step 8). If the computation completed in the background, the GET will return the result directly.
2. **Try a different snapshot** — if the snapshot is unusually large or corrupted, try a different snapshot from the same time window.
3. **Re-trigger the computation** — POST to the `debugInfo` endpoint again (step 6). If the computation completed, you'll get a 302 redirect to the cached result.

### Computation returns "Failed"

If the `debugInfoComputeStatus` endpoint returns `Failed`:

1. Check the error details at the `debugInfoComputeErrors` endpoint.
2. **Try a different snapshot** — the snapshot data may be corrupted or incomplete.
3. **Check the snapshot age** — very old snapshots may have expired from storage.

### Empty or missing variables

If stack frames have no variable indices, or variable fetching returns empty results:

1. **Optimized code** — the compiler may have optimized away local variables. This is common in Release builds.
2. **Framework frames** — .NET runtime frames typically don't include variable information.
3. **Snapshot scope** — only variables that were in scope at the time of the exception are captured.
