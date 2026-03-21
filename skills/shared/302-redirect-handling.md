# 302 Redirect Handling

The Application Insights Profiler dataplane API uses **302 redirects** to signal that cached results are available. This causes a common authentication issue with PowerShell's HTTP cmdlets.

## The problem

When the profiler dataplane returns a 302 redirect (e.g., from `profileTreeDefinitions` POST or `profileTreeComputeStatus` GET), PowerShell's `Invoke-RestMethod` and `Invoke-WebRequest` automatically follow the redirect but **strip the `Authorization` header** on the redirected request. This results in a `401 Unauthorized` on the redirected URL.

## Affected endpoints

| Endpoint | When 302 occurs |
|---|---|
| `POST /profileTreeDefinitions` | Analysis results already exist (cached) |
| `GET /profileTreeComputeStatus` | Analysis just completed — redirects to the profile tree result |

## Workaround

Disable automatic redirects with `-MaximumRedirection 0` and handle the 302 manually:

```powershell
# Disable auto-redirect to avoid auth header being stripped on 302
$response = Invoke-WebRequest `
  -Uri $uri `
  -Method POST `
  -Headers $headers `
  -ContentType "application/json" `
  -Body $body `
  -MaximumRedirection 0 `
  -SkipHttpErrorCheck

if ($response.StatusCode -eq 302) {
    # Follow the redirect manually with the auth header preserved
    $redirectUrl = "https://dataplane.diagnosticservices.azure.com$($response.Headers['Location'])"
    $result = Invoke-RestMethod -Uri $redirectUrl -Method GET -Headers $headers
}
```

## PowerShell exception on 302

PowerShell throws a `WebException` on 302 responses even when `-SkipHttpErrorCheck` is set and `-MaximumRedirection 0` is used. Use a `try-catch` block to handle this:

```powershell
try {
    $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers `
        -MaximumRedirection 0 -SkipHttpErrorCheck
} catch {
    if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
        # 302 means the operation completed — handle accordingly
        Write-Host "302 redirect received (cached/complete result)."
    } else {
        throw  # Re-throw if it's not a 302
    }
}
```

This `try-catch` pattern is especially important in polling loops (e.g., `profileTreeComputeStatus`) where a 302 signals that analysis is complete.
