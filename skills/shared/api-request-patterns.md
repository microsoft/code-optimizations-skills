# API Request Patterns

Standard patterns for making requests to the Application Insights Profiler dataplane API. All scripts in this project follow these conventions for consistency.

## Token acquisition

Acquire a Bearer token using Azure CLI. See [get-access-token.md](get-access-token.md) for details.

```powershell
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)
```

## Correlation ID

Generate a unique GUID for each request to enable request tracing and diagnostics:

```powershell
$correlationId = [guid]::NewGuid().ToString()
```

## User-Agent

All HTTP requests must include a `User-Agent` header to identify this plugin. See [user-agent.md](user-agent.md) for the full convention.

Read `version` and `commit` from `plugin.json` (at the repository root) and construct the agent string:

```powershell
$userAgent = "perf-copilot/$version (commit:$commit)"
```

## Standard headers

All dataplane API calls require an `Authorization` header, a `x-ms-client-request-id` header for correlation, and a `User-Agent` header:

```powershell
# For GET requests (no body)
$headers = @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
}

# For POST/PUT requests with a JSON body — add Content-Type
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
    "x-ms-client-request-id" = $correlationId
    "User-Agent" = $userAgent
}
```

Alternatively, when using `Invoke-WebRequest` or `Invoke-RestMethod`, you can pass `-ContentType "application/json"` as a separate parameter instead of including it in the headers dictionary.

## URL encoding for trace location IDs

Trace location IDs contain pipe characters and other special characters that must be URL-encoded when used in query parameters:

```powershell
$encodedTrace = [System.Uri]::EscapeDataString($traceLocationId)
```

See [trace-location-id-format.md](trace-location-id-format.md) for the full format specification.

## 302 redirect handling

The profiler dataplane uses 302 redirects for cached results. See [302-redirect-handling.md](302-redirect-handling.md) for the issue and standard workaround pattern.
