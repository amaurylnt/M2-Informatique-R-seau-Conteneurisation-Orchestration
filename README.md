# M2-Informatique-R-seau-Conteneurisation-Orchestration

S7 — Observabilité : métriques, logs, traces

Objectifs
- Collecter & visualiser les métriques (Prometheus/Grafana)
- Centraliser les logs (Loki/Promtail)
- Visualiser les traces (OpenTelemetry → Jaeger)
- Créer 2 règles d’alerte pertinentes

Livrables
- 1 dashboard Grafana (latence, erreurs, saturation mini)
- 2 alertes documentées (PrometheusRule + fiche d’exploitation)
- 1 trace visible dans Jaeger

0) Prérequis
- Cluster Kubernetes opérationnel (k3d/k3s/minikube/…).
- kubectl et helm installés.
- Une API (namespace default ci-dessous) qui expose /health et (si possible) /metrics.
- Namespaces :
```
export OBS_NS=observability
export APP_NS=default
```
1) Installation des stacks d’observabilité
1.1 Prometheus + Grafana (kube-prometheus-stack)
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitor prometheus-community/kube-prometheus-stack \
  -n $OBS_NS --create-namespace \
  --set grafana.adminPassword='admin' \
  --set grafana.service.type=ClusterIP
```

1.2 Loki + Promtail (collecte logs)
```
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  -n $OBS_NS \
  --set grafana.enabled=false \
  --set promtail.enabled=true
```
1.3 Jaeger

```
kubectl apply -n $OBS_NS -f https://github.com/jaegertracing/jaeger-operator/releases/latest/download/jaeger-operator.yaml

kubectl -n $OBS_NS rollout status deploy/jaeger-operator --timeout=180s || true
kubectl -n $OBS_NS rollout status deploy/jaeger-operator-webhook --timeout=180s || true

cat <<'YAML' | kubectl apply -n $OBS_NS -f -
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata: { name: simplest }
spec: { strategy: allinone }
YAML
```

2) Provisioning Grafana (datasource Loki)
```
kubectl apply -n $OBS_NS -f k8s/grafana/datasource-loki-configmap.yaml
```

3) Métriques de l’API (Service + ServiceMonitor)
```
kubectl apply -f k8s/monitoring/service-api.yaml
```
# ServiceMonitor pour que Prometheus scrappe l'API
```
kubectl apply -f k8s/monitoring/servicemonitor-api.yaml
```
Important : le ServiceMonitor porte le label release: monitor et scrute le port metrics sur le path /metrics.

4) Traces (OpenTelemetry → Jaeger)
4.1 Auto-instrumentation Node.js (exemple)
Dépendances :
```
npm i -S @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-grpc
```
Fichier fourni : api/tracing.js

Lancer l’API avec preload :
```
node -r ./tracing.js server.js
```

Endpoint OTLP gRPC à utiliser dans le cluster :
- Operator : grpc://simplest-collector.observability:4317
- Fallback “plain” : grpc://jaeger-collector.observability:4317

5) Alerting (2 règles)
```
kubectl apply -f k8s/monitoring/alerts.yaml
```
Règles incluses :
- HighErrorRate : > 2% d’erreurs 5xx sur 10 min
- PodHighRestarts : > 5 redémarrages/10 min

6) Accès aux interfaces
```
# Grafana
kubectl -n $OBS_NS port-forward svc/monitor-grafana 3000:80
# Prometheus
kubectl -n $OBS_NS port-forward svc/monitor-kube-prometheus-st-prometheus 9090:9090 \
  || kubectl -n $OBS_NS port-forward svc/prometheus-operated 9090:9090
# Jaeger (selon option)
kubectl -n $OBS_NS port-forward svc/simplest-query 16686:16686 \
  || kubectl -n $OBS_NS port-forward svc/jaeger-query 16686:16686
```

7) Vérifications & Captures (à insérer)
7.1 Métriques — Prometheus Targets (capture)

- Commandes
```
kubectl -n $OBS_NS get servicemonitors
kubectl -n $OBS_NS get prometheusrules
```

8) Générer du trafic pour tester
```
kubectl -n $APP_NS run curl --image=curlimages/curl -it --rm -- \
  sh -c 'while true; do curl -sS http://api.'$APP_NS'.svc.cluster.local:3000/health >/dev/null; sleep 0.5; done'
```

Pour déclencher HighErrorRate, bombarder une route qui renvoie 500 pendant plusieurs minutes.

9) Fiches d’exploitation (runbooks)
Alerte 1 — HighErrorRate
- Règle : sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.02 sur 10m
- Symptômes : utilisateurs voient des 5xx, panel “error rate” qui grimpe
- Causes probables : bug applicatif, dépendance (DB/API) indisponible, timeout amont
- Diagnostic :
    - Prometheus → “Alerts” → “View expression” (séries fautives)
    - Grafana Explore (Loki) : {app="api"} |= "ERROR"
    - Jaeger : service api, spans en erreur (route/dep fautive)
- Actions :
    - Rollback dernier déploiement si corrélé : kubectl -n $APP_NS rollout undo deploy/api
    - Vérifier santé des dépendances (DB, upstream)
    - Ajuster timeouts/retries si latence inter-service

Alerte 2 — PodHighRestarts
- Règle : increase(kube_pod_container_status_restarts_total[10m]) > 5 sur 15m
- Symptômes : CrashLoopBackOff, indisponibilité intermittente
- Causes probables : OOM/CPU throttling, probes trop agressives, secret/env manquants
- Diagnostic :
```
kubectl -n $APP_NS get pods | grep api

kubectl -n $APP_NS describe pod <pod> (Events)

kubectl -n $APP_NS logs <pod> -p (logs du conteneur précédent)
```
Panels CPU/mémoire Grafana
- Actions :
    - Assouplir/lisser probes liveness/readiness, puis rollout restart
    - Augmenter requests/limits si OOM/CPU
    - Corriger variables d’env/secret et re-déployer

11) Vérifications par commandes (récap)
```
# Services Prometheus
kubectl -n $OBS_NS get svc | grep -i prom
# Targets UP ?
kubectl -n $OBS_NS port-forward svc/monitor-kube-prometheus-st-prometheus 9090:9090 \
  || kubectl -n $OBS_NS port-forward svc/prometheus-operated 9090:9090

curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up{job=~".*api.*"}'

# Loki (logs)
kubectl -n $OBS_NS port-forward svc/loki 3100:3100
curl -G --data-urlencode 'query={app="api"}' --data-urlencode 'limit=10' \
  'http://localhost:3100/loki/api/v1/query'

# Jaeger (traces)
kubectl -n $OBS_NS port-forward svc/simplest-query 16686:16686 \
  || kubectl -n $OBS_NS port-forward svc/jaeger-query 16686:16686
curl -s http://localhost:16686/api/services
```

12) Débrief / REX (exemple concis)
- Ce qui marche : métriques scrappées via ServiceMonitor, logs centralisés dans Loki, traces OTel visibles dans Jaeger ; dashboard Grafana OK (erreurs, latence p95, CPU).
- Points d’attention : readiness du webhook Jaeger Operator (attendre les rollouts), nom du Service Prometheus (varie selon chart), cohérence des labels (app, release: monitor).
- Améliorations possibles : Alertmanager avec receiver (Slack/email), ajout de panels mémoire & saturation réseau, histogrammes custom côté API, NetPol pour sécuriser la stack d’observabilité, persistence de Jaeger/Prometheus.
