# Resolve App ID from Resource ID

If the user provides an Application Insights **resource ID** instead of an **app ID**, resolve it with:

```powershell
az monitor app-insights component show \
  --ids "<RESOURCE_ID>" \
  --query "appId" -o tsv
```

Example:

```powershell
az monitor app-insights component show \
  --ids "/subscriptions/bbe41737-1ade-44df-8e33-217f11b8b452/resourceGroups/aks-weather-demo/providers/microsoft.insights/components/weather-ai" \
  --query "appId" -o tsv
```

The returned GUID (e.g. `a1163c00-895c-42ee-9c55-4c527742f747`) is the **app ID** to use in subsequent API calls.
