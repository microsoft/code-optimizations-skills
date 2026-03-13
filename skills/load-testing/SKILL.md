---
name: load-testing
description: Guide for setting up and running load tests. Use this when asked to load test an application, stress test an endpoint, or evaluate system capacity.
---

# Load Testing

When asked to set up or run load tests, follow this process:

1. **Understand the test goals**: throughput targets, latency SLAs, concurrency levels, or capacity planning.
2. **Recommend appropriate tools** based on context:
   - k6 (Grafana) — scriptable, developer-friendly
   - Apache JMeter — GUI-based, protocol-rich
   - Azure Load Testing — cloud-native, integrated with Azure Monitor
   - Artillery — Node.js-based, YAML-driven
   - Locust — Python-based, distributed
3. **Help write the test script** for the chosen tool, targeting the identified endpoints.
4. **If Azure Monitor is configured**, use the Azure MCP server tools to:
   - Monitor resource health during the test
   - Query metrics (CPU, memory, response time) for the target resource
   - Check web test availability results
   - Analyze Log Analytics for errors during load
5. **Analyze results** and provide recommendations:
   - Identify the breaking point or saturation threshold
   - Highlight slow endpoints and error rates under load
   - Suggest scaling strategies (vertical, horizontal, caching, async)

## Tips

- Start with a baseline test at normal traffic levels before ramping up.
- Include think time and realistic user patterns in the load profile.
- Monitor both the application and its dependencies during the test.
