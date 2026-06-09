<#
.SYNOPSIS
    Updates the commit hash in plugin.json to match the current HEAD.

.DESCRIPTION
    Run this script before a release to stamp the current git commit hash
    into plugin.json. The agent constructs the User-Agent string at runtime
    from the version and commit fields in plugin.json.

.EXAMPLE
    .\Update-CommitHash.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
    $repoRoot = $PSScriptRoot
    if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
        Write-Error "Could not find git repository root. Run this script from the repo or the scripts/ folder."
        exit 1
    }
}

Push-Location $repoRoot
try {
    $commitHash = (git rev-parse --short HEAD).Trim()
    if (-not $commitHash) {
        Write-Error "Failed to get git commit hash."
        exit 1
    }

    $pluginJsonPath = Join-Path $repoRoot "plugin.json"
    $pluginJson = Get-Content $pluginJsonPath -Raw | ConvertFrom-Json
    $version = $pluginJson.version
    $oldCommit = $pluginJson.commit

    if ($oldCommit -eq $commitHash) {
        Write-Host "Commit hash is already up to date ($commitHash). Nothing to do."
        exit 0
    }

    $pluginContent = Get-Content $pluginJsonPath -Raw
    $pluginContent = $pluginContent -replace '"commit":\s*"[^"]*"', "`"commit`": `"$commitHash`""
    Set-Content $pluginJsonPath -Value $pluginContent -NoNewline

    Write-Host "Updated plugin.json: commit $oldCommit -> $commitHash"
    Write-Host "Agent string:        optix/$version (commit:$commitHash)"
    Write-Host ""
    Write-Host "Review with 'git diff plugin.json', then commit."
} finally {
    Pop-Location
}
