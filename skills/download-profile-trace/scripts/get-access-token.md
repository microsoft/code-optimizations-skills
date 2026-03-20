# Get Access Token

Acquire a Bearer token for the Application Insights Profiler dataplane API.

```powershell
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)
```

This token is used in the `Authorization: Bearer <token>` header for all subsequent API calls.

The token is typically valid for **~85 minutes**. However, the `$token` variable only exists in the PowerShell session where it was set. **Always re-acquire the token in the same command block as the API call** to avoid 401 errors from cross-session variable scoping. Each script in this skill includes the token acquisition inline for this reason.
