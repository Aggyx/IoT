#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot"
KUBE_CONTEXT="k3d-$CLUSTER_NAME"
CONFS_DIR="$(cd "$(dirname "$0")/../confs" && pwd)"

if ! docker info >/dev/null 2>&1; then
    echo "Docker inaccessible : lancez install.sh et verifiez vos droits." >&2
    exit 1
fi

clusters="$(k3d cluster list --no-headers)"
if ! awk -v name="$CLUSTER_NAME" '$1 == name { found=1 } END { exit !found }' <<< "$clusters"; then
    k3d cluster create "$CLUSTER_NAME" --servers 1 --agents 2 --port "8888:8888@loadbalancer"
fi

kube() {
    kubectl --context "$KUBE_CONTEXT" "$@"
}

for namespace in gitlab argocd dev; do
    kube create namespace "$namespace" --dry-run=client -o yaml | kube apply -f -
done

kube apply -f "$CONFS_DIR/gitlab.yaml"
kube -n gitlab rollout status deployment/gitlab --timeout=20m

# Recharge le nouvel import DNS sans attendre la propagation du volume.
kube -n kube-system rollout restart deployment/coredns
kube -n kube-system rollout status deployment/coredns --timeout=120s

argo_server="$(kube -n argocd get deployment argocd-server --ignore-not-found -o name)"
if [[ -z "$argo_server" ]]; then
    kube -n argocd apply --server-side --force-conflicts \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi
kube -n argocd wait deployment --all --for=condition=Available --timeout=600s
kube -n argocd rollout status statefulset/argocd-application-controller --timeout=600s

echo "GitLab : lancez scripts/gitlab.sh, puis publiez le depot avant d'appliquer application.yaml."
echo "Argo CD : lancez scripts/argocd.sh."
