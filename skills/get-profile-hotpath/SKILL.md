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

### 1. Gather inputs

Ask the user for:
- **App ID**: The Application Insights app ID (GUID). If the user provides a resource ID instead, resolve it by running the script in [resolve-app-id.md](scripts/resolve-app-id.md).
- **Trace location ID**: The full `ServiceProfilerContent` string, which looks like: `v1|{stampId}|{dataCube}|{machineName}|{processId}|{sessionId}|{activityPath}|{startTime}|{endTime}`

If the user doesn't have a trace location ID, help them find one by querying profiler samples — see [find-profiler-traces.md](scripts/find-profiler-traces.md).

### 2. Acquire an access token

Run the script in [get-access-token.md](scripts/get-access-token.md) to acquire a Bearer token for the profiler dataplane.

### 3. Fetch the Redis cache region

Run the script in [get-metadata.md](scripts/get-metadata.md) to call the `profileTreeMetadata` endpoint and extract the `redisCacheRegion` value.

### 4. Fetch the root profile tree

Run the script in [get-profile-tree.md](scripts/get-profile-tree.md) to call the `profileTreeDefinitions` endpoint. This returns the root call tree with the `HotPath` array (node indices) and top-level `Nodes`.

### 5. Fetch child nodes to complete the hot path

The root tree usually only contains the first 1–2 levels of nodes. The remaining nodes in the `HotPath` are referenced by index in `ChildReferences` but not inline. Run the script in [get-child-nodes.md](scripts/get-child-nodes.md) iteratively to expand them.

### 6. Present the hot path

Once all hot path nodes are loaded, present the result using the format described in [present-hotpath.md](references/present-hotpath.md).

## Response format

See [present-hotpath.md](references/present-hotpath.md) for how to interpret the profile tree JSON and display the hot path as a human-readable call tree.
