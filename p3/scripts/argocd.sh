#!/bin/bash
set -euo pipefail

# expose the Argo CD UI on port 8080
# --address 0.0.0.0 makes it reachable from outside the VM, not only from inside

PASSWORD="$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"

echo "Argo CD : https://localhost:8080 (admin / $PASSWORD)"

kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
