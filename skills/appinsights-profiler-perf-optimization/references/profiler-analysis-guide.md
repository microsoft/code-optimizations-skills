# Application Insights Profiler Analysis Guide

## Overview

This is a stub reference document for analyzing Application Insights Profiler traces and identifying performance optimization opportunities.

## Common Analysis Patterns

### High CPU Usage

- Look for hot paths in the flame graph
- Identify methods with high self-time
- Check for inefficient algorithms or loops

### High Latency

- Analyze call stacks for blocking operations
- Identify synchronous I/O or database calls
- Check for lock contention

### Low Throughput

- Examine thread pool exhaustion
- Look for async/await misuse
- Identify resource bottlenecks

## Reference Links

*Add relevant documentation links here*

## Examples

*Add code examples and optimization patterns here*
