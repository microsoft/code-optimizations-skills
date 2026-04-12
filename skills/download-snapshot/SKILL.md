---
name: download-snapshot
description: Download a snapshot dump file from Application Insights Snapshot Debugger. Use this when asked to download, save, or export a snapshot or .dmp file for offline debugging.
---

# Download Snapshot

This skill downloads a snapshot dump artifact from the Application Insights Snapshot Debugger dataplane API. The downloaded file can be opened in Visual Studio, WinDbg, or `dotnet-dump` for offline exception analysis.

## Prerequisites

- The user must be logged in to Azure CLI (`az login`)
- The user must provide an Application Insights **app ID** (GUID) or **resource ID**

## Steps

### 1–2. Check investigation notes and gather inputs

Follow the [Standard Skill Preamble](../shared/standard-skill-preamble.md) to check for existing investigation context and gather inputs.

In addition to the standard App ID, this skill requires:
- **Time range** (optional): How far back to look for snapshots. Defaults to 7 days (`P7D`).
- **Output path** (optional): Where to save the downloaded file. Defaults to the current directory.

### 3. Acquire an access token

Run the script in [get-access-token.md](../shared/get-access-token.md) to acquire a Bearer token for the dataplane. See the **token freshness and session scoping** guidance in that document — re-acquire the token in the same command block as each API call.

### 4. List available snapshots

Run the script in [list-snapshots.md](scripts/list-snapshots.md) to call the ingested artifacts endpoint and list available snapshot dumps.

**Display only the 10 most recent snapshots by default.** If more snapshots exist, tell the user the total count and offer to show more. The API can return many snapshots for active applications, which produces overwhelming output.

Present the results to the user with:
- Timestamp (`triggerTime` — when the snapshot was captured)
- Role name
- Role instance (machine/container name)
- Artifact ID

Let the user pick which snapshot to download. If there's only one result, confirm it with the user before proceeding.

### 5. Download the selected snapshot

Run the script in [download-snapshot-file.md](scripts/download-snapshot-file.md) with the selected `artifactId`. The script:
1. Calls the artifact download endpoint (`GET /artifacts/{artifactId}`)
2. Follows the 302 redirect to the SAS-protected blob URL
3. Downloads the snapshot file to the specified output path

### 6. Present the result

After downloading, tell the user:
- Where the file was saved
- The file size
- How to open it — see [snapshot-file-info.md](references/snapshot-file-info.md) for guidance on tools and formats

## Response format

See [snapshot-file-info.md](references/snapshot-file-info.md) for information about snapshot file formats and how to open them.

## Troubleshooting

### 401 Unauthorized

1. Verify the user is logged in: `az account show`
2. Re-authenticate: `az login`
3. Ensure the correct subscription is selected: `az account set --subscription <subscription-id>`
4. Try acquiring the token manually: `az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com"`

### Empty snapshot list

1. **Check the time range** — snapshots may have been captured outside the default 7-day window. Try `P30D`.
2. **Verify the App ID** — ensure it matches the Application Insights resource with Snapshot Debugger enabled.
3. **Confirm Snapshot Debugger is enabled** — the feature must be turned on in the Application Insights resource. Check the Azure portal under Application Insights → Snapshot Debugger.

### 404 Not Found during download

1. **Expired snapshot** — snapshots have a retention period. Very old snapshots may have been purged from storage.
2. **Wrong artifact ID** — verify the artifact ID matches a snapshot from the listing.
3. **Try again** — transient storage issues can cause temporary 404s. Wait a moment and retry.
