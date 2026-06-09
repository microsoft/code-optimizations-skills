# Investigation: Redis Dependency Blind Spot and Instrumentation

**Date:** June 9, 2026
**Service:** Backend dataplane service
**Severity:** High (20s+ request failures during Redis outage, zero observability into Redis health)
**Files Changed:** `RedisConnectionManager.cs`, `ServiceCollectionExtensions.cs`, `Startup.cs`, plus 4 new files

---

## Executive Summary

A Redis connection pool exhaustion event caused **500 errors on critical resource-creation endpoints** with request durations exceeding 60 seconds. Investigation revealed that Redis operations were **completely invisible** — no dependency telemetry, no profiler frames, no metrics. The 20-second `SyncTimeout` was a known workaround (documented in a code comment) but no data existed to validate whether it was necessary. The fix adds Redis dependency tracking instrumentation by bridging the StackExchange.Redis built-in profiling API to Application Insights `DependencyTelemetry`, enabling future data-driven timeout tuning.

---

## 1. How the Issue Was Found

An error exploration query across the dataplane Application Insights resource with a **7-day lookback** revealed:

| Category | Groups | Key Finding |
|---|---|---|
| Exceptions | 1 type | `RedisConnectionException` — connection timeout |
| Failed Requests | 17 groups | Including 500s on two resource-creation endpoints |
| Failed Dependencies | 27 groups | Including 21s timeouts to IMDS (169.254.169.254) |

A correlated incident emerged in a two-minute window: Redis connection pool exhaustion → 500 errors on two critical create endpoints → IMDS metadata failures that had been occurring for roughly 14 hours leading up to the incident.

---

## 2. Deep Trace Analysis — The Incident

Two operations were analyzed in detail using distributed trace correlation:

### Operation 1: First resource-creation endpoint (62.3s duration)

**Operation ID:** (redacted)

Timeline reconstruction from dependency and trace telemetry:

```
T+0.0s   Request starts
T+0.1s   Blob downloads (artifacts) — succeed normally
T+2.0s   Credential acquisition (GetToken) — succeeds
T+5.0s   Redis StringSet attempt — connection pool exhausted
T+25.0s  Redis SyncTimeout fires (20,000ms configured timeout)
T+25.0s  RedisConnectionException thrown
T+62.3s  Request completes with 500
```

**Anomaly discovered:** `GetToken` calls continued appearing in the trace **2+ hours after the request failed** — a possible token refresh leak where background credential renewal continued on an abandoned request context.

### Operation 2: Second resource-creation endpoint (24s duration)

**Operation ID:** (redacted)

Identical pattern — Redis connection pool exhaustion within the same 2-minute window. Both operations confirmed the same root cause: all Redis connections were dead or hung, and the 20s `SyncTimeout` was the dominant contributor to request latency.

---

## 3. The Observability Gap

### What we could see
- The `RedisConnectionException` in exceptions telemetry
- The 500 HTTP responses in request telemetry
- IMDS dependency failures (21s timeouts to 169.254.169.254)

### What we could NOT see
- **Redis dependency calls** — no `dependencies | where type == "Redis"` data existed at all
- **Redis latency distribution** — no P50/P95/P99 data for normal operations
- **Redis command breakdown** — no visibility into which commands (GET, SET, EVAL) were slow
- **Connection pool health** — no metrics on active/idle/failed connections
- **Redis in profiler traces** — confirmed by fetching a 2,352ms artifact-retrieval profiler trace (see §4)

### Why Redis was invisible

The dataplane uses the classic Application Insights SDK (`Microsoft.ApplicationInsights.AspNetCore 2.23.0`). Unlike HTTP dependencies (auto-collected by the AI SDK) and SQL dependencies (auto-collected via `DiagnosticSource`), **StackExchange.Redis does not emit `DiagnosticSource` events**. Redis dependency tracking requires explicit instrumentation.

No `Microsoft.ApplicationInsights.StackExchangeRedis` NuGet package exists — unlike the SQL and HTTP equivalents, Microsoft never shipped an official AI SDK Redis collector.

---

## 4. Profiler Trace Analysis — Confirming the Blind Spot

To verify whether Redis operations might appear in CPU profiler traces, we queried profiler samples near the incident window and analyzed the hottest artifact-retrieval trace (2,352ms duration):

**Hot path result:**

| Component | Time | % of Total |
|---|---|---|
| Azure Authorization (CheckAccess → HTTP to PDP) | 2,131ms | 90.6% |
| JIT Compilation (cold start) | 771ms | 32.8% |
| MISE Auth Middleware | 1,596ms | 67.9% |
| **Redis** | **Not present** | **0%** |

> Percentages exceed 100% due to parallel execution across threads.

**Why Redis doesn't appear:** The Application Insights Profiler uses CPU sampling. Redis operations are async I/O — when the thread `await`s a Redis call, it yields to the thread pool. The profiler sees `AWAIT_TIME` but cannot attribute it to Redis without framework dependency frames enabled. For healthy Redis calls (sub-millisecond), they never appear on the hot path because other operations dominate.

**Conclusion:** Neither dependency telemetry nor CPU profiling can reveal Redis behavior without explicit instrumentation. This validated the decision to add instrumentation before attempting any configuration changes.

---

## 5. Codebase Analysis — Redis Configuration and Usage

### Redis Connection Configuration (`RedisConnectionManager.cs`)

```csharp
private const int SyncTimeoutInMilliseconds = 20000;  // 20 seconds

var config = ConfigurationOptions.Parse(connectionString);
config.ConnectRetry = 5;
config.KeepAlive = ConnectionTtlInSeconds;  // 180s
config.AbortOnConnectFail = false;
// SyncTimeout is set to 20 seconds as a workaround — current payloads
// can be very large and need extra time. TODO: consider chunking payloads.
config.SyncTimeout = SyncTimeoutInMilliseconds;
```

The 20s timeout has a code comment acknowledging it as a workaround, but no telemetry exists to validate whether current operations actually need it.

### Redis Usage Patterns

All Redis operations in the codebase are lightweight:

| Component | Operations | Expected Latency |
|---|---|---|
| `ClientCache<T>` | StringGet, StringSet, KeyExists, KeyDelete | < 5ms |
| `RedisSlidingWindowRateLimiter` | ScriptEvaluate (Lua on sorted sets) | < 5ms |
| SignalR Redis backplane | Pub/Sub (managed by SignalR) | < 1ms |
| Aggregation result listener | StringGet polling | < 5ms |

**No operation requires 20 seconds.** But without latency data, reducing the timeout is a blind change — hence instrumentation first.

### Missing Resilience Patterns

- **No `BacklogPolicy`** — defaults to queuing, which can cause cascading failures when the connection pool is exhausted
- **No circuit breaker** — failed connections retry indefinitely
- **No connection pooling** — single `ConnectionMultiplexer` per environment, cached in `IMemoryCache`

---

## 6. The Fix — Redis Dependency Instrumentation

### Approach

Bridge StackExchange.Redis's built-in profiling API (`IProfiler` / `ProfilingSession`) to Application Insights `DependencyTelemetry`. This is zero-risk (purely observational) and uses public, stable APIs on both sides.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  ASP.NET Core Pipeline                              │
│                                                     │
│  RedisProfilingMiddleware                           │
│    ├─ BeginProfiling() ← starts session             │
│    ├─ await next(context)                           │
│    └─ FinishProfiling() ← emits DependencyTelemetry│
│                                                     │
│  ApplicationInsightsRedisInitializer                │
│    └─ connection.RegisterProfiler(this)             │
│       └─ Uses AsyncLocal<ProfilingSession>          │
│          for per-request isolation                  │
│                                                     │
│  IRedisConnectionInitializer (abstraction)          │
│    ├─ ApplicationInsightsRedisInitializer (dataplane)│
│    └─ NullRedisConnectionInitializer (default)      │
└─────────────────────────────────────────────────────┘
```

### 6.1 Shared Library: Instrumentation Hook (`netstandard2.0`)

**`IRedisConnectionInitializer.cs`** — Interface for post-connect instrumentation:
```csharp
public interface IRedisConnectionInitializer
{
    void Initialize(IConnectionMultiplexer connection);
}
```

**`NullRedisConnectionInitializer.cs`** — Default no-op for projects without AI SDK.

**`RedisConnectionManager.cs`** — Calls `Initialize()` after `ConnectAsync`:
```csharp
public RedisConnectionManager(
    IRedisConnectionProvider connectionProvider,
    IMemoryCache memoryCache,
    ILogger<RedisConnectionManager> logger,
    IRedisConnectionInitializer connectionInitializer = null)  // optional, backward-compatible
```

**`ServiceCollectionExtensions.cs`** — Registers default via `TryAddSingleton` (host can override):
```csharp
services.TryAddSingleton<IRedisConnectionInitializer, NullRedisConnectionInitializer>();
```

### 6.2 Dataplane: AI SDK Bridge

**`ApplicationInsightsRedisInitializer.cs`** — Bridges SE.Redis profiling to AI DependencyTelemetry:

```csharp
public class ApplicationInsightsRedisInitializer : IRedisConnectionInitializer, IProfiler
{
    private readonly AsyncLocal<ProfilingSession> _session = new();
    private readonly TelemetryClient _telemetryClient;

    public void Initialize(IConnectionMultiplexer connection)
        => connection.RegisterProfiler(this);

    public ProfilingSession GetSession() => _session.Value;

    public void FinishProfilingSession()
    {
        var session = _session.Value;
        if (session == null) return;
        _session.Value = null;

        foreach (var command in session.FinishProfiling())
        {
            var telemetry = new DependencyTelemetry
            {
                Type = "Redis",
                Name = command.Command.ToString(),
                Target = command.EndPoint?.ToString(),
                Duration = command.ElapsedTime,
                Success = command.RetransmissionOf is null,
                Timestamp = DateTimeOffset.UtcNow - command.ElapsedTime,
            };
            _telemetryClient.TrackDependency(telemetry);
        }
    }
}
```

**`RedisProfilingMiddleware.cs`** — Per-request profiling session lifecycle:

```csharp
public async Task InvokeAsync(HttpContext context)
{
    _initializer.BeginProfilingSession();
    try { await _next(context); }
    finally { _initializer.FinishProfilingSession(); }
}
```

### 6.3 DI Registration (`Startup.cs`)

```csharp
// Override the default NullRedisConnectionInitializer with AI-instrumented version
services.AddSingleton<ApplicationInsightsRedisInitializer>();
services.AddSingleton<IRedisConnectionInitializer>(sp =>
    sp.GetRequiredService<ApplicationInsightsRedisInitializer>());

// Middleware (early in pipeline, after auth observer)
app.UseMiddleware<RedisProfilingMiddleware>();
```

---

## 7. Design Decisions

1. **Why instrument in the shared library instead of only in the dataplane service?**
   The shared library owns `RedisConnectionManager` and all Redis access. The `IRedisConnectionInitializer` abstraction allows any consuming project (dataplane, frontend, future services) to opt into instrumentation without modifying the shared library. The `NullRedisConnectionInitializer` default ensures zero impact on projects that don't configure it.

2. **Why use `AsyncLocal<ProfilingSession>` instead of `HttpContext.Items`?**
   StackExchange.Redis's `IProfiler.GetSession()` has no access to `HttpContext`. `AsyncLocal` flows through `async`/`await` boundaries and provides per-request isolation without coupling to ASP.NET Core.

3. **Why use SE.Redis's built-in profiling API instead of wrapping `IDatabase`?**
   Wrapping `IDatabase` would require intercepting every method (StringGet, StringSet, ScriptEvaluate, etc.) and keeping up with API changes. The built-in `IProfiler`/`ProfilingSession` API captures all commands automatically, including retransmissions and multiplexed operations. It's the officially supported instrumentation surface.

4. **Why add an optional constructor parameter instead of requiring DI?**
   `RedisConnectionManager` is in a `netstandard2.0` library used by multiple projects. Making `IRedisConnectionInitializer` optional (`= null`) maintains backward compatibility — existing code that constructs `RedisConnectionManager` directly (including the frontend project and tests) continues to work without modification.

5. **Why `TryAddSingleton` for the default?**
   Using `TryAddSingleton` allows the host project to register its own `IRedisConnectionInitializer` before calling `AddRedis()`. The shared library only registers the no-op default if no implementation has been registered yet.

6. **Why instrument before changing the timeout?**
   The 20s `SyncTimeout` is a known workaround with a TODO comment. Reducing it without latency data risks breaking legitimate slow operations (large payload serialization). Instrumentation provides P50/P95/P99 baselines to make a data-driven decision.

---

## 8. Expected Impact

### Immediate (after deployment)

| Metric | Before | After |
|---|---|---|
| Redis dependency visibility | **None** | Full — every command tracked |
| Redis latency percentiles | **Unknown** | P50/P95/P99 available |
| Redis command breakdown | **Unknown** | Per-command type (GET, SET, EVAL) |
| Redis failure detection | Exception-only (after 20s timeout) | Per-command success/failure |
| Performance overhead | N/A | Minimal — profiling uses existing SE.Redis hooks |

### Enabled Future Actions (data-driven)

| Action | Blocked By | Unblocked By |
|---|---|---|
| Reduce SyncTimeout 20s → 5s | No P99 latency data | Instrumentation P99 shows safe threshold |
| Add `BacklogPolicy.FailFast` | Unknown impact on normal operations | Command success rate data |
| Add circuit breaker | No baseline failure rate | Dependency failure tracking |
| Payload chunking (TODO in code) | Unknown which operations are slow | Per-command duration data |

---

## 9. What Was NOT Fixed (Known Gaps)

1. **Frontend project** — Manually constructs `RedisConnectionManager` in `Startup.cs` (not via `AddRedis()` DI). Needs separate instrumentation wiring. Lower priority as the frontend is not the dataplane.

2. **No new tests** — The instrumentation is purely observational (emits telemetry, doesn't change behavior). Existing `RedisConnectionManagerTests` (3 tests) continue to pass. The optional parameter default ensures backward compatibility.

3. **Token refresh leak** — Deep trace analysis revealed `GetToken` calls continuing 2+ hours after request failure. This is a separate issue unrelated to Redis instrumentation.

4. **IMDS failure pattern** — 21s timeouts to 169.254.169.254 started roughly 14 hours before the Redis outage. Possible causal chain (IMDS → credential refresh → Redis auth) not yet investigated.

---

## 10. Verification

- **Build:** `dotnet build` succeeded with 0 errors, 0 new warnings
- **Tests:** 3/3 existing `RedisConnectionManagerTests` pass (backward-compatible optional parameter)
- **Profiler trace analysis:** Confirmed Redis is invisible in CPU sampling profiler (validated instrumentation need)
- **Code review:** Rubber-duck review identified key concerns (lazy connection creation, `netstandard2.0` nullable constraints, `RetransmissionOf` null check) — all addressed in implementation

---

## 11. Key Takeaway: Instrument Before You Optimize

The investigation followed a deliberate sequence:

1. **Error exploration** → Found the Redis outage
2. **Deep trace analysis** → Understood the failure mode (connection pool exhaustion + 20s timeout)
3. **Codebase analysis** → Found the 20s timeout workaround and missing resilience patterns
4. **Profiler analysis** → Confirmed Redis is invisible in existing observability
5. **Instrumentation** → Added dependency tracking (this fix)
6. **Future: Optimization** → Reduce timeout, add circuit breaker (data-driven, after baseline)

The temptation was to immediately reduce the 20s timeout to 5s (all operations are simple key-value ops that should complete in <5ms). But without P99 latency data, that's a blind change. The instrumentation-first approach ensures that when the timeout is eventually reduced, it's backed by production data — and if it causes issues, the dependency telemetry will show exactly which commands are affected.
