# Get Recommendation Detail

Fetches an AI-generated recommendation for a specific Code Optimization insight. Use after [get-code-optimizations.md](get-code-optimizations.md) to get actionable fix guidance for a selected recommendation.

## API

```
GET https://dataplane.diagnosticservices.azure.com/api/apps/{appId}/insights/rollups/{key}/recommendation?timestamp={timestamp}&api-version=2024-03-06-preview
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `appId` | Yes | Application Insights app ID (GUID) |
| `key` | Yes | The `key` field from the `AggregatedInsightResult` returned by the rollups endpoint |
| `timestamp` | Yes | ISO 8601 UTC timestamp — the `timestamp` field from the same result |
| `culture` | No | Language identifier (e.g., `en-US`). Defaults to `Accept-Language` header value. |

### Response

```json
{
  "recommendation": "AI-generated recommendation text with specific code optimization guidance"
}
```

## Script

```powershell
$appId = "<APP_ID>"
$key = "<RECOMMENDATION_KEY>"        # From the rollups response .key field
$timestamp = "<RECOMMENDATION_TS>"   # From the rollups response .timestamp field
$correlationId = [guid]::NewGuid().ToString()

# Always re-acquire the token in the same command block to avoid cross-session variable scoping issues
$token = (az account get-access-token --resource "api://dataplane.diagnosticservices.azure.com" --query accessToken -o tsv)

$encodedKey = [System.Uri]::EscapeDataString($key)
$uri = "https://dataplane.diagnosticservices.azure.com/api/apps/$appId/insights/rollups/$encodedKey/recommendation" +
  "?timestamp=$([System.Uri]::EscapeDataString($timestamp))" +
  "&api-version=2024-03-06-preview"

$response = Invoke-RestMethod `
  -Uri $uri `
  -Method GET `
  -Headers @{
    "Authorization" = "Bearer $token"
    "x-ms-client-request-id" = $correlationId
  }

Write-Host $response.recommendation
```
