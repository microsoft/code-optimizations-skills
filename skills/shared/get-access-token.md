# Get Access Token

Acquire a Bearer token for the Application Insights Profiler dataplane API.

```powershell
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)
```

This token is used in the `Authorization: Bearer <token>` header for all subsequent API calls. See [api-request-patterns.md](api-request-patterns.md) for the standard header construction pattern.

## Token lifetime

The token is typically valid for ~60–90 minutes. If you get a `401 Unauthorized` response, re-run this command to refresh.

## Token freshness and session scoping

The `$token` variable only exists in the PowerShell session where it was set. If you run subsequent API calls in a different session (or if the variable is lost), you'll get `401 Unauthorized`. **Re-acquire the token in the same command block as each API call** to ensure it's always available. The token itself lasts ~85 minutes, but session-scoping is the more common cause of 401 errors.

This is especially critical during multi-step operations like the hot path pipeline's polling loop, which may run for over a minute. Always re-acquire the token within the same PowerShell block that makes the API call.
