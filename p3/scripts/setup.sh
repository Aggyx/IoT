#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot"
APP_NAME="playground"
CONFS_DIR="$(cd "$(dirname "$0")/../confs" && pwd)"

#Check if docker is install and usable by the user
if ! docker info >/dev/null 2>&1; then
    echo "Docker not accessibble, run the installation script (install.sh)"
    exit 1
fi

# delete a possible older version of the cluster and create a new one 
k3d cluster delete "$CLUSTER_NAME" >/dev/null 2>&1 || true
k3d cluster create "$CLUSTER_NAME" --port "8888:8888@loadbalancer"


# namespace: isolate group of resources inside the cluster
kubectl create namespace argocd
kubectl create namespace dev


#command from argoCD documentation (quick start)
kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


# wait for argoCD to deploy all it's components, be running and healthy, 
# there are two types of "workload controllers" : deployments (for the interchangeable copies), and statefulSet (for fixed identity),
# two different ways of checking if they are good to go.
kubectl wait deployment --all -n argocd --for=condition=Available --timeout=600s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=600s


kubectl apply -f "$CONFS_DIR/application.yaml"


# wait for the app to be created, and then to be available (running and healthy), 
# we cannot put only the second one because the object does not exists yet
kubectl wait deployment/"$APP_NAME" -n dev --for=create --timeout=300s
kubectl wait deployment/"$APP_NAME" -n dev --for=condition=Available --timeout=300s


# get password fot the web interface, and decode it in base 64
until kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; do
    sleep 2
done
PASSWORD="$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"



echo "Application : curl http://localhost:8888/"
echo "Argo CD     : user admin / password $PASSWORD"
echo "Web interface   : run scripts/argocd.sh then open https://localhost:8080"