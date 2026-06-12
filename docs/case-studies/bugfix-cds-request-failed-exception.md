# Bug Fix: CDS RequestFailedException Handling and Cache Resilience

**Date:** June 2, 2026
**Service:** Backend dataplane service
**Severity:** Medium (incorrect error responses, 15-minute cache amplification of transient failures)
**Files Changed:** `CdsClient.cs`, `CdsOptions.cs`, `CdsProfileFilter.cs`, `CdsProfilesBulkFilter.cs`

---

## Executive Summary

The Dataplane service was returning **HTTP 500 with Error-level logging** for all CDS (Configuration Data Service) failures — including transient HTTP 500s from CDS itself. Worse, a cache design flaw caused **faulted tasks to be served for 15 minutes** after a single transient failure, amplifying brief CDS outages into prolonged service degradation. The fix differentiates transient errors (5xx/429) from permanent failures, returns appropriate HTTP status codes, evicts transient failures from the cache, and increases retry resilience.

---

## 1. How the Issue Was Found

An exported Application Insights exceptions query containing 42 exception rows was analyzed. Among the two exception types found:

| Exception Type | Count |
|---|---|
| `KustoClientRequestCanceledByUserException` | 36 |
| `Azure.RequestFailedException` | **6** |

All 6 `RequestFailedException` occurrences had the same message: **"Failed to get the CDS profile."** — thrown from `CdsClient.GetCdsProfileAsync` at `CdsClient.cs:203`. The call stack showed the exception propagating through:

```
CdsClient.GetCdsProfileAsync
  → CdsClient.GetCachedCdsProfileAsync
    → CdsProfileFilter.OnAuthorizationAsync
```

Of the 6 exceptions, **4 had Snapshot Debugger captures** (`ai.snapshot.id` present).

---

## 2. Diagnosis Without the Snapshot Dump (CSV-Only)

### What we knew
- **Exception type:** `Azure.RequestFailedException`
- **Message:** "Failed to get the CDS profile." — a generic message with **no HTTP status code**
- **Operation:** an authenticated `GET` on an aggregated-insights endpoint
- **Cloud role:** backend dataplane service
- **Call stack:** `CdsClient.GetCdsProfileAsync` → `CdsProfileFilter.OnAuthorizationAsync`

### What we could NOT determine
- **The HTTP status code** CDS returned (400? 429? 500? 503?)
- **Whether this was transient or permanent** — critical for choosing the fix approach
- **Whether retries had already been attempted** (Azure SDK pipeline configuration)
- **The specific CDS endpoint or resource** being queried

### Conclusion from CSV alone
We could identify the code path but the generic exception message made it impossible to determine whether CDS was throttling us (429), experiencing an outage (500), or rejecting our request (4xx). The fix approach was ambiguous — should we retry? Rate-limit? Improve error messages?

---

## 3. Diagnosis With the Snapshot Dumps

Four crash dumps were available for the `RequestFailedException` instances. Using `dotnet-dump analyze`, we extracted the `<Status>k__BackingField` from the exception object on each dump's exception thread:

| Dump # | Thread | HTTP Status |
|---|---|---|
| 1 | Thread 63 | **500** |
| 2 | Thread 59 | **500** |
| 3 | Thread — | **500** |
| 4 | Thread — | **500** |

### Key findings from dumps
1. **All 4 dumps confirmed HTTP 500** — CDS was returning Internal Server Error, not throttling or rejecting
2. The `Status` property was accessible via `dumpobj` on the exception instance: `<Status>k__BackingField = 500`
3. These are **transient CDS-side failures**, not client errors or permanent conditions

### Extraction technique
```
> clrthreads                          # Find thread with RequestFailedException
> setthread <N>                       # Switch to exception thread
> dumpobj <exception_address>         # Inspect exception fields
  → <Status>k__BackingField = 500    # HTTP status code from CDS
```

---

## 4. Comparison: CSV vs Dump Diagnosis

| Aspect | CSV Only | With Dump |
|---|---|---|
| Exception type & message | ✅ Known | ✅ Known |
| Call stack | ✅ Full stack | ✅ Full stack with line numbers |
| HTTP status code from CDS | ❌ Not in message | ✅ **500** (from `Status` field) |
| Transient vs permanent? | ❌ Unknown | ✅ Transient (500 = server error) |
| Fix approach confidence | ⚠️ Low — could be 429, 500, or 4xx | ✅ High — confirmed transient, improve handling |
| Retry feasibility | ❌ Unknown | ✅ Azure SDK already retries once (`MaxRetries=1`) |

**The dump was essential** because:
1. The exception message was generic ("Failed to get the CDS profile.") with no status code — the dump revealed the `Status` field holding **500**
2. Knowing all failures were HTTP 500 confirmed these are transient CDS outages, validating the decision to downgrade to Warning and return 503 (ServiceUnavailable) instead of 500 (InternalServerError)
3. Without the dump, we might have treated all CDS errors uniformly or guessed at the wrong fix

---

## 5. Additional Issue Found During Code Review

During multi-model code review (Opus 4.7, round 2), a **critical pre-existing bug** was discovered:

### The Faulted-Task Cache Problem

The CDS client uses `MemoryCache` with a custom `GetOrCreateAsync` extension that caches the `Task<T>` object itself (not the result). The cache flow:

```
Request 1 (cache miss):
  cache[key] = Task<CdsProfile>  ← stored BEFORE awaiting
  Task runs → throws RequestFailedException(500)
  Task is now faulted, but REMAINS in cache for 15 minutes

Requests 2..N (cache hit):
  cache.TryGetValue(key) → returns faulted Task
  await faultedTask → immediately re-throws same exception
  CDS is NEVER contacted again for this key
```

**Impact:** A single transient CDS 500 would cause **all requests for that appId/subscription/link to fail for 15 minutes** — even if CDS recovered in seconds. This transformed brief CDS hiccups into prolonged outages.

This bug affected three cached methods:
- `GetCachedCdsProfileAsync` (profile lookups)
- `GetSubscriptionStateAsync` (subscription state)
- `GetPrivateEndpointConnectionPropertiesAsync` (private endpoint)

---

## 6. The Fix

### 6.1 Improved Exception Message (`CdsClient.cs`)

```csharp
// Before
throw new RequestFailedException(response.Status, "Failed to get the CDS profile.");

// After
throw new RequestFailedException(response.Status,
    $"Failed to get the CDS profile. CDS returned HTTP {response.Status}.");
```

Now the exception message includes the HTTP status code, making CSV-only diagnosis possible in the future.

### 6.2 Cache Eviction for Transient Failures (`CdsClient.cs`)

Applied to all three cached methods:

```csharp
private async Task<CdsProfile> GetCachedCdsProfileAsync<TKey>(
    TKey key, Func<TKey, CancellationToken, Task<CdsProfile>> asyncFactory,
    CancellationToken cancellationToken)
{
    try
    {
        return await _memoryCache.GetOrCreateAsync(key, asyncFactory,
            _cacheEntryLifetime, cancellationToken).ConfigureAwait(false)
            ?? throw new CdsProfileNotFoundException("...");
    }
    catch (RequestFailedException ex) when (ex.Status >= 500 || ex.Status == 429)
    {
        // Evict transient failures from cache so the next request retries
        // instead of re-throwing the cached faulted task for 15 minutes.
        _memoryCache.Remove(key);
        throw;
    }
}
```

### 6.3 Specific Error Handling in Dataplane CdsProfileFilter

```csharp
catch (RequestFailedException ex) when (ex.Status == StatusCodes.Status429TooManyRequests)
{
    _logger.LogWarning("CDS returned 429 (Too Many Requests) for app id {AppId}", appId);
    TimeSpan retryAfter = TimeSpan.FromSeconds(10);
    context.Result = TooManyRequests("CDS rate limit exceeded. Please retry later.", retryAfter);
}
catch (RequestFailedException ex) when (ex.Status >= 500)
{
    _logger.LogWarning("CDS returned HTTP {StatusCode} for app id {AppId}", ex.Status, appId);
    context.Result = ServiceUnavailable("CDS service error. Please retry later.");
}
```

This mirrors the existing FrontEnd `CdsProfileFilter` pattern and uses proper HTTP response helpers instead of `Unauthorized(HttpStatusCode.InternalServerError, ...)`.

### 6.4 Bulk Filter Transient Handling (`CdsProfilesBulkFilter.cs`)

```csharp
catch (RequestFailedException ex) when (ex.Status >= 500 || ex.Status == 429)
{
    // Transient CDS errors — log as warning and continue processing other apps.
    _logger.LogWarning("CDS returned HTTP {StatusCode} for app id {AppId}", ex.Status, app);
}
```

### 6.5 Increased Retry Resilience (`CdsOptions.cs`)

```csharp
// Before
public int MaxRetries { get; set; } = 1;

// After
public int MaxRetries { get; set; } = 3;
```

---

## 7. Design Decisions

1. **Why return 503 (ServiceUnavailable) instead of 500 (InternalServerError) for CDS 5xx?**
   HTTP 500 implies a bug in *our* code. HTTP 503 correctly signals that an upstream dependency is temporarily unavailable, and clients can retry.

2. **Why use sanitized messages instead of `ex.Message`?**
   Azure SDK's `RequestFailedException.Message` includes the full response (status line, headers, body) which could leak internal CDS endpoints and correlation IDs to external callers. The Opus 4.7 review caught this information disclosure risk.

3. **Why handle 429 separately from 5xx?**
   429 (Too Many Requests) has different semantics — it signals throttling, not an outage. Returning `TooManyRequests` with a `Retry-After` header enables proper client backoff behavior. This matches the FrontEnd's existing pattern.

4. **Why evict from cache instead of fixing `MemoryCacheExtensions`?**
   The cache extension is shared across the codebase. Changing it could affect other consumers that intentionally cache faulted tasks. The targeted fix in `CdsClient` is safer and scoped to the CDS domain.

5. **Why increase MaxRetries to 3?**
   With MaxRetries=1, the Azure SDK pipeline only retries once. For transient 500s, additional retries increase the chance of success. The exponential backoff built into the Azure SDK pipeline prevents thundering herd issues.

---

## 8. Expected Impact

| Metric | Before | After |
|---|---|---|
| Error-level exceptions for CDS 500 | ~6/day | 0 |
| Warning-level logs for CDS 500 | 0 | ~6/day |
| Snapshot captures for CDS errors | ~4/day | ~4/day (first-chance, unchanged) |
| Failure amplification window | **15 minutes** per appId | **0** (cache evicted) |
| HTTP response for CDS 500 | 500 InternalServerError | 503 ServiceUnavailable |
| HTTP response for CDS 429 | 500 InternalServerError | 429 TooManyRequests + Retry-After |
| Retry attempts per CDS call | 1 + original | 3 + original |

### Note on Snapshot Captures

The Snapshot Debugger captures on first-chance exceptions — before any `catch` block runs. Our fixes improve *handling* but don't prevent the `throw` at `CdsClient.cs:203`. To reduce snapshot noise, configure Snapshot Debugger to exclude `Azure.RequestFailedException` or raise the snapshot threshold.

---

## 9. Verification

- **Build:** `dotnet build` succeeded with 0 warnings, 0 errors
- **Code Review:** 5 rounds of dual-model review (GPT-5.5 + Opus 4.7) with 2 consecutive clean rounds
  - Round 2: Opus 4.7 discovered the faulted-task cache bug → fixed
  - Round 3: GPT-5.5 found subscription/private-link cache gap; Opus 4.7 found info disclosure → fixed both
  - Rounds 4-5: Both models clean

---

## 10. Key Takeaway: Multi-Model Code Review Finds Real Bugs

The faulted-task cache issue was **not visible** in the original exception telemetry or crash dumps — it was discovered entirely through code review. The dual-model approach proved its value:

| Finding | Discovered By | Round |
|---|---|---|
| Faulted tasks cached for 15 minutes | Opus 4.7 | Round 2 |
| Subscription & private-link cache same issue | GPT 5.5 | Round 3 |
| Information disclosure via `ex.Message` | Opus 4.7 | Round 3 |

Without the multi-model review, the fix would have improved error handling but left the 15-minute cache amplification bug — arguably a worse problem than the original error classification.
