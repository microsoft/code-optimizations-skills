# Poll Trace Analysis Status

After triggering the trace analysis, poll the `profileTreeComputeStatus` endpoint until the analysis is complete before fetching the profile tree.

## Request

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/profileTreeComputeStatus?t={traceLocationId}&f={showFramework}&api-version=2024-03-06-preview&r={redisCacheRegion}
```

### Query parameters

| Parameter | Description |
|---|---|
| `t` | The trace location ID (URL-encoded `ServiceProfilerContent` value) |
| `f` | `false` to hide framework frames, `true` to show them |
| `api-version` | `2024-03-06-preview` |
| `r` | The `redisCacheRegion` from the metadata endpoint |

### Headers

| Header | Value |
|---|---|
| `Authorization` | `Bearer {token}` |
| `x-ms-client-request-id` | A new GUID for correlation |

## Redirect behaviour (important)

When the analysis completes, the status endpoint may return a **302 redirect** to the profile tree result. PowerShell's `Invoke-RestMethod` automatically follows redirects but **strips the `Authorization` header**, causing a `401 Unauthorized` on the redirected URL. This is the same pattern described in [trigger-trace-analysis.md](trigger-trace-analysis.md).

**Workaround**: Use `Invoke-WebRequest` with `-MaximumRedirection 0` and `-SkipHttpErrorCheck`. If the response is a 302, the analysis is complete — proceed directly to step 7 (fetch the root profile tree). Do not attempt to follow the redirect from the status endpoint.

## PowerShell script

```powershell
$appId = "<APP_ID>"
$traceLocationId = "<TRACE_LOCATION_ID>"
$redisCacheRegion = "<REDIS_CACHE_REGION>"
$showFramework = "false"
$correlationId = [guid]::NewGuid().ToString()

$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
$statusUri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/profileTreeComputeStatus?t=$encodedTrace&f=$showFramework&api-version=2024-03-06-preview&r=$redisCacheRegion"
$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
}

# Increase maxAttempts for large traces if needed (45 × 2s ≈ 90 seconds)
$maxAttempts = 45
$delaySeconds = 2

for ($i = 1; $i -le $maxAttempts; $i++) {
    # Use Invoke-WebRequest with -MaximumRedirection 0 to prevent auto-following
    # 302 redirects, which would strip the Authorization header and cause 401 errors.
    $response = Invoke-WebRequest -Uri $statusUri -Method GET -Headers $headers `
        -MaximumRedirection 0 -SkipHttpErrorCheck

    if ($response.StatusCode -eq 302) {
        # 302 means the analysis is complete — the redirect points to the result.
        # Do NOT follow it here; proceed to step 7 to fetch the profile tree via GET.
        Write-Host "Poll $i — 302 redirect received. Trace analysis is complete."
        break
    }

    if ($response.StatusCode -eq 401) {
        Write-Host "Poll $i — 401 Unauthorized, refreshing token..."
        $token = az account get-access-token `
            --resource "api://dataplane.diagnosticservices.azure.com" `
            --query accessToken -o tsv
        $headers["Authorization"] = "Bearer $token"
        Start-Sleep -Seconds $delaySeconds
        continue
    }

    if ($response.StatusCode -ne 200) {
        Write-Error "Poll $i — Unexpected status code: $($response.StatusCode)"
        Start-Sleep -Seconds $delaySeconds
        continue
    }

    $status = $response.Content | ConvertFrom-Json
    Write-Host "Poll $i — Status: $($status.status)"

    if ($status.status -eq "Complete") {
        Write-Host "Trace analysis is complete."
        break
    }

    if ($status.status -eq "Failed") {
        Write-Error "Trace analysis failed: $($status | ConvertTo-Json -Depth 5)"
        break
    }

    Start-Sleep -Seconds $delaySeconds
}

if ($i -gt $maxAttempts) {
    Write-Error "Trace analysis did not complete within $maxAttempts attempts."
}
```

> **Why `-MaximumRedirection 0`?** When the analysis finishes, the status endpoint returns a 302 redirect to the profile tree result. PowerShell's default behaviour follows the redirect automatically but strips the `Authorization` header, resulting in a 401. Disabling auto-redirect lets us detect the 302 as a "complete" signal and fetch the tree properly in the next step (with the auth header preserved).

## Behaviour

- Poll every 2 seconds, up to 45 attempts (roughly 90 seconds). Increase `$maxAttempts` for larger traces.
- A **302** response means the analysis is complete — proceed to step 7 to fetch the profile tree.
- A **200** response with `status: "Complete"` also means the analysis is done.
- A **200** response with `status: "Failed"` means the analysis failed — try a different trace.
- A **401** response triggers an automatic token refresh and retry.
- Once complete (via 302 or status), proceed to fetch the root profile tree.
