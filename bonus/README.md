# Bonus - Local GitLab

This bonus extends part 3: the application manifests are no longer hosted on
GitHub but on a **GitLab instance running inside the cluster**. Argo CD keeps the
same role and syncs the application into the `dev` namespace from this local
GitLab, so the whole GitOps pipeline runs on the machine with no external Git
service.

## Concepts

| Tool | Role |
| --- | --- |
| **K3d** | Runs a K3s Kubernetes cluster inside Docker containers. |
| **GitLab CE** | Self-hosted Git server. It stores the application manifests in a private project. |
| **Argo CD** | GitOps controller. It watches the GitLab project and applies its manifests to the cluster. |
| **CoreDNS** | DNS server of the cluster. It lets pods resolve the GitLab hostname. |
| **local-path** | Default K3s storage class. It keeps GitLab data on a node's disk. |

### One hostname for everyone

GitLab must be reachable with the same URL, `http://gitlab.iot.test:8081`, from
two places:

- **from the host** (browser, `git push`): `/etc/hosts` maps `gitlab.iot.test`
  to `127.0.0.1`, and a `kubectl port-forward` sends port `8081` to the GitLab
  service;
- **from inside the cluster** (Argo CD): a CoreDNS rule rewrites
  `gitlab.iot.test` to `gitlab.gitlab.svc.cluster.local`, the internal name of
  the GitLab service. Argo CD therefore does not depend on the port-forward.

K3s CoreDNS loads extra rules from the `coredns-custom` ConfigMap in
`kube-system`; the rule is defined at the end of
[confs/gitlab.yaml](confs/gitlab.yaml).

## Architecture

```
  Host machine                          K3d cluster "iot" (1 server, 2 agents)
 +---------------------------+        +--------------------------------------------+
 | /etc/hosts:               |        |  namespace: gitlab                         |
 |  127.0.0.1 gitlab.iot.test|        |   +--------------------------------------+ |
 |                           |  port- |   | GitLab CE  (Deployment + 20Gi PVC)   | |
 | browser / git push  ------+------->|   | Service "gitlab" :8081               | |
 |   gitlab.iot.test:8081    | forward|   | project root/iot-malde-ch (private)  | |
 |                           |        |   +------------------^-------------------+ |
 |                           |        |                      | git fetch           |
 |                           |        |  namespace: kube-system  (CoreDNS rewrite)  |
 |                           |        |   gitlab.iot.test -> gitlab.gitlab.svc     |
 |                           |        |                      |                     |
 |                           |  port- |  namespace: argocd   |                     |
 | browser  -----------------+------->|   +------------------+-------------------+ |
 |   localhost:8080          | forward|   | Argo CD, Application "playground"    | |
 |                           |        |   +------------------+-------------------+ |
 |                           |        |                      | apply               |
 |                           |        |  namespace: dev      v                     |
 |                           |  k3d   |   +--------------------------------------+ |
 | curl localhost:8888  -----+------->|   | Deployment + Service "playground"    | |
 |                           |   LB   |   +--------------------------------------+ |
 +---------------------------+        +--------------------------------------------+
```

## Repository layout

```
bonus/
  confs/
    gitlab.yaml        GitLab PVC, Deployment, Service and CoreDNS rewrite rule
    application.yaml   Argo CD Application pointing to the local GitLab project
  iot-lab/
    deployment.yaml    wil42/playground image, 2 replicas, port 8888
    service.yaml       LoadBalancer service on port 8888
  scripts/
    install.sh         Installs Docker, kubectl, k3d, git and jq
    setup.sh           Deploys GitLab, pushes the manifests, installs Argo CD
    clean.sh           Deletes the cluster
```

`iot-lab/` holds the application manifests. `setup.sh` pushes them to the
`manifests/` folder of the GitLab project, which is the path Argo CD watches.

## Usage

Run the scripts from the `bonus/` folder. GitLab needs a lot of resources: plan
for at least 8 GB of RAM and 20 GB of free disk space.

### 1. Install the tools

```bash
./scripts/install.sh
```

The script adds the current user to the `docker` group, so log out and log back
in (or run `newgrp docker`) before the next step.

### 2. Deploy everything

```bash
./scripts/setup.sh
```

The script:

1. creates the `iot` cluster if it does not exist yet, with port `8888` of the
   host mapped to the cluster load balancer,
2. creates the `gitlab`, `argocd` and `dev` namespaces,
3. deploys GitLab from [confs/gitlab.yaml](confs/gitlab.yaml) and waits until it
   is ready (this can take several minutes on the first start),
4. adds `127.0.0.1 gitlab.iot.test` to `/etc/hosts` (asks for `sudo`) and starts
   a background port-forward to GitLab on port `8081`,
5. reads the `root` password generated by GitLab,
6. pushes the content of `iot-lab/` to `root/iot-malde-ch` on the `main` branch;
   GitLab creates the private project on this first push,
7. restarts CoreDNS so the `gitlab.iot.test` rewrite rule is loaded,
8. installs Argo CD if it is not already installed,
9. registers the GitLab project in Argo CD with a repository secret,
10. applies [confs/application.yaml](confs/application.yaml) and waits until the
    application is `Synced`,
11. prints the URLs and credentials, then keeps a port-forward to Argo CD open.

The script stays in the foreground. `Ctrl-C` stops both port-forwards; the
cluster and the application keep running.

### 3. Access the services

| Service | URL | Credentials |
| --- | --- | --- |
| Application | http://localhost:8888 | - |
| GitLab | http://gitlab.iot.test:8081 | `root` / printed by `setup.sh` |
| Argo CD | https://localhost:8080 | `admin` / printed by `setup.sh` |

To reopen the interfaces after `setup.sh` has stopped:

```bash
kubectl -n gitlab port-forward svc/gitlab 8081:8081
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### 4. Clean up

```bash
./scripts/clean.sh
```

Deleting the cluster also deletes the GitLab volume, so every project stored in
GitLab is lost. Run `clean.sh` before running `setup.sh` again.

## Limitations

This setup is a lab, not a production deployment:

- GitLab is served over plain HTTP and runs as a single pod. A real Kubernetes
  deployment would use the official GitLab Helm chart and HTTPS.
- Argo CD authenticates to GitLab with the `root` account. A dedicated user with
  a read-only deploy token would be safer.
- GitLab deletes `/etc/gitlab/initial_root_password` 24 hours after its first
  start, after which `setup.sh` can no longer read the password.

## Useful kubectl commands

```bash
# Cluster and namespaces
kubectl get nodes
kubectl get ns

# GitLab
kubectl get pods,svc,pvc -n gitlab
kubectl logs -n gitlab deployment/gitlab --tail=50
kubectl exec -n gitlab deployment/gitlab -- \
  awk '/^Password:/ {print $2}' /etc/gitlab/initial_root_password

# DNS rewrite seen from inside the cluster
kubectl get configmap coredns-custom -n kube-system -o yaml
kubectl run dns-test --rm -it --restart=Never --image=busybox -- \
  nslookup gitlab.iot.test

# Argo CD
kubectl get pods -n argocd
kubectl get application playground -n argocd \
  -o jsonpath='{.status.sync.comparedTo.source.repoURL} {.status.sync.status} {.status.sync.revision}{"\n"}'

# Application
kubectl get all -n dev
curl http://localhost:8888/
```

## References

- [GitLab Docker installation](https://docs.gitlab.com/install/docker/installation/)
- [K3s CoreDNS custom configuration](https://docs.k3s.io/advanced#coredns-custom-configuration-imports)
- [Argo CD private repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
