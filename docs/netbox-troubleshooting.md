# NetBox on MicroK8s - Troubleshooting Notes

This document captures a sanitized troubleshooting workflow for a NetBox deployment running on MicroK8s.

The environment uses Kubernetes, Helm, PostgreSQL, Valkey, and NetBox application pods.

## Scenario

A NetBox deployment was created successfully, but the application pod failed its startup probe.

Symptoms included:

- NetBox pod created but not becoming Ready
- Startup probe failure
- Connection refused errors
- Worker pod waiting during initialization
- PostgreSQL and Valkey pods running
- Kubernetes service present but application not responding correctly

Example sanitized error:

```text
Startup probe failed:
connection refused to <pod-ip>:8080/login
