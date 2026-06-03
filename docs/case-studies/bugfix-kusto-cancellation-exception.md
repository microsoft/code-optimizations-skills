# Bug Fix: Unhandled KustoClientRequestCanceledByUserException in Dataplane

**Date:** June 2, 2026
**Service:** Backend dataplane service
**Severity:** Medium (noise/telemetry impact, not data loss)
**Files Changed:** `InsightService.cs`, `BulkQueryByRegionStrategy.cs`, `CentralKustoBulkQueryStrategy.cs`

---

## Executive Summary

The dataplane service was generating **36+ Error-level exceptions per day** (with Snapshot Debugger captures) for `KustoClientRequestCanceledByUserException` — a benign condition caused by clients disconnecting before their Kusto queries complete. The fix catches this exception at the Kusto boundary, downgrades the log level to Warning, and converts it to `OperationCanceledException` for proper ASP.NET Core handling.

---

## 1. How the Issue Was Found

An exported Application Insights exceptions query containing 42 exception rows from the dataplane service was analyzed. The data revealed:

| Exception Type | Count |
|---|---|
| `KustoClientRequestCanceledByUserException` | 36 |
| `Azure.RequestFailedException` | 6 |

All 42 exceptions occurred on a single day (June 2, 2026), all from the same dataplane cloud role. Of the 36 Kusto cancellation exceptions, **22 had Snapshot Debugger captures** (`ai.snapshot.id` present in custom dimensions) — meaning the Snapshot Debugger was actively collecting memory dumps for what is essentially a non-actionable client timeout.

---

## 2. Diagnosis Without the Snapshot Dump (CSV-Only)

From the exported CSV telemetry alone, we could determine:

### What we knew
- **Exception type:** `KustoClientRequestCanceledByUserException`
- **Message:** "Kusto client request has been canceled by the user."
- **Operation:** an authenticated `GET` on an aggregated-insights endpoint
- **Request path:** an aggregated-insights rollup route on the dataplane API
- **Cloud role/instance:** dataplane service (single role instance)
- **Region:** (redacted)
- **Call stack** (from the `details` JSON field):
  - `RestClient2.MakeHttpRequestAsyncImpl` (Kusto SDK)
  - → `CslQueryProviderExtentions.ExecuteQueryAsync` (our code, line 45)
  - → `InsightService.ExecuteInsightsQueryAsync` (our code, line 239)
  - → `InsightService.GetAggregatedInsightsAsync` (our code, line 74)
  - → `AppsInsightsController.GetAggregatedInsightsFromKusto` (our code, line 184)
  - → `AppsInsightsController.GetAggregatedInsights` (our code, line 108)
- **Snapshot identifiers:** `snapshotId`, `stampId` extracted from custom dimensions

### What we could NOT determine
- **Variable values** at the time of the exception (what query was running, what Kusto cluster was targeted, what the cancellation reason was)
- **Whether the CancellationToken was already canceled** before the query started (instant cancellation) or canceled mid-query (timeout)
- **The Kusto cluster URL** and database being queried
- **The client request ID** for correlation with Kusto-side logs

### Conclusion from CSV alone
We could identify the code path and the general pattern (client disconnection → Kusto cancellation → unhandled exception), but could not determine the precise timing or root cause details. The recommendation was speculative: "The client likely disconnected before the query completed."

---

## 3. Diagnosis With the Snapshot Dump

Loading the 1.27 GB snapshot dump in `dotnet-dump` provided significantly more detail:

### Thread identification
```
Thread 60 (OS ID 0x2754) — Threadpool Worker
Exception: KustoClientRequestCanceledByUserException 000001eb6393ad80 (nested exceptions)
```

### Exception chain (from dump objects)
```
KustoClientRequestCanceledByUserException (HResult: 0x80131500)
  └─ TaskCanceledException: "A task was canceled." (HResult: 0x8013153B)
       └─ TaskCanceledException: "A task was canceled." (HResult: 0x8013153B)
            Origin: System.Net.Http.HttpClient.HandleFailure (HttpClient.cs:630)
```

### Variable values extracted from dump

| Field | Value |
|---|---|
| **DataSource** | `https://<redacted>.<region>.kusto.windows.net/v1/rest/query` |
| **DatabaseName** | *(redacted)* |
| **ClientRequestId** | `KD2RunQuery;<redacted-guid>` |
| **ErrorMessage** | *(empty string)* |
| **FailureCode** | 400 |
| **IsPermanent** | true |
| **TimeSinceStarted** | **0.8114 ms** |

### Type hierarchy (from dump class inspection)
```
KustoClientRequestCanceledByUserException
  → KustoClientException
    → KustoException
      → System.Exception    ← does NOT inherit from OperationCanceledException
```

### Key insight from the dump
The **`TimeSinceStarted` was only 0.8114 ms** — the Kusto query was canceled almost immediately after being started. The `CancellationToken` was already in a canceled state when the HTTP request was initiated. This confirms the client had already disconnected before the Kusto call began, making this a completely non-actionable exception.

The type hierarchy analysis was also critical: because `KustoClientRequestCanceledByUserException` does **not** inherit from `OperationCanceledException`, it cannot be caught by existing `catch (OperationCanceledException)` patterns — it requires an explicit catch.

---

## 4. Comparison: CSV vs Dump Diagnosis

| Aspect | CSV Only | With Dump |
|---|---|---|
| Exception type & message | ✅ Known | ✅ Known |
| Call stack | ✅ Full stack from `details` JSON | ✅ Full stack with source line numbers |
| Kusto cluster URL | ❌ Not available | ✅ (recovered, redacted) |
| Database name | ❌ Not available | ✅ (recovered, redacted) |
| Client request ID | ❌ Not available | ✅ (recovered, redacted) |
| Cancellation timing | ❌ Unknown (speculative) | ✅ **0.8ms** — instant, token pre-canceled |
| Exception hierarchy | ❌ Unknown | ✅ Does NOT extend `OperationCanceledException` |
| Nested exception chain | ⚠️ Partial (from `details` JSON) | ✅ Full chain with HResults |
| Root cause confidence | ⚠️ Medium — "likely client disconnect" | ✅ High — confirmed pre-canceled token |
| Fix approach confidence | ⚠️ Might try `catch (OperationCanceledException)` which wouldn't work | ✅ Knew to catch `KustoClientRequestCanceledByUserException` explicitly |

**The dump was essential** for two reasons:
1. Without it, we might have tried catching `OperationCanceledException`, which would **not** catch this exception (wrong inheritance chain).
2. The 0.8ms timing confirmed this is a pure client-disconnect scenario, not a Kusto-side timeout, validating the decision to downgrade to Warning.

---

## 5. The Fix

### Approach

Catch `KustoClientRequestCanceledByUserException` at the Kusto boundary layer, guarded by `cancellationToken.IsCancellationRequested` to ensure only genuine client disconnections are downgraded. Log at Warning level (not Error) and convert to `OperationCanceledException` so ASP.NET Core handles it as a normal request cancellation.

### Changes

#### `InsightService.cs` — Primary fix (non-bulk query path)

```csharp
private async Task<IDataReader> ExecuteInsightsQueryAsync(
    Query query, AzureLocation location, long? take, CancellationToken cancellationToken)
{
    ICslQueryProvider client = await _queryClientProvider
        .GetQueryClientAsync(location, InsightsDatabaseName, cancellationToken);
    try
    {
        return await client.ExecuteQueryAsync(
            query, InsightsDatabaseName, take, cancellationToken).ConfigureAwait(false);
    }
    catch (KustoClientRequestCanceledByUserException ex)
        when (cancellationToken.IsCancellationRequested)
    {
        _logger.LogWarning("Kusto query canceled because the request was aborted.");
        throw new OperationCanceledException(
            "Kusto query canceled because the request was aborted.", ex, cancellationToken);
    }
    catch (KustoRequestThrottledException ex)
    {
        _logger.LogError(ex, "Kusto request throttled.");
        throw;
    }
}
```

#### `BulkQueryByRegionStrategy.cs` — Bulk query path (2 catch sites)

Added `catch (KustoClientRequestCanceledByUserException) when (cancellationToken.IsCancellationRequested)` before both existing `catch (Exception ex)` blocks. Since these paths already swallow exceptions to continue querying other regions/clients, the cancellation is simply logged at Warning and swallowed (no re-throw needed).

#### `CentralKustoBulkQueryStrategy.cs` — Central cache bulk path

Same pattern as `InsightService.cs`: catch before the broad `Exception` catch, log at Warning, re-throw as `OperationCanceledException` (this path re-throws on failure).

### Design Decisions

1. **Why `when (cancellationToken.IsCancellationRequested)`?**
   Only downgrades the exception when the ASP.NET `RequestAborted` token is actually canceled. If Kusto throws this exception for an unexpected reason (not client disconnect), it falls through to the existing error handling.

2. **Why `throw new OperationCanceledException(... ex, cancellationToken)`?**
   Preserves the original Kusto exception as `InnerException` for diagnostics. Passing the `cancellationToken` ensures ASP.NET Core recognizes it as a request cancellation (returns 499/connection reset, not 500).

3. **Why not log `ex` in `LogWarning`?**
   Passing the exception object to the logger would still generate exception telemetry in Application Insights. Since this is a known, non-actionable pattern, a simple message suffices. The original exception is preserved in the `OperationCanceledException.InnerException` if anyone needs to inspect it.

4. **Why fix at the service layer, not the controller?**
   `ExecuteInsightsQueryAsync` is the Kusto boundary for all insight queries. Fixing here covers all callers without duplicating catch logic in every controller action.

---

## 6. Expected Impact

| Metric | Before | After |
|---|---|---|
| Error-level exceptions/day | ~36 | ~0 (for this exception type) |
| Snapshot captures/day | ~22 | 0 |
| Warning-level logs/day | 0 | ~36 (low-cost, no snapshots) |
| Snapshot storage cost | ~22 × 1.27 GB = ~28 GB/day | 0 |
| Alert noise | High | None |

---

## 7. Verification

- **Build:** `dotnet build` succeeded with 0 warnings, 0 errors.
- **No existing tests** for `InsightService`, `BulkQueryByRegionStrategy`, or `CentralKustoBulkQueryStrategy` were found in the test projects.
- The fix uses the same exception handling pattern already established in the codebase (`Utf8JsonWriterResult.cs`, `RecommendationService.cs`).
