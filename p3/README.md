# Part 3 - K3d and Argo CD

This part deploys a small web application on a local Kubernetes cluster and keeps
it in sync with a Git repository, following the **GitOps** approach: the Git
repository is the single source of truth, and Argo CD makes the cluster match it.

## Concepts

| Tool | Role |
| --- | --- |
| **Docker** | Runs containers. K3d uses it to run the Kubernetes nodes themselves as containers. |
| **K3s** | A lightweight Kubernetes distribution, used in parts 1 and 2 inside Vagrant VMs. |
| **K3d** | Runs K3s inside Docker containers. No VM is needed, so a cluster starts in seconds. |
| **kubectl** | The command-line client used to talk to the Kubernetes API. |
| **Argo CD** | A GitOps controller. It watches a Git repository and applies its manifests to the cluster. |

With `automated` sync enabled, Argo CD:

- **syncs** the cluster every time a new commit is pushed to the repository,
- **prunes** resources that were removed from Git,
- **self-heals** manual changes: if someone edits or deletes a resource with
  `kubectl`, Argo CD restores the state described in Git.

## Architecture

```
  GitHub (public)                      K3d cluster "iot" (1 server, 2 agents)
 +------------------------+          +------------------------------------------+
 | malochato/iot-malde-ch |          |  namespace: argocd                       |
 |   manifests/           |  watch   |   +----------------------------------+   |
 |     deployment.yaml    | <------- |   | Argo CD                          |   |
 |     service.yaml       |          |   | Application "playground"         |   |
 +------------------------+          |   +----------------+-----------------+   |
                                     |                    | apply                |
                                     |                    v                      |
                                     |  namespace: dev                           |
                                     |   +----------------------------------+   |
                                     |   | Deployment "playground" (2 pods) |   |
                                     |   | Service "playground" :8888       |   |
                                     |   +----------------+-----------------+   |
                                     +--------------------|---------------------+
                                                          | k3d load balancer
                                                          v
                                                localhost:8888 (host)
```

## Repository layout

```
p3/
  app/
    deployment.yaml    wil42/playground image, 2 replicas, port 8888
    service.yaml       LoadBalancer service on port 8888
  confs/
    application.yaml   Argo CD Application pointing to the GitHub repository
  scripts/
    install.sh         Installs Docker, kubectl and k3d
    setup.sh           Creates the cluster, installs Argo CD, deploys the app
    argocd.sh          Opens the Argo CD web interface (port-forward)
    clean.sh           Deletes the cluster
```

Argo CD does not deploy from this folder. It deploys from the public repository
[malochato/iot-malde-ch](https://github.com/malochato/iot-malde-ch), which holds
the same files in a `manifests/` folder:

```
iot-malde-ch/
  manifests/
    deployment.yaml
    service.yaml
```

`app/` is a reference copy of the initial state pushed to that repository
(`wil42/playground:v1`). Once the image tag or the replicas are changed on
GitHub, the cluster follows GitHub, not this copy.

## Usage

Run the scripts from the `p3/` folder.

### 1. Install the tools

```bash
./scripts/install.sh
```

Each tool is installed only if it is missing. The script adds the current user to
the `docker` group, so log out and log back in (or run `newgrp docker`) before
the next step.

### 2. Create the cluster and deploy

```bash
./scripts/setup.sh
```

The script:

1. deletes any previous `iot` cluster and creates a new one with 1 server and
   2 agents, mapping port `8888` of the host to the cluster load balancer,
2. creates the `argocd` and `dev` namespaces,
3. installs Argo CD from its official manifest and waits until it is healthy,
4. applies [confs/application.yaml](confs/application.yaml),
5. waits until Argo CD has deployed the application in `dev`,
6. prints the Argo CD admin password.

### 3. Access the application and Argo CD

| Service | URL | Credentials |
| --- | --- | --- |
| Application | http://localhost:8888 | - |
| Argo CD | https://localhost:8080 | `admin` / printed by `setup.sh` |

```bash
curl http://localhost:8888/
./scripts/argocd.sh   # keep it running, then open https://localhost:8080
```

`argocd.sh` forwards port `8080` of the host to the Argo CD server. It listens on
`0.0.0.0`, so the interface is also reachable from outside the VM. The browser
shows a warning because Argo CD uses a self-signed certificate.

### 4. Clean up

```bash
./scripts/clean.sh
```

## Useful kubectl commands

```bash
# Cluster and namespaces
kubectl get nodes
kubectl get ns

# Application
kubectl get all -n dev
kubectl describe deployment playground -n dev
kubectl get pods -n dev -o jsonpath='{.items[*].spec.containers[*].image}'

# Argo CD
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get application playground -n argocd \
  -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}{"\n"}'

# Argo CD admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
```
