# User-Agent Convention

All HTTP requests made by this plugin must include a `User-Agent` header to identify the client for telemetry and diagnostics purposes.

## Format

```
perf-copilot/{version} (commit:{commitHash})
```

- **version** — from `plugin.json` → `"version"`
- **commitHash** — from `plugin.json` → `"commit"` (short SHA of the last release commit)

Example:

```
perf-copilot/0.1.0 (commit:9c4d3f5)
```

## Usage in PowerShell scripts

Define the user agent string at the top of each script block and include it in every header dictionary:

```powershell
$userAgent = "perf-copilot/0.1.0 (commit:9c4d3f5)"

$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
}
```

## Maintenance

When releasing a new version, update both `version` and `commit` in `plugin.json`. Then update all script templates in `skills/` to reflect the new user agent string.
