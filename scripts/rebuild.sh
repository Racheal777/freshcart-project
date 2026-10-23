#!/usr/bin/env bash
# Rebuilds the whole FreshCart platform on EKS, up to the end of Phase 2.
# Run from anywhere: ./scripts/rebuild.sh
set -euo pipefail

# Always run from the repo root, wherever the script is called from
cd "$(dirname "$0")/.."

REGION="eu-north-1"
CLUSTER="freshcart-eks-cluster"
ENVOY_GATEWAY_VERSION="1.9.2"
KUBE_PROMETHEUS_STACK_VERSION="92.11.0"

echo "==> 1. Building the cluster with Terraform (about 15 to 20 minutes)"
terraform -chdir=terraform/eks init -input=false
terraform -chdir=terraform/eks apply

echo "==> 2. Updating the kubectl address book"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"
kubectl config current-context

echo "==> 3. Waiting for all nodes to be Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "==> 4. Installing Envoy Gateway $ENVOY_GATEWAY_VERSION"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  -n envoy-gateway-system --create-namespace
kubectl wait --for=condition=Available deployment/envoy-gateway \
  -n envoy-gateway-system --timeout=300s

echo "==> 5. Installing Prometheus and Grafana ($KUBE_PROMETHEUS_STACK_VERSION)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  -n monitoring --create-namespace

echo "==> 6. Creating the GatewayClass (platform level)"
kubectl apply -f k8s/platform/gatewayclass.yaml

echo "==> 7. Creating the freshcart namespace"
kubectl create namespace freshcart --dry-run=client -o yaml | kubectl apply -f -

echo "==> 8. Creating the database secret"
# The URL is typed in, never saved in a file or in git
read -rsp "Paste the Neon database URL, then press Enter: " DB_URL
echo
kubectl create secret generic checkout-api-secrets \
  --from-literal=database-url="$DB_URL" \
  -n freshcart --dry-run=client -o yaml | kubectl apply -f -
unset DB_URL

echo "==> 9. Deploying FreshCart"
kubectl apply -k k8s/
kubectl rollout status deployment/checkout-api -n freshcart --timeout=180s
kubectl rollout status deployment/storefront -n freshcart --timeout=180s

echo "==> 10. Loading the golden signals dashboard into Grafana"
kubectl create configmap golden-signals-dashboard \
  -n monitoring \
  --from-file=monitoring/grafana/dashboards/golden-signals.json \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f -

echo "==> 11. Waiting for the Gateway address"
ADDRESS=""
for i in $(seq 1 30); do
  ADDRESS=$(kubectl get gateway freshcart-gateway -n freshcart \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  if [ -n "$ADDRESS" ]; then break; fi
  sleep 10
done

echo
echo "All done!"
echo "FreshCart:  http://$ADDRESS"
echo "Note: a new load balancer can take 2 minutes to appear in DNS."
echo
echo "Grafana password:"
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d
echo
echo "Open Grafana with:"
echo "  kubectl port-forward svc/monitoring-grafana -n monitoring 3002:80"