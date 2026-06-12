---
name: Test performance optimization skills
description: Test scenarios for validating the perf-optimization, get-profile-hotpath, and download-profile-trace skills.
---

# Test Scenarios

## 1. End-to-end performance analysis

**Prompt**: "Help me investigate why my API is slow. My Application Insights resource ID is /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{name}"

**Expected flow**:
1. Skill resolves app ID from resource ID
2. Writes investigation-notes.md
3. Fetches Code Optimization recommendations
4. Gets recommendation detail for top issues
5. Finds relevant profiler traces
6. Fetches hot path for the most impactful trace
7. Correlates hot path with recommendations
8. Suggests code changes

## 2. Hot path retrieval

**Prompt**: "Get the profiler hot path for my App Insights resource"

**Expected flow**:
1. Checks investigation-notes.md for existing app ID
2. Finds profiler traces if no trace location ID provided
3. Presents traces for user selection
4. Fetches metadata, triggers analysis, polls, fetches root tree
5. Expands child nodes along hot path
6. Presents formatted call tree with percentages

## 3. Trace download

**Prompt**: "Download a profiler trace from my App Insights"

**Expected flow**:
1. Checks investigation-notes.md
2. Lists available traces with timestamps, roles, formats
3. User selects a trace
4. Downloads via artifact ID or trace location ID
5. Reports file location, size, and how to open

## 4. Edge cases

### Empty Code Optimization recommendations
- Trigger with a time range that has no profiler data
- Expected: agent widens time range or falls back to manual trace analysis

### Empty AI recommendation
- Expected: agent proceeds with profiler hot path and source code analysis

### Null artifact ID in trace listing
- Expected: agent resolves via ServiceProfilerSample customEvents query