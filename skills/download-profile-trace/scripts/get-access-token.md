# Get Access Token

Acquire a Bearer token for the Application Insights Profiler dataplane API.

```powershell
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)
```

This token is used in the `Authorization: Bearer <token>` header for all subsequent API calls.

The token is typically valid for ~60–90 minutes. If you get a `401 Unauthorized` response, re-run this command to refresh.
