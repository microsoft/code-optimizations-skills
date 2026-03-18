# Find Profiler Traces

If the user doesn't have a specific trace location ID, query the Application Insights resource for recent profiler samples.

This requires the Application Insights **resource ID** (not the app ID). Use the `az monitor app-insights query` command:

```powershell
az monitor app-insights query \
  --apps "<RESOURCE_ID>" \
  --analytics-query "customEvents | where name == 'ServiceProfilerSample' | project timestamp, customDimensions | order by timestamp desc | take 10" \
  --output json
```

Each result contains a `customDimensions` JSON string with a `ServiceProfilerContent` field. That value is the **trace location ID**.

Example `ServiceProfilerContent` value:

```
v1|westus2-ey2ahqc2dsyvq|a1163c00-895c-42ee-9c55-4c527742f747|weatherapp-6f5766589f-dkxzk|1|2026-03-18T21:00:39.1061639Z|/#1/1/61035/|2026-03-18T21:00:43.1159071Z|2026-03-18T21:00:43.1310982Z
```

The format is: `v1|{stampId}|{dataCube}|{machineName}|{processId}|{sessionId}|{activityPath}|{requestStartTime}|{requestEndTime}`

Present the traces to the user (timestamp, machine, activity path) and let them pick one.
