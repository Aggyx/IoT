#!/bin/bash
set -euo pipefail

echo "Argo CD : https://localhost:8080"
exec kubectl --context k3d-iot -n argocd port-forward svc/argocd-server 8080:443
