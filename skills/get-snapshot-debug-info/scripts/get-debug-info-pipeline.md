# Get Debug Info Pipeline (Combined)

A single-script alternative to running steps 3–7 individually. This script acquires a token, fetches metadata, triggers debug info computation, polls for completion, fetches the debug info (exception + call stack), and fetches variables for each stack frame — all in one PowerShell block.

Use this when you want to minimize tool calls. The individual scripts in this folder remain available for debugging or when you need finer control over each step.

## Parameters

| Parameter | Description |
|---|---|
| `$appId` | Application Insights app ID (GUID) |
| `$stampId` | Azure stamp identifier |
| `$snapshotId` | Snapshot GUID |
| `$snapshotTimestamp` | Snapshot capture timestamp (ISO 8601) |

## PowerShell script

```powershell
$appId = "<APP_ID>"
$stampId = "<STAMP_ID>"
$snapshotId = "<SNAPSHOT_ID>"
$snapshotTimestamp = "<SNAPSHOT_TIMESTAMP>"

# --- Step 1: Acquire token ---
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)
# $userAgent — construct from plugin.json version and commit fields. See skills/shared/user-agent.md
$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
    "User-Agent" = $userAgent
}

# --- Step 2: Get metadata (redisCacheRegion) ---
$metadataResponse = Invoke-RestMethod `
  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/snapshotDebuggerMetadata?api-version=2025-03-19-preview" `
  -Method GET -Headers $headers

$redisCacheRegion = $metadataResponse.redisCacheRegion
Write-Host "redisCacheRegion: $redisCacheRegion"

# --- Step 3: Trigger debug info computation ---
$body = @{
    stampId = $stampId
    snapshotId = $snapshotId
    snapshotTimestamp = $snapshotTimestamp
    redisCacheRegion = $redisCacheRegion
} | ConvertTo-Json

$triggerHeaders = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
    "User-Agent" = $userAgent
}

$skipPoll = $false
$debugInfo = $null

try {
    $triggerResponse = Invoke-WebRequest `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/debugInfo?api-version=2025-03-19-preview" `
      -Method POST -Headers $triggerHeaders -ContentType "application/json" -Body $body `
      -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction SilentlyContinue
} catch {
    if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
        $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($_.Exception.Response.Headers.Location)"
        Write-Host "Debug info cached (302 exception). Following redirect..."
        $debugInfo = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers @{
            "Authorization" = "Bearer $token"
            "x-ms-client-request-id" = [guid]::NewGuid().ToString()
            "User-Agent" = $userAgent
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
    Write-Host "Debug info cached. Following redirect..."
    $debugInfo = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers @{
        "Authorization" = "Bearer $token"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
        "User-Agent" = $userAgent
    }
    $skipPoll = $true
} elseif ($triggerResponse.StatusCode -eq 202) {
    Write-Host "Computation triggered (202). Polling for completion..."
} else {
    Write-Host "Trigger returned status: $($triggerResponse.StatusCode)"
}

# --- Step 4: Poll for completion (if needed) ---
if (-not $skipPoll) {
    $encodedTimestamp = [System.Uri]::EscapeDataString($snapshotTimestamp)
    $statusUri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/debugInfoComputeStatus?st=$stampId&sn=$snapshotId&t=$encodedTimestamp&r=$redisCacheRegion&api-version=2025-03-19-preview"
    $maxAttempts = 45
    $delaySeconds = 2

    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $pollResponse = Invoke-WebRequest -Uri $statusUri -Method GET -Headers @{
                "Authorization" = "Bearer $token"
                "x-ms-client-request-id" = [guid]::NewGuid().ToString()
                "User-Agent" = $userAgent
            } -MaximumRedirection 0 -SkipHttpErrorCheck
        } catch {
            if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
                $location = $_.Exception.Response.Headers.Location
                if ($location -match "debugInfoComputeErrors") {
                    Write-Error "Poll $i - Computation failed (302 redirect to errors endpoint: $location)."
                    return
                }
                Write-Host "Poll $i - Computation complete (302)."
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
            $location = $pollResponse.Headers['Location']
            if ($location -match "debugInfoComputeErrors") {
                Write-Error "Poll $i - Computation failed (302 redirect to errors endpoint: $location)."
                return
            }
            Write-Host "Poll $i - Computation complete (302 redirect)."
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
        if ($status.status -eq "Failed") { Write-Error "Debug info computation failed."; return }
        Start-Sleep -Seconds $delaySeconds
    }

    # --- Step 5: Fetch debug info ---
    $debugInfo = Invoke-RestMethod `
      -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/debugInfo?st=$stampId&sn=$snapshotId&t=$encodedTimestamp&r=$redisCacheRegion&api-version=2025-03-19-preview" `
      -Method GET -Headers @{
        "Authorization" = "Bearer $token"
        "x-ms-client-request-id" = [guid]::NewGuid().ToString()
        "User-Agent" = $userAgent
      }
}

# --- Step 6: Display exception info ---
Write-Host "`n=== Exception Info ==="
Write-Host "Type: $($debugInfo.exceptionInfo.Id)"
Write-Host "Description: $($debugInfo.exceptionInfo.Description)"
Write-Host "Code: $($debugInfo.exceptionInfo.Code)"
Write-Host "Stack frames: $($debugInfo.stackFrames.Count)"

# --- Step 7: Fetch variables for user code frames (2 levels deep) ---
# Only auto-fetch variables for frames with source file info (user code).
# Framework frames are listed but their variables are skipped to reduce API calls.
# The user can request variable expansion for specific framework frames if needed.
Write-Host "`n--- CALL STACK ---"
$frameIndex = 0
$userFrameCount = 0
$skippedFrameCount = 0
foreach ($frame in $debugInfo.stackFrames) {
    $location = ""
    $isUserCode = $false
    if ($frame.File) {
        $location = " - $($frame.File)"
        if ($frame.Line) { $location += ":$($frame.Line)" }
        $isUserCode = $true
    }
    Write-Host "[$frameIndex] $($frame.Name)$location"

    if (-not $isUserCode) {
        # Framework frame — list it but skip variable fetching
        if ($frame.Variables -and $frame.Variables.Count -gt 0) {
            Write-Host "    (framework frame — $($frame.Variables.Count) variable(s) available, skipped)"
            $skippedFrameCount++
        } else {
            Write-Host "    (no variables)"
        }
    } elseif ($frame.Variables -and $frame.Variables.Count -gt 0) {
        # User code frame — fetch and display variables
        $userFrameCount++
        $frameVarBody = @{
            stampId = $stampId
            snapshotId = $snapshotId
            snapshotTimestamp = $snapshotTimestamp
            redisCacheRegion = $redisCacheRegion
            indices = $frame.Variables
        } | ConvertTo-Json

        $frameVars = Invoke-RestMethod `
          -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/variables?api-version=2025-03-19-preview" `
          -Method POST -Headers @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
            "x-ms-client-request-id" = [guid]::NewGuid().ToString()
            "User-Agent" = $userAgent
          } -Body $frameVarBody

        foreach ($v in $frameVars) {
            Write-Host "    $($v.name) ($($v.type)) = $($v.value)"

            # Show child variables (level 2)
            if ($v.children -and $v.children.Count -gt 0) {
                $childBody = @{
                    stampId = $stampId
                    snapshotId = $snapshotId
                    snapshotTimestamp = $snapshotTimestamp
                    redisCacheRegion = $redisCacheRegion
                    indices = @($v.children | Select-Object -First 10)
                } | ConvertTo-Json

                $childVars = Invoke-RestMethod `
                  -Uri "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/variables?api-version=2025-03-19-preview" `
                  -Method POST -Headers @{
                    "Authorization" = "Bearer $token"
                    "Content-Type" = "application/json"
                    "x-ms-client-request-id" = [guid]::NewGuid().ToString()
                    "User-Agent" = $userAgent
                  } -Body $childBody

                foreach ($cv in $childVars) {
                    Write-Host "      +-- $($cv.name) ($($cv.type)) = $($cv.value)"
                }
            }
        }
    } else {
        Write-Host "    (no variables)"
    }
    $frameIndex++
}

Write-Host "`nFetched variables for $userFrameCount user code frame(s). Skipped $skippedFrameCount framework frame(s)."
Write-Host "To inspect a specific framework frame's variables, re-run with its variable indices."
```

## Notes

- The script uses `try-catch` for 302 redirect handling during trigger and polling, as PowerShell throws exceptions on 302 even with `-SkipHttpErrorCheck` when `-MaximumRedirection 0` is set. See [302-redirect-handling.md](../../shared/302-redirect-handling.md) for details on this pattern.
- Token is acquired once at the start. For snapshots that take >60 minutes to process, the token may expire — the polling loop handles 401 by refreshing.
- Variables are only auto-fetched for **user code frames** (those with a `File` property indicating source info). Framework/runtime frames are listed with their method names but their variables are skipped to reduce noise and API calls. This mirrors how the profiler hot path skill only expands nodes along the hot path.
- Variables are fetched per-frame (not batched globally) because the `/variables` API returns variables positionally — the `id` field in the response is not a unique global identifier.
- Child variable expansion is capped at 10 children per variable to avoid overwhelming output.
- The user can request variable expansion for specific framework frames if needed — use the [get-variables.md](get-variables.md) script with the frame's variable indices.
- The output shows each stack frame with its variables indented beneath it. Child variables are shown with a `+--` prefix.

## User communication

The debug info pipeline involves multiple steps that can take 1–2 minutes:

1. **Triggering computation** — usually instant, but may take a few seconds
2. **Polling for completion** — up to 90 seconds (45 polls × 2s) for fresh computations
3. **Fetching debug info** — usually under 5 seconds
4. **Fetching variables** — only for user code frames (those with source file info), typically 2–4 API calls. Framework frames are listed but their variables are skipped. The user can request expansion of specific framework frames afterward.

Before running this pipeline, inform the user that the debug info fetch is a multi-step process and may take a minute or two. Provide periodic status updates (the script's `Write-Host` output serves this purpose) so the user knows the process hasn't stalled. If the computation is already cached (302 on trigger), the entire pipeline completes in seconds.
