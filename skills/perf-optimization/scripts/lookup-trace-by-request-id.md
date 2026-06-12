# Look Up Trace Location ID by Request ID

After [query-slow-requests.md](query-slow-requests.md) identifies slow requests with profiler traces, use this script to resolve the `ServiceProfilerContent` (trace location ID) for specific request IDs. The trace location ID is required by the `get-profile-hotpath` skill.

## Script

> ⚠️ Read [az CLI query pitfalls](../../shared/az-cli-query-pitfalls.md) before modifying this script. Key requirements: `--offset` is mandatory, use `--output json`, and flatten KQL to a single line.

```powershell
$resourceId = "<RESOURCE_ID>"
$requestIds = @("REQUEST_ID_1", "REQUEST_ID_2")  # From query-slow-requests.md results
$lookbackHours = 24

# Build comma-separated quoted list for KQL 'in' operator
$reqIdList = ($requestIds | ForEach-Object { "'$_'" }) -join ", "

$query = "customEvents | where name == 'ServiceProfilerSample' | extend reqId = tostring(customDimensions['RequestId']) | where reqId in ($reqIdList) | extend spc = tostring(customDimensions['ServiceProfilerContent']) | project timestamp, spc, reqId | order by timestamp desc"

$offset = if ($lookbackHours -le 24) { "P1D" } elseif ($lookbackHours -le 168) { "P7D" } else { "P30D" }

$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset $offset `
  --output json 2>&1

if (-not $result -or $result -match "ERROR" -or $result -match "BadArgumentError") {
  Write-Host "ERROR: Query failed. Output:"
  Write-Host $result
} else {
  try {
    $parsed = $result | ConvertFrom-Json
  } catch {
    Write-Host "ERROR: Failed to parse query results: $_"
    Write-Host $result
    return
  }

  $rows = $parsed.tables[0].rows
  if ($rows.Count -eq 0) {
    Write-Host "No profiler traces found for the specified request IDs."
  } else {
    Write-Host "Found $($rows.Count) trace(s):`n"
    foreach ($row in $rows) {
      Write-Host "Request ID: $($row[2])"
      Write-Host "Trace Location ID: $($row[1])"
      Write-Host "Timestamp: $($row[0])"
      Write-Host "---"
    }
  }
}
```

## Usage

1. Run [query-slow-requests.md](query-slow-requests.md) to find slow requests with profiler traces
2. Copy the request IDs of interest (the `id` column from the results)
3. Replace `REQUEST_ID_1`, `REQUEST_ID_2` in the `$requestIds` array above
4. Run this script to get the corresponding `ServiceProfilerContent` values
5. Pass the `ServiceProfilerContent` value as the trace location ID to the `get-profile-hotpath` skill
