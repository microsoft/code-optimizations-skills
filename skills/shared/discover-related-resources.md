# Discover Related Application Insights Resources

Discovers Application Insights resources related to a primary resource — for example, downstream services or tools whose telemetry lives in separate App Insights components. Uses multiple targeted strategies to avoid listing all components in a subscription.

## When to use

Run this script when:
- You need a complete picture of telemetry across multiple services (e.g., an AI agent and the tools it calls)
- A distributed trace spans multiple App Insights resources
- You want to identify where profiler data, request telemetry, or dependency traces live for downstream components

## Prerequisites

- The primary App Insights resource must already be identified (Resource ID, Subscription ID, Resource Group in `investigation-notes.md`)
- User must be logged in to Azure CLI (`az login`)
- Azure Resource Graph extension is needed for the shared-workspace strategy (`az extension add --name resource-graph` if not installed)

## Parameters

| Parameter | Required | Source | Description |
|-----------|----------|--------|-------------|
| `resourceId` | Yes | `investigation-notes.md` | Full ARM resource ID of the primary App Insights resource |
| `subscriptionId` | Yes | `investigation-notes.md` | Azure subscription GUID |
| `resourceGroup` | Yes | `investigation-notes.md` | Resource group of the primary resource |
| `componentName` | Yes | `investigation-notes.md` | App Insights component name |

## Script

### Step 1: Check investigation notes for existing related resources

Before running discovery, check whether `investigation-notes.md` already has a **"Related Resources"** section. If it does, present the existing entries to the user and ask:
- **Reuse** — skip discovery and use the existing list
- **Update** — run discovery and merge new findings with existing entries
- **Re-discover** — clear existing entries and run discovery from scratch

### Step 2: Query the dependencies table for outbound targets

Query the primary resource's `dependencies` table to map what the application calls.

> ⚠️ Before running this query, review [az CLI query pitfalls](az-cli-query-pitfalls.md).

```powershell
$resourceId = "<RESOURCE_ID>"

$query = "dependencies | where timestamp > ago(7d) | summarize callCount=count(), avgDuration=avg(duration) by target, type, resultCode | order by callCount desc | take 50"

$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset "P7D" `
  --output json 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "WARNING: Dependencies query failed. Continuing with other discovery strategies."
  Write-Host $result
} else {
  $parsed = $result | ConvertFrom-Json
  $rows = $parsed.tables[0].rows
  Write-Host "Found $($rows.Count) distinct dependency targets"
  # Present targets to build context for the user
  foreach ($row in $rows) {
    Write-Host "  Target: $($row[0])  Type: $($row[1])  Calls: $($row[2])  AvgDuration: $([math]::Round($row[3], 1))ms"
  }
}
```

This gives a map of outbound calls — use it to contextualize the resources discovered in the next steps.

### Step 3: Discover related App Insights resources

Run all four strategies below. Each is independent and best-effort — some may return no results. Collect all findings and deduplicate in Step 4.

#### 3a. Same resource group scan

Related services are often deployed in the same resource group. List App Insights components in the primary resource's resource group (excludes the primary itself).

> Uses `az resource list` instead of `az monitor app-insights component list` to avoid extension dependency issues. See [az CLI query pitfalls](az-cli-query-pitfalls.md#prefer-az-resource-list-over-extension-dependent-commands).

```powershell
$resourceGroup = "<RESOURCE_GROUP>"
$primaryName = "<COMPONENT_NAME>"

$components = az resource list `
  -g "$resourceGroup" `
  --resource-type "Microsoft.Insights/components" `
  --query "[?name != '$primaryName'].{name:name, id:id, resourceGroup:resourceGroup}" `
  --output json 2>&1

if ($LASTEXITCODE -eq 0) {
  $parsed = $components | ConvertFrom-Json
  Write-Host "Found $($parsed.Count) other App Insights component(s) in resource group '$resourceGroup'"
  foreach ($c in $parsed) {
    Write-Host "  Name: $($c.name)  ID: $($c.id)"
  }
} else {
  Write-Host "WARNING: Resource group scan failed. Continuing."
}
```

#### 3b. Dependency telemetry IKey correlation

The Application Insights SDK may auto-populate target instrumentation keys in dependency telemetry when the downstream service is also instrumented. Query for these:

```powershell
$resourceId = "<RESOURCE_ID>"

$query = "dependencies | where timestamp > ago(7d) | where isnotempty(customDimensions['ai.internal.sdkVersion']) | extend targetIKey = tostring(customDimensions['ai.target.instrumentationKey']) | where isnotempty(targetIKey) | distinct target, targetIKey | take 20"

$result = az monitor app-insights query `
  --apps "$resourceId" `
  --analytics-query "$query" `
  --offset "P7D" `
  --output json 2>&1

if ($LASTEXITCODE -eq 0) {
  $parsed = $result | ConvertFrom-Json
  $rows = $parsed.tables[0].rows
  if ($rows.Count -gt 0) {
    Write-Host "Found $($rows.Count) dependency target(s) with instrumentation keys"
    foreach ($row in $rows) {
      Write-Host "  Target: $($row[0])  IKey: $($row[1])"
    }
  } else {
    Write-Host "No dependency IKey correlations found (SDK may not populate these for this app)."
  }
} else {
  Write-Host "WARNING: Dependency IKey query failed. Continuing."
}
```

> **Note**: Not all SDKs populate `ai.target.instrumentationKey`. This strategy works best when both the caller and target use the Application Insights SDK with cross-component correlation enabled.

> **AI agent workloads**: AI agent SDKs (e.g., Azure AI Projects) typically emit dependencies with `type=AI` and `target=unknown`. This strategy will not find downstream resources for agent-to-tool calls. For agent workloads, strategy 3d (local config scan) is typically the most reliable discovery method — tool endpoints and connection strings are usually in the source code.

#### 3c. Shared Log Analytics workspace

App Insights resources that share the same underlying Log Analytics workspace are often part of the same application or team. Use Azure Resource Graph to find them:

```powershell
$resourceId = "<RESOURCE_ID>"

# First, get the workspace ID of the primary resource
$workspaceId = az monitor app-insights component show `
  --ids "$resourceId" `
  --query "workspaceResourceId" -o tsv 2>&1

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workspaceId)) {
  Write-Host "WARNING: Could not determine workspace for primary resource. Skipping shared-workspace scan."
} else {
  Write-Host "Primary resource workspace: $workspaceId"

  $graphQuery = "resources | where type == 'microsoft.insights/components' | where properties.WorkspaceResourceId == '$workspaceId' | where id != '$resourceId' | project name, id, resourceGroup, subscriptionId, instrumentationKey=properties.InstrumentationKey"

  # Pre-install Resource Graph extension silently to avoid interactive prompt.
  # See az-cli-query-pitfalls.md#extension-auto-install-prompts-hang-automation
  az extension add --name resource-graph --yes 2>$null

  $graphResult = az graph query -q "$graphQuery" --first 10 --output json 2>&1

  if ($LASTEXITCODE -eq 0) {
    $parsed = $graphResult | ConvertFrom-Json
    $data = $parsed.data
    if ($data.Count -gt 0) {
      Write-Host "Found $($data.Count) App Insights resource(s) sharing the same workspace"
      foreach ($r in $data) {
        Write-Host "  Name: $($r.name)  RG: $($r.resourceGroup)  IKey: $($r.instrumentationKey)"
      }
    } else {
      Write-Host "No other App Insights resources share the same workspace."
    }
  } else {
    Write-Host "WARNING: Resource Graph query failed. You may need to install the extension: az extension add --name resource-graph"
  }
}
```

#### 3d. Local config scan for additional connection strings

Scan the working directory for Application Insights connection strings. Any `InstrumentationKey` that differs from the primary resource is a candidate downstream resource. This reuses the pattern from [check-connection-string-match.md](check-connection-string-match.md).

```powershell
$primaryIKey = "<PRIMARY_INSTRUMENTATION_KEY>"  # Resolve from primary resource if not known

$patterns = @("appsettings*.json", "*.bicep", "*.bicepparam", ".env", "launchSettings.json")
$found = @()

foreach ($pat in $patterns) {
  $files = Get-ChildItem -Path . -Filter $pat -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](bin|obj|node_modules)[\\/]' }
  foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    $matches = [regex]::Matches($content, 'InstrumentationKey=([0-9a-fA-F\-]{36})')
    foreach ($m in $matches) {
      $ikey = $m.Groups[1].Value
      if ($ikey -ne $primaryIKey) {
        $relPath = $f.FullName.Replace((Get-Location).Path + "\", "")
        $found += [PSCustomObject]@{ File = $relPath; InstrumentationKey = $ikey }
      }
    }
  }
}

if ($found.Count -gt 0) {
  Write-Host "Found $($found.Count) additional connection string(s) in local config files"
  $found | Select-Object File, InstrumentationKey -Unique | ForEach-Object {
    Write-Host "  File: $($_.File)  IKey: $($_.InstrumentationKey)"
  }
} else {
  Write-Host "No additional connection strings found in local config files."
}
```

### Step 4: Deduplicate and resolve

Merge all findings from steps 3a–3d. Deduplicate by instrumentation key or resource ID. For any IKeys discovered through dependency correlation (3b) or config scan (3d) that haven't been resolved to a resource name, resolve them.

Use Azure Resource Graph to search across **all accessible subscriptions** — downstream resources are often in a different subscription than the primary:

> ⚠️ Pre-install the Resource Graph extension before querying. See [az CLI query pitfalls](az-cli-query-pitfalls.md#extension-auto-install-prompts-hang-automation).

```powershell
$unknownIKey = "<INSTRUMENTATION_KEY>"

# Pre-install Resource Graph extension silently
az extension add --name resource-graph --yes 2>$null

# Search across ALL accessible subscriptions for this IKey
$graphQuery = "resources | where type == 'microsoft.insights/components' | where properties.InstrumentationKey == '$unknownIKey' | project name, id, resourceGroup, subscriptionId, instrumentationKey=properties.InstrumentationKey"

$graphResult = az graph query -q "$graphQuery" --first 5 --output json 2>&1

if ($LASTEXITCODE -eq 0) {
  $parsed = $graphResult | ConvertFrom-Json
  if ($parsed.data.Count -gt 0) {
    foreach ($r in $parsed.data) {
      Write-Host "Resolved IKey $unknownIKey → $($r.name) (RG: $($r.resourceGroup), Sub: $($r.subscriptionId))"
    }
  } else {
    Write-Host "WARNING: IKey $unknownIKey not found in any accessible subscription."
  }
} else {
  Write-Host "WARNING: Resource Graph query failed. Falling back to single-subscription lookup."
  # Fallback: search only the primary subscription
  $subscriptionId = "<SUBSCRIPTION_ID>"
  $component = az resource list `
    --subscription "$subscriptionId" `
    --resource-type "Microsoft.Insights/components" `
    --query "[?properties.InstrumentationKey == '$unknownIKey'].{name:name, id:id, resourceGroup:resourceGroup}" `
    --output json 2>&1
}
```

> **If an IKey cannot be resolved**: Present it to the user with the source (which file or dependency it came from) and ask if they can identify the resource or provide the subscription it belongs to.

### Step 5: Present findings and ask the user

Present a consolidated table of all discovered resources, including the primary. For each, show:
- **Resource Name** and **Resource Group**
- **How it was discovered** (same RG, dependency IKey, shared workspace, config file, or primary)
- **A suggested role label** — infer from dependency targets if possible (e.g., if a dependency target hostname matches a resource name, suggest "Tool: \<target\>"). Default to "Unknown — please label".

Ask the user to:
1. **Confirm** which resources are relevant to the investigation
2. **Label** each with a role (e.g., "Agent host", "Tool: SearchAPI", "Backend: SQL")
3. **Add** any additional resources not discovered automatically
4. **Remove** any irrelevant resources

### Step 6: Write to investigation notes

Write or update the **"Related Resources"** section in `investigation-notes.md`. Use the table format defined in [investigation-notes.md](investigation-notes.md):

```markdown
## Related Resources

| Role | Resource Name | Resource ID | App ID | Subscription ID | Resource Group |
|------|---------------|-------------|--------|-----------------|----------------|
| Agent host | `my-agent-ai` | `/subscriptions/.../components/my-agent-ai` | `<guid>` | `<guid>` | `my-rg` |
| Tool: SearchAPI | `search-api-ai` | `/subscriptions/.../components/search-api-ai` | `<guid>` | `<guid>` | `my-rg` |
```

If the section already exists, merge — update existing entries and append new ones. Do not remove entries the user previously confirmed unless they explicitly ask.

## Limitations

- **Same resource group scan (3a)** only finds resources co-located in the primary resource group. Downstream services are often in different resource groups or even different subscriptions.
- **Dependency IKey correlation (3b)** depends on the SDK populating `ai.target.instrumentationKey`. This works best with cross-component correlation enabled; many apps won't have this. **AI agent telemetry** (type=AI) typically has `target=unknown`, making this strategy ineffective for agent-to-tool dependencies.
- **Shared workspace scan (3c)** requires the `resource-graph` Azure CLI extension. The script pre-installs it, but the query may be slow if the user has access to many subscriptions.
- **Config scan (3d)** only finds connection strings in local source code. Deployed apps may use different connection strings set via environment variables or Key Vault. **For AI agent workloads, this is often the most reliable strategy** since tool endpoints are typically in the source code.
- **IKey resolution (Step 4)** uses Azure Resource Graph to search across all accessible subscriptions, with a single-subscription fallback.
- Not all dependency targets will have their own App Insights resource. The discovery is best-effort.
