# Bug Fix: Geneva Audit Logging Exception — Missing CallerIdentityDescription

**Date:** June 9, 2026
**Service:** Backend compute worker service
**Severity:** Medium (audit compliance gap — compute operations not being audited across all prod regions)
**Files Changed:** `OpenTelemetryAuditLogger.cs`

---

## Executive Summary

The Geneva audit library was throwing `AuditLoggingException` ("Caller identity description cannot be empty if Type is 'Other'") **176 times per day across all 13 production regions** on the backend compute worker service during a background compute operation. The exception was caught and swallowed, so compute operations succeeded — but **audit records were silently dropped**, creating an audit compliance gap. The root cause was a missing parameter in a single method call; the fix was a one-line change.

---

## 1. How the Issue Was Found

### Working with constrained App Insights resources

The compute worker service's Application Insights resource is in a constrained subscription not accessible via `az` CLI. The error exploration skill's standard query scripts could not be used directly.

**Workaround:** The user ran the exceptions query directly in the Azure Portal and exported the results — 176 rows of tab-delimited exception data — which were pasted into the session for analysis.

### Parsing portal-exported data

The exported data used 4-space delimiters (not tabs) and contained 47 columns per row, with complex nested JSON in the `details` and `customDimensions` columns. A Python script was used to parse the data and extract key fields via regex patterns rather than delimiter splitting (which was unreliable due to spaces within field values).

### Key finding

All 176 exceptions were the **same problem ID** — a single exception type occurring uniformly across the entire production fleet:

| Field | Value |
|---|---|
| Exception type | `OpenTelemetry.Audit.Geneva.AuditLoggingException` |
| Message | "Caller identity description cannot be empty if Type is 'Other'" |
| Method | `OpenTelemetry.Audit.Geneva.AuditDiagnosticsExceptionHandler.EmitAndThrow` |
| Our code | `OpenTelemetryAuditLogger.LogAudit` (line 61) |
| Operation | (background compute operation) |
| Role | (compute worker role) |
| Count | 176 over 24 hours |
| Trend | Stable (88 first half → 88 second half) |
| Regions | All 13 production regions |
| Machines | 32 unique instances |

---

## 2. Root Cause Analysis

### The call chain

```
RequestHandler.AuditOperation()
  → new CallerIdentity(user: null, roleName: "<compute worker role>")
    → CallerIdentityType = Other, CallerIdentityEntry = "<compute worker role>"
    → CallerIdentityDescription = "Role name"  ← SET correctly in the model
  → OpenTelemetryAuditLogger.LogAudit(auditProperties)
    → auditRecord.AddCallerIdentity(type, entry)  ← MISSING description parameter
    → _auditLogger.LogAudit(auditRecord)
      → Geneva validates: Type == Other but description is empty → THROWS
```

### Why it happened

The failing operation is a background compute operation with no user context. When `user` is null, the `CallerIdentity` constructor falls back to `CallerIdentityType.Other` and correctly sets `CallerIdentityDescription = "Role name"`. However, `OpenTelemetryAuditLogger.LogAudit` on line 52 called `AddCallerIdentity` with only two parameters (type and entry), never passing the description.

The Geneva audit library (`OpenTelemetry.Audit.Geneva` v2.4.4) validates that a description is provided when the caller identity type is `Other` — a reasonable requirement, since `Other` is a catch-all type that needs context.

### Why it was silent

The exception was caught by a broad `catch (Exception ex)` on line 63 and logged via `_logger.TrackException(ex)`. The compute operation itself succeeded, but the audit record was never written.

---

## 3. The Fix

### One-line change (`OpenTelemetryAuditLogger.cs`, line 52)

```csharp
// Before — missing description parameter
auditRecord.AddCallerIdentity(
    auditProperties.CallerIdentity.CallerIdentityType,
    auditProperties.CallerIdentity.CallerIdentityEntry);

// After — passes the description through
auditRecord.AddCallerIdentity(
    auditProperties.CallerIdentity.CallerIdentityType,
    auditProperties.CallerIdentity.CallerIdentityEntry,
    auditProperties.CallerIdentity.CallerIdentityDescription);
```

### Safety verification

A key concern was whether passing `null` for the description when `CallerIdentityType` is `UPN` or `ObjectID` would cause a *new* exception. The Opus 4.7 review verified via reflection that:

- The Geneva library only validates the description when `Type == Other`
- `null` description is accepted for `UPN` and `ObjectID` types
- No other overload of `AddCallerIdentity` exists — the 3-arg version is the only one

---

## 4. Scope Verification

### All callers construct CallerIdentity safely

Seven callers across the codebase were verified — three compute worker services, one aggregation worker, one cleanup background job, and two paths in the frontend service. All paths go through the two `CallerIdentity` constructors, both of which set `CallerIdentityDescription = "Role name"` when `CallerIdentityType` is `Other`. The cleanup path explicitly passes `CallerIdentityType.Other` with a fixed role name; all other paths pass a possibly-null `user` plus a role name. No caller mutates `CallerIdentityDescription` after construction.

### Single choke point

`AddCallerIdentity` is called in exactly one place in the codebase — `OpenTelemetryAuditLogger.cs` line 52. This fix covers all audit logging for all services.

---

## 5. Expected Impact

| Metric | Before | After |
|---|---|---|
| AuditLoggingException count/day | 176 | 0 |
| Dropped audit records/day | 176 | 0 |
| Regions with missing audit | All 13 | 0 |
| Machines affected | 32 | 0 |
| Code changes | — | 1 line |

---

## 6. Verification

- **Build:** `dotnet build` succeeded with 0 warnings, 0 errors
- **Code Review:** 2 rounds of dual-model review (GPT 5.5 + Opus 4.7), all 4 reviews clear — no blocking issues
  - Round 1: Both models confirmed null description safe for UPN/ObjectID; both flagged (non-blocking) that `CallerIdentityDescription` has a public setter
  - Round 2: Both models returned "No issues found"

---

## 7. Design Decisions

1. **Why pass description unconditionally instead of only for `Other` type?**
   The 3-arg `AddCallerIdentity` overload accepts null description for non-Other types. Passing it unconditionally is simpler, avoids branching, and ensures any future `CallerIdentityType` values also get their description passed through.

2. **Why not also make `CallerIdentityDescription` a private setter?**
   Both reviewers noted this as a non-blocking improvement. The public setter creates a theoretical regression risk (someone could null it out after construction). However, no current code does this, and changing the setter accessibility is a separate concern from the immediate audit fix.

---

## 8. Methodology Notes

### Error exploration on constrained resources

This case demonstrates that the error exploration workflow can operate on **portal-exported data** when the App Insights resource is not accessible via CLI. The key adaptation:

1. User ran the KQL query in the Azure Portal
2. Exported results were pasted as text (portal uses 4-space delimited format)
3. Python scripts parsed the data using regex extraction for key fields
4. Analysis proceeded identically to the CLI-driven workflow

**Limitation:** Only exceptions were analyzed. The failed requests and failed dependencies queries could not be run, so cross-category correlation was not possible. For a constrained resource, the user would need to export those query results separately.

### Multi-model review efficiency

The 2-round, dual-model review completed with all clear rounds on the first attempt — appropriate for a one-line fix with a well-understood root cause. The review validated two key safety properties:
1. No regression for existing UPN/ObjectID paths (null description is safe)
2. No other code paths with the same bug (single call site, all constructors correct)
