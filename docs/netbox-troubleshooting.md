# NetBox on MicroK8s - Troubleshooting Notes

This document captures a sanitized troubleshooting workflow for a NetBox deployment running on MicroK8s.

The environment uses Kubernetes, Helm, PostgreSQL, Valkey, and NetBox application pods.

The purpose of this document is to demonstrate a practical troubleshooting methodology for containerized infrastructure and Kubernetes networking.

## Scenario

A NetBox deployment was created using Helm, but the application pod did not initially become healthy.

Symptoms included:

- NetBox pod created but not becoming Ready
- Startup probe failures
- Connection refused errors
- NetBox worker waiting during initialization
- PostgreSQL and Valkey pods running
- Kubernetes service created but the application not responding correctly

Example sanitized error:

```text
Startup probe failed:
connection refused to <pod-ip>:8080/login
```

This required troubleshooting the path between the Kubernetes service, pod, container, application, and supporting services.

## Initial Checks

The first step was to confirm the overall Kubernetes cluster state.

```bash
microk8s status
microk8s kubectl get nodes
microk8s kubectl get pods -A -o wide
```

Things to verify:

- All Kubernetes nodes are Ready
- PostgreSQL is Running
- Valkey is Running
- NetBox pod is scheduled
- NetBox worker state
- Pod restart counts
- Pod IP addresses
- Which Kubernetes node is hosting each workload

Example:

```text
NAME       STATUS   ROLES    AGE   VERSION
k8s-node1  Ready    <none>   10d   v1.x
k8s-node2  Ready    <none>   10d   v1.x
```

## Inspect the NetBox Pod

The next step is to inspect the affected NetBox pod.

```bash
microk8s kubectl describe pod <netbox-pod-name>
```

Important sections include:

- Container state
- Init container state
- Startup probes
- Readiness probes
- Environment variables
- Mounted volumes
- Restart counts
- Kubernetes events

The Events section is particularly useful because Kubernetes records probe failures, scheduling problems, volume errors, and container restart activity there.

## Review Application Logs

Application logs help determine whether the problem exists inside NetBox itself or at the Kubernetes layer.

```bash
microk8s kubectl logs <netbox-pod-name>
```

If the pod contains multiple containers, first identify them:

```bash
microk8s kubectl get pod <netbox-pod-name> \
  -o jsonpath='{.spec.containers[*].name}'
```

Then inspect a specific container:

```bash
microk8s kubectl logs <netbox-pod-name> \
  -c <container-name>
```

Useful errors to look for include:

- Database connection failures
- Cache connection failures
- Python exceptions
- Configuration errors
- Permission errors
- Application startup failures

## Check Kubernetes Services

The NetBox service should be verified independently from the application pod.

List services:

```bash
microk8s kubectl get services -A
```

Example sanitized output:

```text
NAME      TYPE        CLUSTER-IP       PORT(S)
netbox    ClusterIP   10.152.x.x       80/TCP
```

A `ClusterIP` service provides an internal Kubernetes virtual IP.

The existence of the service does not necessarily mean that NetBox itself is healthy.

## Check Service Endpoints

A Kubernetes service can exist even when it has no functioning backend pods.

Check all endpoints:

```bash
microk8s kubectl get endpoints -A
```

Or check NetBox specifically:

```bash
microk8s kubectl get endpoints netbox
```

If no endpoints are present, investigate:

- Pod labels
- Service selectors
- Pod readiness
- Application listening port
- Container health

The service selector must match the appropriate pod labels before Kubernetes can associate the service with the application pods.

## Verify Service Selectors and Pod Labels

Display the NetBox service:

```bash
microk8s kubectl describe service netbox
```

Display pod labels:

```bash
microk8s kubectl get pods --show-labels
```

The service selectors should correspond to labels assigned to the NetBox pods.

A selector mismatch can result in a valid Kubernetes service that has no backend endpoints.

## Verify the Application Port

The startup probe failure indicated that Kubernetes was attempting to reach the NetBox application but the connection was refused.

The next step is to determine whether the application is actually listening on the expected port.

Enter the pod:

```bash
microk8s kubectl exec -it <netbox-pod-name> -- /bin/sh
```

Then inspect listening TCP ports if the required utilities are available:

```bash
ss -lnt
```

or:

```bash
netstat -lnt
```

The application must listen on the port expected by the Kubernetes service and health probes.

A connection refused error can indicate:

- Application has not finished starting
- Application process crashed
- Incorrect probe port
- Incorrect container port
- Dependency preventing application startup

## Startup, Readiness, and Liveness Probes

Kubernetes probes serve different purposes.

### Startup Probe

Determines whether the application has successfully started.

A failing startup probe can prevent Kubernetes from considering the container healthy during initialization.

### Readiness Probe

Determines whether the application is ready to receive traffic.

A pod that is not Ready may be removed from service endpoints.

### Liveness Probe

Determines whether the application is still functioning.

Repeated liveness failures can cause Kubernetes to restart the container.

Probe configuration can be inspected using:

```bash
microk8s kubectl describe pod <netbox-pod-name>
```

Important values include:

- Path
- Port
- Initial delay
- Timeout
- Period
- Failure threshold

## Test Connectivity from Inside the Cluster

Testing from inside Kubernetes helps distinguish an application problem from external network access issues.

A temporary troubleshooting pod can be created:

```bash
microk8s kubectl run test-shell \
  --rm -it \
  --image=busybox \
  -- /bin/sh
```

From the troubleshooting pod, test Kubernetes DNS:

```bash
nslookup netbox
```

Then test the NetBox service:

```bash
wget -O- http://netbox
```

This helps determine whether the problem involves:

- Application startup
- Kubernetes DNS
- Service configuration
- Endpoint selection
- Pod networking
- Application port configuration

## Check Kubernetes DNS

Service discovery depends on Kubernetes DNS.

Check the DNS components:

```bash
microk8s kubectl get pods -n kube-system
```

Applications should normally be able to resolve Kubernetes service names from inside the cluster.

DNS problems can cause applications to fail when attempting to reach supporting services such as PostgreSQL or Valkey.

## Check PostgreSQL

NetBox requires PostgreSQL.

Verify the PostgreSQL pod:

```bash
microk8s kubectl get pods -A | grep postgres
```

Inspect it if necessary:

```bash
microk8s kubectl describe pod <postgresql-pod-name>
```

Check its logs:

```bash
microk8s kubectl logs <postgresql-pod-name>
```

A NetBox application container may fail or remain unavailable if the database is not ready or cannot be reached.

## Check Valkey

NetBox also depends on Valkey for caching and task processing.

Verify Valkey:

```bash
microk8s kubectl get pods -A | grep valkey
```

Check logs if required:

```bash
microk8s kubectl logs <valkey-pod-name>
```

Depending on the Helm deployment, multiple Valkey pods may exist.

Verify that the required primary and replica components are healthy.

## Worker Pod Stuck During Initialization

Another symptom observed during deployment was a NetBox worker remaining in an initialization state.

Example:

```text
Init:0/1
```

Inspect the worker:

```bash
microk8s kubectl describe pod <worker-pod-name>
```

Identify its init containers:

```bash
microk8s kubectl get pod <worker-pod-name> \
  -o jsonpath='{.spec.initContainers[*].name}'
```

Then inspect the init container logs:

```bash
microk8s kubectl logs <worker-pod-name> \
  -c <init-container-name>
```

An init container may intentionally wait for another service before allowing the main application container to start.

Possible dependencies include:

- PostgreSQL
- Valkey
- Database migrations
- NetBox application availability
- DNS resolution

## Check Persistent Storage

If the deployment uses persistent storage, verify Persistent Volume Claims:

```bash
microk8s kubectl get pvc -A
```

Then inspect any PVC that is not Bound:

```bash
microk8s kubectl describe pvc <pvc-name>
```

Storage problems can prevent databases or application components from starting.

## Check Recent Kubernetes Events

Kubernetes events provide a useful cluster-wide troubleshooting view.

```bash
microk8s kubectl get events -A \
  --sort-by='.lastTimestamp'
```

Look for:

- Startup probe failures
- Readiness probe failures
- Liveness probe failures
- Image pull failures
- Volume mount errors
- Scheduling failures
- Container back-off events
- DNS problems

Events should be correlated with pod status and application logs rather than treated as the only source of troubleshooting information.

## Helm Validation

Because NetBox was deployed using Helm, the Helm deployment should also be checked.

List releases:

```bash
microk8s helm3 list -A
```

Inspect the NetBox release:

```bash
microk8s helm3 status <release-name>
```

Review configured values:

```bash
microk8s helm3 get values <release-name>
```

This helps identify differences between expected application configuration and the resources actually deployed to Kubernetes.

## Kubernetes Networking Perspective

From a network engineering perspective, troubleshooting the application requires validating several different layers.

```text
User / Client
      |
      v
Kubernetes Service
      |
      v
Service Endpoint
      |
      v
Pod IP
      |
      v
Container Port
      |
      v
NetBox Application
      |
      +----------+
      |          |
      v          v
 PostgreSQL    Valkey
```

A failure at any layer can result in an application that appears unavailable.

Traditional network connectivity is therefore only one part of Kubernetes application troubleshooting.

## Troubleshooting Workflow

The general troubleshooting sequence used in this lab is:

1. Confirm MicroK8s health
2. Confirm Kubernetes node health
3. Review pod state
4. Identify failed or waiting containers
5. Describe the affected pod
6. Review container and init-container logs
7. Validate Kubernetes services
8. Validate service selectors and endpoints
9. Verify application listening ports
10. Test Kubernetes DNS
11. Test connectivity from inside the cluster
12. Validate PostgreSQL
13. Validate Valkey
14. Check persistent storage
15. Review Kubernetes events
16. Review Helm deployment status

This approach helps isolate the problem rather than assuming every application failure is a network problem.

## Key Lessons

Several important Kubernetes troubleshooting principles are demonstrated by this lab.

### A Running Pod Does Not Guarantee a Working Application

Container state, readiness, application health, and service reachability must all be considered.

### A Service Does Not Guarantee Connectivity

A Kubernetes Service can exist without usable endpoints.

Always validate:

```bash
microk8s kubectl get services
microk8s kubectl get endpoints
```

### Connection Refused Is Different From a Timeout

A connection refusal often indicates that the destination was reachable but nothing was accepting the connection on the expected port.

A timeout may instead indicate routing, filtering, CNI, policy, or connectivity problems.

### Application Dependencies Matter

NetBox is not a standalone container.

Its health depends on supporting components such as PostgreSQL and Valkey.

### Kubernetes Requires Layered Troubleshooting

The complete path should be validated:

```text
Service
   |
Endpoint
   |
Pod
   |
Container
   |
Application
   |
Dependencies
```

Each layer should be tested independently.

## Future Lab Work

Future enhancements to the NetBox Kubernetes lab include:

- NetBox REST API testing
- Integration with the network automation inventory
- Persistent storage testing
- Kubernetes Ingress
- TLS
- NetworkPolicy testing
- Application monitoring
- Prometheus and Grafana
- Automated NetBox health checks
- Automated network device synchronization

## Security and Sanitization

This document is based on hands-on lab troubleshooting.

Hostnames, IP addresses, credentials, tokens, certificates, and other potentially sensitive information have been removed or sanitized.

No employer, customer, or production configuration data is included.
