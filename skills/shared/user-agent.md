# User-Agent Convention

All HTTP requests made by this plugin must include a `User-Agent` header to identify the client for telemetry and diagnostics purposes.

## Format

```
optix/{version} (commit:{commitHash})
```

Both values come from `plugin.json` at the repository root:
- **version** → `"version"` field
- **commitHash** → `"commit"` field

## Usage in PowerShell scripts

Read `version` and `commit` from `plugin.json` to construct the agent string. Include it in every header dictionary:

```powershell
$userAgent = "optix/$version (commit:$commit)"

$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
}
```

**Do not hardcode the version or commit hash in script files.** Always read them from `plugin.json` so there is a single source of truth.

## Maintenance

Before a release, run `scripts/Update-CommitHash.ps1` to stamp the current HEAD commit into `plugin.json`.
