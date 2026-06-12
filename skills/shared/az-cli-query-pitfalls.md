# az CLI Query Pitfalls

Known pitfalls when using `az monitor app-insights query` that can cause silent failures, empty results, or incorrect data. Read this before writing or modifying any CLI query scripts.

## `--offset` is mandatory

The `az monitor app-insights query` CLI applies a **server-side time filter** that defaults to **1 hour**. This filter runs _before_ your KQL query executes, so KQL `ago()` expressions are evaluated against already-truncated data.

**Without `--offset`**: A query with `ago(7d)` in KQL will only search the last 1 hour of data — returning 0 rows silently.

**Fix**: Always pass `--offset` with an ISO 8601 duration that covers at least the KQL lookback window:

```powershell
# Last 24 hours
az monitor app-insights query --apps "$resourceId" --analytics-query "$query" --offset "P1D"

# Last 7 days
az monitor app-insights query --apps "$resourceId" --analytics-query "$query" --offset "P7D"

# Last 30 days
az monitor app-insights query --apps "$resourceId" --analytics-query "$query" --offset "P30D"
```

### Valid ISO 8601 duration formats

| Format | Meaning | Notes |
|--------|---------|-------|
| `PT1H` | 1 hour | Use the `T` prefix for time components |
| `PT6H` | 6 hours | |
| `P1D` | 1 day | Preferred over `PT24H` |
| `P7D` | 7 days | |
| `P30D` | 30 days | |

> ⚠️ `P24H` is **not valid** ISO 8601 — hours must follow the `T` designator (`PT24H`). Using `P24H` causes a `BadArgumentError`.

## `--output table` silently drops results

For complex queries — especially those with `join`, `union`, or nested `let` statements — the `--output table` formatter may exit with code 0 but display **no output at all**. This is a known az CLI rendering bug.

**Fix**: Always use `--output json` and parse the results in PowerShell:

```powershell
$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset "P7D" `
  --output json

$parsed = $result | ConvertFrom-Json
$rows = $parsed.tables[0].rows
$columns = $parsed.tables[0].columns

Write-Host "Found $($rows.Count) result(s)"
```

## Multi-line KQL here-strings get truncated

PowerShell here-strings (`@'...'@`) containing multi-line KQL may be truncated when passed to `az monitor app-insights query`. This happens inconsistently and is difficult to diagnose.

**Fix**: Flatten the KQL query to a single line:

```powershell
# BAD: Multi-line here-string — may be truncated
$query = @'
requests
| where timestamp > ago(24h)
| summarize count() by name
'@

# GOOD: Single-line string
$query = "requests | where timestamp > ago(24h) | summarize count() by name"
```

## `$left` / `$right` PowerShell variable conflict

KQL `join` syntax uses `$left` and `$right` to reference tables. In PowerShell, these are interpreted as variable references inside double-quoted strings.

**Fix**: Escape with backticks inside double-quoted strings:

```powershell
# BAD: PowerShell interprets $left and $right as empty variables
$query = "requests | join kind=inner events on $left.id == $right.RequestId_"

# GOOD: Backtick-escaped
$query = "requests | join kind=inner events on `$left.id == `$right.RequestId_"
```

Alternatively, use single-quoted strings (but then you can't interpolate other variables):

```powershell
# Also works, but no variable interpolation
$query = 'requests | join kind=inner events on $left.id == $right.RequestId_'
```

## Extension auto-install prompts hang automation

Some `az` commands require CLI extensions (e.g., `az graph query` requires `resource-graph`). When an extension isn't installed, the CLI prompts interactively:

```
The command requires the extension resource-graph. Do you want to install it now? (Y/n):
```

This prompt **hangs indefinitely** in non-interactive or automated contexts (CI/CD, agent-driven sessions, piped scripts) because there is no TTY to provide input.

**Fix**: Pre-install required extensions silently before using them:

```powershell
# Pre-install the extension silently (idempotent — safe to run even if already installed)
az extension add --name resource-graph --yes 2>$null

# Now the command will work without prompting
az graph query -q "$graphQuery" --output json
```

The `--yes` flag suppresses the confirmation prompt. The `2>$null` suppresses "already installed" warnings.

> ⚠️ This applies to **all** extension-dependent commands, not just `az graph query`. Common extensions that may trigger this: `resource-graph`, `application-insights`, `monitor-control-service`.

## Prefer `az resource list` over extension-dependent commands

Some `az` subcommands (e.g., `az monitor app-insights component list`) depend on CLI extensions that may not be installed or may have version incompatibilities. These can fail with cryptic errors like "'list' is misspelled or not recognized".

**Fix**: When you only need basic resource metadata (name, ID, resource group), use the built-in `az resource list` command instead:

```powershell
# BAD: Requires the application-insights extension
az monitor app-insights component list -g "$resourceGroup" --output json

# GOOD: Works without any extensions
az resource list -g "$resourceGroup" --resource-type "Microsoft.Insights/components" --output json
```

`az resource list` is part of the core CLI and works with any resource type.

For **single-resource lookups** when you already have the resource ID, `az monitor app-insights component show` is the best option — it returns rich properties (InstrumentationKey, AppId, WorkspaceResourceId) that `az resource list` doesn't expose directly:

```powershell
# Show a specific App Insights resource by ID — returns full properties
az monitor app-insights component show --ids "$resourceId" --output json

# Query specific properties
az monitor app-insights component show --ids "$resourceId" --query "{name:name, ikey:instrumentationKey, appId:appId, workspace:workspaceResourceId}" --output json
```

> **Note**: `component show` requires the `application-insights` extension. Pre-install it to avoid interactive prompts (see [above](#extension-auto-install-prompts-hang-automation)).

**Summary**: Use `az resource list` for **listing/searching** (no extension needed). Use `az monitor app-insights component show --ids` for **single-resource property lookups** (extension required but richer data).

## Summary checklist

Before running any `az` CLI command in an automated context, verify:

- [ ] `--offset` is set to an ISO 8601 duration ≥ the KQL lookback window (for `az monitor app-insights query`)
- [ ] `--output json` is used (not `--output table`)
- [ ] KQL is on a single line (no multi-line here-strings)
- [ ] `$left` / `$right` are backtick-escaped if inside double-quoted strings
- [ ] Error handling checks for empty/error output before parsing
- [ ] Required CLI extensions are pre-installed with `az extension add --name <ext> --yes` before use
- [ ] `az resource list` is preferred over extension-dependent commands when basic metadata is sufficient
