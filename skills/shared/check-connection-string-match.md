# Check Connection String Match

Scans the working directory for Application Insights connection strings in common configuration files and compares them against the target resource. This catches the common case where the app sends telemetry to a different App Insights resource than the one being investigated.

## When to use

Run this check when:
- The target resource has **no profiler events**, but the source code has profiler packages and configuration present.
- You want to verify early that the app is actually sending data to the resource in `investigation-notes.md`.

## What it checks

| File pattern | What it looks for |
|---|---|
| `appsettings.json`, `appsettings.*.json` | `ApplicationInsights.ConnectionString` JSON property |
| `*.bicep`, `*.json` (ARM templates) | `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting values |
| `.env` | `APPLICATIONINSIGHTS_CONNECTION_STRING=...` |
| `launchSettings.json` | `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable |

## Script

> ⚠️ This script searches for connection strings in the current working directory tree. It does NOT query Azure — it only inspects local files.

### Parameters

| Parameter | Description |
|-----------|-------------|
| `targetAppId` | The App ID (GUID) of the resource from `investigation-notes.md`. |
| `targetInstrumentationKey` | The Instrumentation Key of the target resource. Optional — if not known, resolve it with `az monitor app-insights component show --ids "<RESOURCE_ID>" --query "instrumentationKey" -o tsv`. |

### Step 1: Resolve the target resource's instrumentation key (if not known)

```powershell
$resourceId = "<RESOURCE_ID>"
$targetIKey = az monitor app-insights component show --ids "$resourceId" --query "instrumentationKey" -o tsv
$targetAppId = az monitor app-insights component show --ids "$resourceId" --query "appId" -o tsv
Write-Host "Target resource — IKey: $targetIKey | App ID: $targetAppId"
```

### Step 2: Scan local config files for connection strings

```powershell
# Search for connection strings in common config files.
# Patterns: InstrumentationKey=<GUID> or ApplicationId=<GUID> inside connection string values.
$patterns = @(
  "appsettings*.json",
  "*.bicep",
  "*.bicepparam",
  ".env",
  "launchSettings.json"
)

$found = @()
$ikeyOnly = @()   # Files with InstrumentationKey-based connection strings
$noIKey = @()     # Files with connection strings that lack an InstrumentationKey (e.g., Entra auth)
foreach ($pat in $patterns) {
  $files = Get-ChildItem -Path . -Filter $pat -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](bin|obj|node_modules)[\\/]' }
  foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    $relPath = $f.FullName.Replace((Get-Location).Path + "\", "")
    if ($content -match 'InstrumentationKey=([0-9a-fA-F\-]{36})') {
      $fileIKey = $Matches[1]
      $appIdMatch = if ($content -match 'ApplicationId=([0-9a-fA-F\-]{36})') { $Matches[1] } else { "(not in string)" }
      $found += [PSCustomObject]@{
        File = $relPath
        InstrumentationKey = $fileIKey
        ApplicationId = $appIdMatch
      }
    }
    elseif ($content -match 'IngestionEndpoint=') {
      # Connection string present but no InstrumentationKey — likely Entra-auth or endpoint-only format
      $noIKey += [PSCustomObject]@{ File = $relPath }
    }
  }
}

if ($found.Count -eq 0 -and $noIKey.Count -eq 0) {
  Write-Host "No connection strings found in local config files."
} else {
  if ($found.Count -gt 0) {
    Write-Host "Found $($found.Count) connection string(s) with InstrumentationKey in local files:`n"
    foreach ($entry in $found) {
      $ikeyMatch = if ($entry.InstrumentationKey -eq $targetIKey) { "MATCH" } else { "MISMATCH" }
      Write-Host "  File: $($entry.File)"
      Write-Host "    IKey: $($entry.InstrumentationKey) [$ikeyMatch]"
      Write-Host "    AppId: $($entry.ApplicationId)"
      Write-Host ""
    }
  }
  if ($noIKey.Count -gt 0) {
    Write-Host "WARNING: Found $($noIKey.Count) connection string(s) WITHOUT InstrumentationKey (cannot auto-compare):"
    foreach ($entry in $noIKey) {
      Write-Host "  File: $($entry.File)  — contains IngestionEndpoint but no IKey. Verify manually."
    }
    Write-Host ""
  }
}
```

### Step 3: Interpret results

| Result | Meaning | Next step |
|--------|---------|-----------|
| All IKey-based connection strings **match** target | Source code points to the correct resource (though runtime overrides are still possible) | Proceed — a mismatch is unlikely to be the cause |
| One or more IKey **mismatch** | Source code points to a different resource. However, the deployed app may override this via environment variables, App Service app settings, or CI/CD pipelines — so the mismatch may or may not reflect what's actually running in production | Present the finding to the user for investigation (see below) |
| Connection strings found but **no InstrumentationKey** (IngestionEndpoint-only) | The app uses a connection string format that cannot be auto-compared (e.g., Entra-auth) | Flag the files for the user and ask them to verify manually |
| No connection strings found | App may use environment variables set at deployment time, Key Vault references, or may not have Application Insights configured locally | Cannot determine match from source code alone. Ask the user how the connection string is configured, or check Azure App Service app settings directly if possible |

### When a mismatch is detected

> **Important context**: A mismatch between the local source code and the target resource does **not** necessarily mean the app is sending data to the wrong place. Connection strings are commonly overridden at deployment time through environment variables, App Service configuration, CI/CD pipelines, or Key Vault references. The source code value may be a development-time default that is never used in production.

Present the mismatch to the user as a **troubleshooting signal**, not a definitive error:

```
🔍 Connection string mismatch found in source code:
  - Investigation target:  IKey=<target>  (resource: <name>)
  - Source code (<file>):  IKey=<found>   (different resource)

Note: This shows what's in the source code. The deployed app may override
this value via environment variables, App Service settings, or CI/CD.
```

Then ask the user which scenario applies:
1. **The source code value is overridden at deployment** — the target resource is correct, and this mismatch is expected. Proceed with the investigation as-is.
2. **The source code value is what the app actually uses** — the profiler data may be going to the other resource. Ask whether to (a) switch the investigation to that resource, or (b) update the app's connection string.
3. **Not sure** — suggest checking the deployed app's effective configuration (e.g., App Service → Configuration → Application settings, or `az webapp config appsettings list`).
