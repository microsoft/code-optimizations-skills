---
name: get-profile-hotpath
description: Fetch and display the hot path from an Application Insights Profiler trace. Use this when asked to get the profiler hot path, call tree, or trace analysis for an App Insights resource.
---

# Get Profile Hot Path

This skill fetches the hot path call tree from an Application Insights Profiler trace using the dataplane REST API directly.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- The user must provide an Application Insights **app ID** (GUID) and a **trace location ID** (the `ServiceProfilerContent` value from a profiler sample)

## Steps

### 1. Check investigation notes

Before asking the user for inputs, check whether `investigation-notes.md` exists in the working directory. If it does, read it for existing Application Insights details (especially **App ID** and **Resource ID**). See [Investigation Notes](../shared/investigation-notes.md) for the file format and rules.

- If an **App ID** is found, present it to the user and ask whether to reuse it or provide a different one.
- If only a **Resource ID** is found (no App ID), resolve the App ID by running the script in [resolve-app-id.md](scripts/resolve-app-id.md), then confirm with the user.
- If the user confirms, skip asking for the App ID in the next step.

### 2. Gather inputs

Ask the user for any values not already obtained from the investigation notes:
- **App ID**: The Application Insights app ID (GUID). If the user provides a resource ID instead, resolve it by running the script in [resolve-app-id.md](scripts/resolve-app-id.md).
- **Trace location ID**: The full `ServiceProfilerContent` string, which looks like: `v1|{stampId}|{dataCube}|{machineName}|{processId}|{sessionId}|{activityPath}|{startTime}|{endTime}`

If the user doesn't have a trace location ID, help them find one by querying profiler samples — see [find-profiler-traces.md](scripts/find-profiler-traces.md).

After all inputs are confirmed, **write or update `investigation-notes.md`** with the App ID and any other resolved values (Resource ID, Subscription ID, Resource Group). See [Investigation Notes](../shared/investigation-notes.md).

### 3. Acquire an access token

Run the script in [get-access-token.md](scripts/get-access-token.md) to acquire a Bearer token for the profiler dataplane.

> **Important — token freshness:** The `$token` variable only exists in the PowerShell session where it was set. If you run subsequent API calls in a different session (or if the variable is lost), you'll get `401 Unauthorized`. **Re-acquire the token in the same command block as each API call** to ensure it's always available. The token itself lasts ~85 minutes, but session-scoping is the more common cause of 401 errors. This is especially critical during the polling loop in step 6, which may run for over a minute.

### 4. Fetch the Redis cache region

Run the script in [get-metadata.md](scripts/get-metadata.md) to call the `profileTreeMetadata` endpoint and extract the `redisCacheRegion` value.

### 5. Trigger trace analysis

Run the script in [trigger-trace-analysis.md](scripts/trigger-trace-analysis.md) to POST to the `profileTreeDefinitions` endpoint. This triggers the trace analysis using the `traceLocationId` and `redisCacheRegion`.

> **302 redirect handling**: When the analysis results already exist, the POST returns a 302 redirect. The script disables auto-redirect (`-MaximumRedirection 0`) and manually follows the `Location` header with the `Authorization` header preserved. If you get the profile tree back directly from the 302 path, you can skip steps 6 and 7.

### 6. Poll for analysis completion

If step 5 returned 202(analysis newly triggered), run the script in [poll-analysis-status.md](scripts/poll-analysis-status.md) to poll the `profileTreeComputeStatus` endpoint until the analysis is complete. This must succeed before fetching the profile tree.

### 7. Fetch the root profile tree

Run the script in [get-profile-tree.md](scripts/get-profile-tree.md) to call the `profileTreeDefinitions` GET endpoint. This returns the root call tree with the `HotPath` array (node indices) and top-level `Nodes`.

### 8. Fetch child nodes to complete the hot path

The root tree usually only contains the first 1–2 levels of nodes. The remaining nodes in the `HotPath` are referenced by index in `ChildReferences` but not inline. Run the script in [get-child-nodes.md](scripts/get-child-nodes.md) iteratively to expand them.

### 9. Present the hot path

Once all hot path nodes are loaded, present the result using the format described in [present-hotpath.md](references/present-hotpath.md).

## Response format

See [present-hotpath.md](references/present-hotpath.md) for how to interpret the profile tree JSON and display the hot path as a human-readable call tree.

## Troubleshooting

### 401 Unauthorized during polling (302 redirect)

The most common cause of 401 errors during the polling loop (step 6) is **302 redirect auth stripping**. When the analysis completes, the status endpoint returns a 302 redirect to the profile tree result. PowerShell's `Invoke-RestMethod` automatically follows the redirect but strips the `Authorization` header, causing a 401 on the redirected URL.

The updated polling script in [poll-analysis-status.md](scripts/poll-analysis-status.md) handles this by using `Invoke-WebRequest -MaximumRedirection 0` to detect the 302 as a completion signal without following it.

If you still see persistent 401s after the script update:

1. Verify the user is logged in: `az account show`
2. Re-authenticate: `az login`
3. Ensure the correct subscription is selected: `az account set --subscription <subscription-id>`
4. Try acquiring the token manually and check for errors: `az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com"`

### Analysis still "Running" after polling timeout

If the `profileTreeComputeStatus` endpoint still returns `Running` after the polling loop exhausts all attempts (default: 45 attempts / ~90 seconds):

1. **Wait and retry** — large traces take longer to analyze. Wait 30–60 seconds, then re-acquire a fresh token and try a direct GET on the `profileTreeDefinitions` endpoint (step 7). If the analysis completed in the background, the GET will return the root tree directly.
2. **Try a different trace** — if the trace is unusually large or corrupted, try a different profiler trace from the same time window. Shorter traces analyze faster.
3. **Re-trigger the analysis** — POST to the `profileTreeDefinitions` endpoint again (step 5). If the analysis completed, you'll get a 302 redirect to the cached result.

### Analysis returns "Failed"

If the `profileTreeComputeStatus` endpoint returns `Failed`:

1. **Try a different trace** — the trace data may be corrupted or incomplete.
2. **Check the trace time window** — very old traces may have expired from storage.
3. **Try with `showFrameworkDependencies: true`** — in rare cases, changing this parameter can resolve analysis failures.

### Empty or minimal root tree

If the root tree has very few nodes or the hot path is unexpectedly short:

1. **Expand child nodes** — the root tree only includes 1–2 levels. Follow `ChildReferences` using [get-child-nodes.md](scripts/get-child-nodes.md) to get the full tree.
2. **Check the trace duration** — very short traces (< 100ms) may not have enough samples for a meaningful call tree.
3. **Try with framework dependencies** — set `showFrameworkDependencies: true` in the trigger request to include runtime frames that may reveal hidden bottlenecks.
