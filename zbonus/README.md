# Partie 3 — GitLab local

GitLab remplace GitHub comme source du dépôt Git. Argo CD garde la synchronisation
automatique (`prune`, `selfHeal`) vers `dev` et sert le Hello World sur le port
`8888`. Le contenu de l'application vit dans GitLab ; l'image BusyBox ne sert
que de runtime HTTP.

## 1. Démarrer GitLab

Depuis `zbonus/` :

```bash
./scripts/setup.sh
```

Le script crée ou réutilise le cluster `iot` et cible explicitement le contexte
`k3d-iot`. GitLab CE `19.5.6` tourne dans le namespace `gitlab` avec un volume
`local-path`. La suppression du cluster par `scripts/clean.sh` efface aussi ce
volume : sauvegarder le dépôt avant de nettoyer. Ce déploiement mononœud GitLab
en HTTP est réservé au lab ; pour un déploiement Kubernetes maintenu, utiliser
le chart officiel et HTTPS.

Ajouter `127.0.0.1 gitlab.iot.test` dans `/etc/hosts` sur la machine qui lance le
port-forward et ouvre le navigateur. Dans un terminal dédié :

```bash
./scripts/gitlab.sh
```

GitLab est accessible à <http://gitlab.iot.test:8081>. CoreDNS résout ce même nom
vers `svc/gitlab` depuis le cluster ; Argo CD ne dépend pas du port-forward.
Test HTTP sans modifier `/etc/hosts` :

```bash
curl --noproxy '*' --resolve gitlab.iot.test:8081:127.0.0.1 \
  -fsS http://gitlab.iot.test:8081/users/sign_in -o /dev/null
```

## 2. Publier le projet privé

Le mot de passe initial du compte `root` est dans
`/etc/gitlab/initial_root_password` du conteneur. Dans l'interface d'administration,
créer le compte non administrateur `iot-lab`, puis son projet privé et vide
`iot-malde-ch`. Un administrateur peut définir ou réinitialiser le mot de passe
du compte avec :

```bash
kubectl --context k3d-iot -n gitlab exec -it deployment/gitlab -- \
  gitlab-rake 'gitlab:password:reset[iot-lab]'
```

Copier `iot-malde-ch/manifests/` dans un répertoire séparé du lab, puis, depuis
ce répertoire :

```bash
git init -b main
git add manifests/
git commit -m "Deploy Hello World from local GitLab"
git remote add origin http://gitlab.iot.test:8081/iot-lab/iot-malde-ch.git
git push -u origin main
```

Pour le push, saisir un jeton personnel `write_repository` à l'invite, sans le
mettre dans l'URL. Pour Argo CD, créer un jeton de déploiement `read_repository`
dans le projet. Lancer `./scripts/argocd.sh` et enregistrer l'URL exacte avec le
nom d'utilisateur et le jeton dans **Settings → Repositories**. Aucun jeton
ne doit être commité.

## 3. Vérifier la révision livrée

```bash
kubectl --context k3d-iot apply -f confs/application.yaml
kubectl --context k3d-iot -n argocd wait application/playground \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
kubectl --context k3d-iot -n argocd get application playground \
  -o jsonpath='{.status.sync.comparedTo.source.repoURL}{" "}{.status.sync.revision}{"\n"}'
kubectl --context k3d-iot -n dev rollout status deployment/playground --timeout=300s
curl -fsS http://localhost:8888/
```

L'URL affichée doit être celle de GitLab et le SHA celui du commit sur `main`.
La réponse attendue est `Hello World depuis GitLab local !` et non l'ancien JSON
`v1`. Si l'application existait déjà, la commande `wait` peut observer brièvement
l'ancien statut `Synced` : vérifier l'URL et le SHA avant de conclure.

Références : [installation GitLab Docker](https://docs.gitlab.com/install/docker/installation/),
[chart GitLab](https://docs.gitlab.com/charts/installation/),
[CoreDNS dans K3s](https://docs.k3s.io/advanced#coredns-custom-configuration-imports),
[jetons de déploiement GitLab](https://docs.gitlab.com/user/project/deploy_tokens/),
[dépôts privés Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/).
