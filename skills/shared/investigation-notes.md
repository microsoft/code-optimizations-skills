# Investigation Notes

Investigation notes capture key context gathered during a performance investigation — especially the Application Insights resource identity — so that subsequent skill invocations can reuse it without re-asking the user.

## File location

The investigation notes file is named **`investigation-notes.md`** and lives in the **current working directory**.

## When to read

At the **beginning** of every skill invocation, before asking the user for any inputs:

1. Check whether `investigation-notes.md` exists in the working directory.
2. If it exists, read it and extract any values relevant to the current skill (e.g., resource ID, app ID, subscription).
3. Present the found values to the user and ask whether they want to **reuse** them or **provide new ones**.
4. If the user confirms, skip the corresponding input-gathering steps.

## When to write

After successfully identifying or resolving the Application Insights resource (or any other key investigation context):

1. If `investigation-notes.md` does not exist, create it with the template below.
2. If it already exists, update only the fields that have new or changed values — preserve everything else.

## File format

```markdown
# Investigation Notes

## Application Insights Resource

| Field             | Value |
|-------------------|-------|
| Resource Name     | `<name>` |
| Resource ID       | `<full ARM resource ID>` |
| App ID            | `<GUID>` |
| Subscription ID   | `<GUID>` |
| Resource Group    | `<name>` |

## Additional Context

<!-- Optional: free-form notes about the investigation, e.g., target endpoints, time ranges, observations -->
```

## Key fields

| Field | Description | Used by |
|---|---|---|
| **Resource ID** | Full ARM resource ID (`/subscriptions/.../providers/microsoft.insights/components/...`). Primary identifier for Azure Monitor queries. | `perf-optimization`, `download-profile-trace`, `get-profile-hotpath` |
| **App ID** | Application Insights app ID (GUID). Required for profiler dataplane API calls. | `download-profile-trace`, `get-profile-hotpath` |
| **Subscription ID** | Azure subscription GUID. Required as a parameter for MCP tool calls. | `perf-optimization` |
| **Resource Group** | Azure resource group name. Used for scoped queries. | `perf-optimization` |
| **Resource Name** | Display name of the Application Insights resource. Helps the user confirm identity. | All skills |

## Rules

- **Always confirm with the user** before reusing values from the notes. The user may want to switch to a different resource.
- **Never silently skip** gathering a required value — if it's missing from the notes, ask the user.
- **Update incrementally** — when a skill resolves a new value (e.g., app ID from resource ID), add it to the notes without overwriting unrelated fields.
- **Respect user overrides** — if the user provides a value that differs from the notes, update the notes with the new value.
