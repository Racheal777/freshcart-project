#!/usr/bin/env bash
# Shuts down the whole FreshCart platform on EKS, to stop AWS charges.
# Run from anywhere: ./scripts/teardown.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Current cluster:"
kubectl config current-context
read -rp "Destroy this cluster? Type yes to continue: " ANSWER
if [ "$ANSWER" != "yes" ]; then
  echo "Stopped. Nothing was deleted."
  exit 0
fi

echo "==> 1. Removing FreshCart, including the Gateway"
echo "    This makes AWS delete the load balancer, so it can't block the destroy"
kubectl delete -k k8s/ --ignore-not-found

echo "==> 2. Waiting 60 seconds for AWS to remove the load balancer"
sleep 60

echo "==> 3. Destroying the cluster with Terraform (about 10 to 15 minutes)"
terraform -chdir=terraform/eks destroy

echo "Done. The cluster is gone, and AWS charges for it have stopped."