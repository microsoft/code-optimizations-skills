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

> **Note:** The `key` and `timestamp` values come from the rollups response returned by [get-code-optimizations.md](get-code-optimizations.md). Extract these values from the response before running this script, as PowerShell variables do not persist across separate command invocations.

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

## Handling empty recommendations

The AI recommendation may return an empty or null `recommendation` field for some insights. This can happen when:

- The insight is too new and the recommendation engine hasn't generated content yet
- The issue type doesn't have a recommendation template
- The service is temporarily unable to generate a recommendation

When the recommendation is empty:

1. **Do not treat this as an error** — the insight itself (from the rollups response) is still valid and actionable.
2. **Proceed with analysis** — use the `issueCategory`, `function`, `symbol`, `context` (call stack), and `value`/`criteria` fields from the rollups response to understand the bottleneck.
3. **Use the hot path** — invoke the `get-profile-hotpath` skill to get method-level call tree data for the affected operation.
4. **Inspect source code** — navigate to the method identified in the `symbol` field and look for common performance anti-patterns (inefficient algorithms, unnecessary allocations, blocking calls).
5. **Generate your own recommendation** — based on the profiler data and source code analysis, provide a concrete optimization suggestion to the user.
