# Error Prioritization Guide

How to rank and prioritize errors discovered through the error exploration queries for maximum impact.

## Prioritization Framework

Not all errors are equally important. Use the following factors to rank errors and recommend which ones to fix first.

### 1. Frequency (count)

The most basic signal — how many times did this error occur?

- **High frequency** (hundreds or thousands of occurrences) → likely a systemic issue affecting many users or operations
- **Low frequency** (single digits) → may be an edge case, but check other factors before dismissing

> Frequency alone is not enough. A high-frequency 404 on a deprecated endpoint matters less than a low-frequency 500 on a critical payment endpoint.

### 2. Trend direction

Is the error rate increasing, decreasing, or stable?

| Trend | Interpretation | Priority impact |
|-------|---------------|-----------------|
| **Increasing** | Active regression or growing problem — getting worse over time | **Highest priority** — likely needs immediate attention |
| **Stable** | Known, ongoing issue — the error rate is consistent | **Medium priority** — important but not urgent |
| **Decreasing** | Issue is resolving itself (deployment fix, transient issue) | **Lower priority** — may not need action |

> An increasing trend on even a low-frequency error is a red flag — it may be the early stage of a larger problem.

### 3. Blast radius

How many different operations, services, or users are affected?

- **Failed dependencies**: Check `AffectedOperations` — a dependency failure that affects 20 different operations is more impactful than one that affects 2
- **Exceptions**: Check if the same exception type appears across multiple `cloud_RoleName` values — cross-service exceptions suggest a shared component issue
- **Failed requests**: Check if multiple operation names share the same failure pattern

### 4. Severity class

Not all HTTP status codes and exception types are equal:

| Category | Examples | Priority |
|----------|----------|----------|
| **Server errors (5xx)** | 500, 502, 503 | **High** — the application is broken |
| **Timeouts** | 504, `TaskCanceledException`, `TimeoutException` | **High** — reliability issue, often cascading |
| **Data errors** | `NullReferenceException`, `InvalidOperationException` | **Medium-High** — logic bugs |
| **Client errors (4xx)** | 400, 401, 403, 404 | **Varies** — 401/403 may be auth issues; 404 may be benign |
| **Transient errors** | 429, `SocketException` | **Medium** — may need retry logic |

### 5. Recency

When was the error last seen?

- **Last seen within the hour** → actively occurring right now
- **Last seen today** → recent and relevant
- **Last seen days ago** → may already be resolved

## Composite Priority Score

When presenting recommendations, combine these factors into a narrative priority assessment:

### 🔴 Fix immediately
- 5xx errors with **increasing** trend
- Any error with high frequency **and** increasing trend
- Timeout patterns affecting multiple operations

### 🟡 Fix soon
- High-frequency errors with **stable** trend
- 5xx errors with stable or decreasing trend (still a bug, just not getting worse)
- Dependency failures with high blast radius

### 🟢 Monitor / investigate later
- Low-frequency errors with **decreasing** trend
- 4xx errors that may be expected (404 on optional resources, 401 before auth)
- Errors only seen in non-production roles

## Presenting Recommendations

When recommending issues to fix, structure the recommendation as:

1. **State the error** — What is it? (exception type, failed operation, dependency target)
2. **Quantify the impact** — How often? How many operations affected? What's the trend?
3. **Explain why it matters** — Is it causing user-facing failures? Is it getting worse?
4. **Suggest next steps** — What should the user investigate? Which skill can help dig deeper?

### Example recommendation

> **🔴 #1: `System.TimeoutException` in `OrderService.ProcessPayment`**
> - 342 occurrences in the last 24h, **increasing** (87 → 255 between first and second halves)
> - Affects the `POST /api/orders` endpoint — all 342 exceptions correlate with HTTP 500 responses
> - The downstream payment gateway (`payments.example.com`) shows 298 failed dependency calls with P95 latency of 31,200ms
> - **Recommendation**: Investigate the payment gateway dependency. Consider adding a circuit breaker pattern. Use the `deep-analysis` skill with a specific operation ID to trace the full request flow.

## Cross-referencing Error Categories

The most actionable insights come from correlating across error categories:

| Pattern | What it means |
|---------|--------------|
| Exception + failed request on same operation | The exception is the root cause of the request failure |
| Failed dependency + exception in caller | Dependency failure is causing the exception — fix the dependency or add error handling |
| Failed dependency + failed request on different operations | Cascading failure — the dependency is a shared bottleneck |
| Exception without failed request | The exception is caught/handled but may still indicate a problem (performance cost, data quality) |
| Failed request without exception | May be an infrastructure-level failure (load balancer, routing) or intentional error response |
