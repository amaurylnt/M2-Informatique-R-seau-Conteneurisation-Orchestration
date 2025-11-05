# M2-Informatique-R-seau-Conteneurisation-Orchestration

S6 — Scalabilité & Résilience (Front: httpbin)
Namespace : workshop · Ingress : workshop.local · Controller : Traefik (k3d/k3s)

1) Objectifs du TP

Poser des requests/limits (QoS Burstable).
Mettre en place un HPA (CPU + Pods metric http_requests_per_second si Prometheus Adapter est présent).
Assurer la disponibilité via PDB.
Pratiquer les déploiements : rolling update (Deployment) et canary (Argo Rollouts – bonus).
Charger l’app avec k6 et relever des SLI/SLO.

2) Prérequis

Cluster K8s local (k3d/k3s/minikube).
Traefik comme Ingress Controller (par défaut sur k3d/k3s).
kubectl, curl, k6.
Résolution locale : ajouter 127.0.0.1 workshop.local dans:
Windows: C:\Windows\System32\drivers\etc\hosts
WSL/Linux/macOS: /etc/hosts
k3d conseillé (expose les ports Ingress) :
- k3d cluster create s6 -p "80:80@loadbalancer" -p "443:443@loadbalancer"

3) Arborescence
```
s6-scalability/
├─ k8s/
│  ├─ namespace.yaml
│  ├─ api-deploy.yaml
│  ├─ api-svc.yaml
│  ├─ api-ingress.yaml
│  ├─ api-pdb.yaml
│  └─ api-hpa.yaml
├─ argo-rollouts/         
│  └─ api-rollout.yaml
└─ k6/
   └─ script.js
```
4) Déploiement (manifests de base)
4.1 Créer le namespace
```
kubectl apply -f k8s/namespace.yaml
```
4.2 Déployer l’API httpbin + Service
```
kubectl apply -f k8s/api-deploy.yaml
kubectl apply -f k8s/api-svc.yaml
kubectl -n workshop get deploy,po,svc
```
4.3 Ingress (Traefik)

Ingress vers la racine / du service :
```
kubectl apply -f k8s/api-ingress.yaml
kubectl -n workshop get ingress
curl -i http://workshop.local/status/200  # attendu: 200 OK (page blanche normale)
```
Pour voir du contenu : 
```
curl -i http://workshop.local/get ou /html ou /status/418.
```
5) QoS — Requests/Limits
Les requests/limits sont posés dans api-deploy.yaml :
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits:   { cpu: "300m", memory: "256Mi" }


Vérification :
```
kubectl -n workshop get pod -l app=api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.qosClass}{"\n"}{end}'
```
6) PDB — PodDisruptionBudget
```
kubectl apply -f k8s/api-pdb.yaml
kubectl -n workshop get pdb
kubectl -n workshop describe pdb api-pdb
```
7) HPA — Autoscaling
7.1 Pré-requis
metrics-server doit être présent :
```
kubectl -n kube-system get deploy metrics-server
kubectl top pods -n workshop
```
7.2 Appliquer l’HPA
```
kubectl apply -f k8s/api-hpa.yaml
kubectl -n workshop get hpa api-hpa -o wide
```
La metric CPU doit se remplir (sinon attendre ~1 min).
La metric Pods http_requests_per_second restera Unknown sans Prometheus Adapter.

8) Charge & SLI/SLO avec k6
8.1 Script k6
```
k6/script.js appelle http://workshop.local/status/200 (ou /get si vous voulez un corps de réponse visible).
```
Lancer :
```
k6 run k6/script.js
```

Observer en parallèle :
```
kubectl -n workshop get hpa api-hpa -w
kubectl -n workshop get deploy api -w
kubectl -n workshop top pods
```  
Astuce : si httpbin consomme trop peu de CPU, abaisser temporairement averageUtilization (ex. 20) ou requests/limits pour déclencher un scale.

Script k6 utilisé

k6/script.js
```
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    rps: {
      executor: 'constant-arrival-rate',
      rate: 50,          // 50 req/s
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 20,
      maxVUs: 50,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
  },
};

export default () => {
  const res = http.get('http://workshop.local/status/200'); // ou /get si tu veux un corps
  check(res, { 'status 200': (r) => r.status === 200 });
};
```
8.2 SLI/SLO
Indicateur (SLI)	Cible (SLO)	Mesure (k6/kubectl)	Résultat
Disponibilité (%)	≥ 99.5% sur 30j	http_req_failed<1%	…
Latence p95 (ms)	< 300 ms	http_req_duration	…
Taux d’erreurs (%)	< 1%	http_req_failed	…
Saturation CPU pod (%)	< 80%	kubectl top pods	…

9) Rolling update (Deployment)
Si vous avez fait le canary (bonus) avec Rollout, repassez un instant en Deployment pour cocher la case rolling.
```
kubectl -n workshop delete rollout api --ignore-not-found
kubectl apply -f k8s/api-deploy.yaml
kubectl -n workshop rollout status deploy/api
kubectl -n workshop set image deploy/api api=kennethreitz/httpbin:latest
kubectl -n workshop rollout history deploy/api
kubectl -n workshop rollout undo deploy/api
```
10) Bonus — Canary avec Argo Rollouts
Installer le contrôleur + CLI
```
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```
10.2 Basculer Deployment → Rollout
```
kubectl -n workshop delete deploy api --ignore-not-found
kubectl apply -f argo-rollouts/api-rollout.yaml
kubectl -n workshop get rollout
kubectl argo rollouts -n workshop get rollout api
```
10.3 Lancer une “nouvelle version” & suivre
```
kubectl -n workshop patch rollout api --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"kennethreitz/httpbin:latest"}]'
kubectl argo rollouts -n workshop get rollout api --watch
```
11) REX (retour d’expérience)
- Ingress/Traefik : exposer à la racine / évite les soucis de rewrite. Les 404 initiales venaient d’un préfixe /api non “strippé”.
- QoS : avec requests<limits, la classe Burstable protège mieux en contention que BestEffort.
- HPA : avec httpbin, la charge CPU est faible → il faut ajuster les cibles (ou requests/limits) pour observer le scale.
- PDB : utile pour maintenir N pods disponibles durant des opérations de maintenance (drain). Sur cluster 1 nœud, le drain est bloqué si PDB trop strict.
- Canary : Argo Rollouts apporte de la progressivité (10%→30%→60%) et un contrôle fin (pause/promotion/abort). Très pratique pour mitiger le risque en prod.
- k6 : simple à script, pratique pour fixer des thresholds (p95, erreurs) et jouer des scénarios à RPS constant.

12) Dépannage rapide
- 404 Ingress : vérifier ingressClassName: traefik, host workshop.local, règle sur /.
- Connexion refusée : sur k3d, exposer -p "80:80@loadbalancer".
- HPA “Unknown” : metrics-server absent. Pods metric Unknown : Prometheus Adapter manquant.
- k6 100% failed : URL cible erronée / DNS non résolu dans WSL → ajouter workshop.local dans /etc/hosts de WSL.
- PDB qui bloque : réduire minAvailable temporairement ou ajouter des nœuds pour permettre un drain.
