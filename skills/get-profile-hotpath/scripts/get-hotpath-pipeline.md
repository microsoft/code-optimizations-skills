# Get Hot Path Pipeline (Combined)

A single-script alternative to running steps 3–8 individually. This script acquires a token, fetches metadata, triggers analysis, polls for completion, fetches the root profile tree, and iteratively expands child nodes along the hot path — all in one PowerShell block.

Use this when you want to minimize tool calls. The individual scripts in this folder remain available for debugging or when you need finer control over each step.

## Parameters

| Parameter | Description |
|---|---|
| `$appId` | Application Insights app ID (GUID) |
| `$traceLocationId` | Full `ServiceProfilerContent` string for the trace |
| `$showFramework` | `"false"` to hide framework frames, `"true"` to show them |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"
$showFramework = "false"

# --- Step 1: Acquire token ---
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)
$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
}

# --- Step 2: Get metadata (redisCacheRegion) ---
$metadataResponse = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeMetadata?api-version=2024-03-06-preview" `
  -Method GET -Headers $headers

$redisCacheRegion = $metadataResponse.redisCacheRegion
Write-Host "redisCacheRegion: $redisCacheRegion"

# --- Step 3: Trigger trace analysis ---
$body = @{
    traceLocationId = $traceLocationId
    showFrameworkDependencies = ($showFramework -eq "true")
    redisCacheRegion = $redisCacheRegion
} | ConvertTo-Json

$triggerHeaders = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
}

$skipPoll = $false
$rootTree = $null

try {
    $triggerResponse = Invoke-WebRequest `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreedefinitions?api-version=2024-03-06-preview" `
      -Method POST -Headers $triggerHeaders -ContentType "application/json" -Body $body `
      -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction SilentlyContinue
} catch {
    if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
        $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($_.Exception.Response.Headers.Location)"
        Write-Host "Analysis cached (302 exception). Following redirect..."
        $rootTree = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers @{
            "Authorization" = "Bearer $token"
            "x-ms-client-request-id" = [guid]::NewGuid().ToString()
        }
        $skipPoll = $true
    } else {
        throw
    }
}

if ($skipPoll) {
    # 302 was already handled in the catch block
} elseif ($triggerResponse.StatusCode -eq 302) {
    $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($triggerResponse.Headers['Location'])"
    Write-Host "Analysis cached. Following redirect..."
    $rootTree = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers @{
        "Authorization" = "Bearer $token"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
    }
    $skipPoll = $true
} elseif ($triggerResponse.StatusCode -eq 202) {
    Write-Host "Analysis triggered (202). Polling for completion..."
} else {
    # Try-catch for 302 that throws despite -SkipHttpErrorCheck
    Write-Host "Trigger returned status: $($triggerResponse.StatusCode)"
}

# --- Step 4: Poll for completion (if needed) ---
if (-not $skipPoll) {
    $encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
    $statusUri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeComputeStatus?t=$encodedTrace&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion"
    $maxAttempts = 45
    $delaySeconds = 2

    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $pollResponse = Invoke-WebRequest -Uri $statusUri -Method GET -Headers @{
                "Authorization" = "Bearer $token"
                "x-ms-client-request-id" = [guid]::NewGuid().ToString()
            } -MaximumRedirection 0 -SkipHttpErrorCheck
        } catch {
            if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
                Write-Host "Poll $i - Analysis complete (302)."
                break
            }
            throw
        }

        if ($pollResponse.StatusCode -eq 401) {
            Write-Host "Poll $i - 401, refreshing token..."
            $token = az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv
            Start-Sleep -Seconds $delaySeconds
            continue
        }

        if ($pollResponse.StatusCode -eq 302) {
            Write-Host "Poll $i - Analysis complete (302 redirect)."
            break
        }

        if ($pollResponse.StatusCode -ne 200) {
            Write-Host "Poll $i - Status: $($pollResponse.StatusCode)"
            Start-Sleep -Seconds $delaySeconds
            continue
        }

        $status = $pollResponse.Content | ConvertFrom-Json
        Write-Host "Poll $i - Status: $($status.status)"
        if ($status.status -eq "Complete") { break }
        if ($status.status -eq "Failed") { Write-Error "Analysis failed."; return }
        Start-Sleep -Seconds $delaySeconds
    }

    # --- Step 5: Fetch root profile tree ---
    $rootTree = Invoke-RestMethod `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeDefinitions?t=$encodedTrace&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion" `
      -Method GET -Headers @{
        "Authorization" = "Bearer $token"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
      }
}

# --- Step 6: Display root info ---
Write-Host "`nActivity: $($rootTree.ActivityId) | Wall: $($rootTree.WallClockMSec)ms"
Write-Host "CPU: $($rootTree.TotalCpuTime)ms | Await: $($rootTree.TotalAwaitTime)ms | Blocked: $($rootTree.TotalBlockedTime)ms"
Write-Host "HotPath indices: $($rootTree.HotPath -join ', ')"

# --- Step 7: Expand child nodes along hot path ---
$loadedNodes = [System.Collections.Generic.Dictionary[string,object]]::new()
function Collect-Nodes($nodes) {
    foreach ($n in $nodes) {
        $loadedNodes[[string]$n.Meta.Index] = $n
        if ($n.Nodes) { Collect-Nodes $n.Nodes }
    }
}
Collect-Nodes $rootTree.Nodes

$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
$maxRounds = 10

for ($round = 1; $round -le $maxRounds; $round++) {
    # Collect pending indices from hot path and from loaded nodes' ChildReferences
    $pending = @()
    foreach ($idx in $rootTree.HotPath) {
        if (-not $loadedNodes.ContainsKey([string]$idx)) { $pending += [string]$idx }
    }
    foreach ($idx in $rootTree.HotPath) {
        $hpKey = [string]$idx
        if ($loadedNodes.ContainsKey($hpKey)) {
            $node = $loadedNodes[$hpKey]
            if ($node.ChildReferences) {
                foreach ($cr in $node.ChildReferences) {
                    $crKey = [string]$cr
                    if (-not $loadedNodes.ContainsKey($crKey)) { $pending += $crKey }
                }
            }
        }
    }
    $pending = @($pending | Select-Object -Unique)

    if ($pending.Count -eq 0) { break }

    Write-Host "Round $round - Fetching $($pending.Count) child node(s)..."
    $childParams = ($pending | ForEach-Object { "c=$([System.Uri]::EscapeDataString($_))" }) -join "&"

    $childNodes = Invoke-RestMethod `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeChildren?t=$encodedTrace&$childParams&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion" `
      -Method GET -Headers @{
        "Authorization" = "Bearer $token"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
      }

    $newCount = 0
    foreach ($node in $childNodes) {
        if (-not $loadedNodes.ContainsKey([string]$node.Meta.Index)) { $newCount++ }
        $loadedNodes[[string]$node.Meta.Index] = $node
    }
    if ($newCount -eq 0) { break }
}

# --- Step 8: Output hot path nodes ---
Write-Host "`n--- HOT PATH NODES ---"
foreach ($idx in $rootTree.HotPath) {
    if ($loadedNodes.ContainsKey([string]$idx)) {
        $node = $loadedNodes[[string]$idx]
        $pct = [math]::Round(($node.Values.Metric / $rootTree.WallClockMSec) * 100, 1)
        Write-Host "[$idx] $($node.Values.Metric)ms ($pct%) - $($node.Meta.Label)"

        # Show immediate children of hot path nodes
        if ($node.ChildReferences) {
            foreach ($cr in $node.ChildReferences) {
                if ($loadedNodes.ContainsKey([string]$cr) -and [string]$cr -notin ($rootTree.HotPath | ForEach-Object { [string]$_ })) {
                    $child = $loadedNodes[[string]$cr]
                    $cpct = [math]::Round(($child.Values.Metric / $rootTree.WallClockMSec) * 100, 1)
                    Write-Host "  [$cr] $($child.Values.Metric)ms ($cpct%) - $($child.Meta.Label)"
                }
            }
        }
    }
}

Write-Host "`nTotal loaded nodes: $($loadedNodes.Count)"
```

## Notes

- The script uses `try-catch` for 302 redirect handling during polling, as PowerShell throws exceptions on 302 even with `-SkipHttpErrorCheck` when `-MaximumRedirection 0` is set. See [302-redirect-handling.md](../../shared/302-redirect-handling.md) for details on this pattern.
- Token is acquired once at the start. For traces that take >60 minutes to analyze, the token may expire — the polling loop handles 401 by refreshing.
- Child node expansion runs up to 10 rounds. Most traces complete in 2–3 rounds.
- The output shows hot path nodes with percentages relative to wall clock time. Percentages >100% indicate parallel execution (expected for multi-threaded workloads).

## User communication

The hot path pipeline involves multiple steps that can take 1–2 minutes or longer for large traces:

1. **Triggering analysis** — usually instant, but may take a few seconds
2. **Polling for completion** — up to 90 seconds (45 polls × 2s) for fresh analyses
3. **Fetching root tree** — usually under 5 seconds
4. **Expanding child nodes** — varies, typically 3–8 rounds of API calls

Before running this pipeline, inform the user that the hot path fetch is a multi-step process and may take a minute or two. Provide periodic status updates (the script's `Write-Host` output serves this purpose) so the user knows the process hasn't stalled. If the analysis is already cached (302 on trigger), the entire pipeline completes in seconds.
