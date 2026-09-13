#!/usr/bin/env bash

#
# Kubernetes / MicroK8s Cluster Health Check
#
# Performs a basic health assessment of a MicroK8s cluster.
# Designed for lab and demonstration environments.
#

set -u

KUBECTL="microk8s kubectl"

echo
echo "============================================================"
echo " Kubernetes Cluster Health Check"
echo "============================================================"
echo
echo "Run time: $(date)"
echo

# ------------------------------------------------------------
# MicroK8s status
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " MicroK8s Status"
echo "------------------------------------------------------------"

if command -v microk8s >/dev/null 2>&1; then
    microk8s status --wait-ready
else
    echo "ERROR: MicroK8s command not found."
    exit 1
fi

echo


# ------------------------------------------------------------
# Cluster nodes
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Cluster Nodes"
echo "------------------------------------------------------------"

$KUBECTL get nodes -o wide

echo


# ------------------------------------------------------------
# Node readiness
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Node Readiness Check"
echo "------------------------------------------------------------"

NOT_READY=$(
    $KUBECTL get nodes \
    --no-headers 2>/dev/null |
    awk '$2 != "Ready" {print $1}'
)

if [ -z "$NOT_READY" ]; then
    echo "PASS: All Kubernetes nodes are Ready."
else
    echo "WARNING: The following nodes are not Ready:"
    echo "$NOT_READY"
fi

echo


# ------------------------------------------------------------
# Pods
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Pods"
echo "------------------------------------------------------------"

$KUBECTL get pods -A -o wide

echo


# ------------------------------------------------------------
# Unhealthy pods
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Pod Health Check"
echo "------------------------------------------------------------"

UNHEALTHY_PODS=$(
    $KUBECTL get pods -A \
    --no-headers 2>/dev/null |
    awk '
    $4 != "Running" &&
    $4 != "Completed" {
        print $1 "/" $2 " - " $4
    }'
)

if [ -z "$UNHEALTHY_PODS" ]; then
    echo "PASS: No unhealthy pods detected."
else
    echo "WARNING: Pods requiring investigation:"
    echo "$UNHEALTHY_PODS"
fi

echo


# ------------------------------------------------------------
# Services
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Kubernetes Services"
echo "------------------------------------------------------------"

$KUBECTL get services -A

echo


# ------------------------------------------------------------
# Endpoints
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Service Endpoints"
echo "------------------------------------------------------------"

$KUBECTL get endpoints -A

echo


# ------------------------------------------------------------
# Persistent Volume Claims
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Persistent Volume Claims"
echo "------------------------------------------------------------"

$KUBECTL get pvc -A 2>/dev/null || true

echo


# ------------------------------------------------------------
# Recent cluster events
# ------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Recent Cluster Events"
echo "------------------------------------------------------------"

$KUBECTL get events -A \
    --sort-by='.lastTimestamp' 2>/dev/null |
    tail -20

echo


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo "============================================================"
echo " Health Check Complete"
echo "============================================================"

if [ -z "$NOT_READY" ] && [ -z "$UNHEALTHY_PODS" ]; then
    echo "Overall status: PASS"
else
    echo "Overall status: ATTENTION REQUIRED"
fi

echo
