# M2-Informatique-R-seau-Conteneurisation-Orchestration

S5 — PostgreSQL en StatefulSet (PV/PVC dynamiques) + Runbook Backup/Restore

🎯 Objectifs
- Comprendre et mettre en œuvre PV/PVC/StorageClass (provisioning dynamique).
- Déployer PostgreSQL 16 en StatefulSet avec volumeClaimTemplates.
- Exposer un Headless Service.
- Réaliser un backup logique et un restore (pg_dumpall / psql).

🧱 Pré-requis
- kubectl configuré vers le cluster.
- Une StorageClass fonctionnelle (sur K3s/K3d : local-path par défaut).
  kubectl get storageclass

Manifests présents :
k8s/00-namespace.yaml
k8s/10-secret.yaml
k8s/20-service-headless.yaml
k8s/30-statefulset.yaml

Scripts de runbook :
runbook/backup-linux-macos.sh
runbook/restore-linux-macos.sh
runbook/backup-windows.ps1
runbook/restore-windows.ps1

📦 Déploiement
⚠️ Si tu utilises K3s/K3d, mets storageClassName: local-path ou supprime la ligne pour utiliser la SC par défaut.
```
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/10-secret.yaml
kubectl apply -f k8s/20-service-headless.yaml
kubectl apply -f k8s/30-statefulset.yaml
```

Vérifications
```
kubectl -n workshop get pods -l app=postgres -w
kubectl -n workshop get pvc
kubectl -n workshop get pv
kubectl -n workshop describe sts postgres
```

Attendu :
Pod postgres-0 Running
PVC data-postgres-0 Bound (PV Bound)

✅ Test de persistance
Créer une DB/table, insérer une valeur puis vérifier après redémarrage du Pod.
POD=$(kubectl -n workshop get po -l app=postgres -o jsonpath='{.items[0].metadata.name}')

# Création d’une base et d’une table d’essai
```
kubectl -n workshop exec -it "$POD" -- bash -lc 'psql -U postgres -c "CREATE DATABASE demo;"'
kubectl -n workshop exec -it "$POD" -- bash -lc 'psql -U postgres -d demo -c "CREATE TABLE t(x int); INSERT INTO t VALUES (42);"'
kubectl -n workshop exec -it "$POD" -- bash -lc 'psql -U postgres -d demo -c "SELECT * FROM t;"'
```
# Redémarrage du Pod et attente de readiness
```
kubectl -n workshop delete pod -l app=postgres
kubectl -n workshop wait --for=condition=ready pod -l app=postgres --timeout=180s
```
# Vérification : la donnée persiste grâce au PVC
```
POD=$(kubectl -n workshop get po -l app=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl -n workshop exec -it "$POD" -- bash -lc 'psql -U postgres -d demo -c "SELECT * FROM t;"'
```
🛟 Runbook Backup / Restore
Linux / macOS
cd runbook
chmod +x backup-linux-macos.sh restore-linux-macos.sh

# Backup logique (exporte toutes les DB/roles)
```
./backup-linux-macos.sh
```
# Restore
```
./restore-linux-macos.sh backup-YYYY-MM-DD.sql
```
Windows (PowerShell)
```
cd runbook
.\backup-windows.ps1
```
```
.\restore-windows.ps1 -File
.\backup-YYYY-MM-DD.sql
```

Ce que font les scripts :
pg_dumpall -U postgres (dans le Pod) → redirigé dans un fichier local backup-YYYY-MM-DD.sql
psql -U postgres (dans le Pod) ← réinjecte le contenu du dump

🧰 Dépannage (FAQ)
PVC en Pending
Vérifie la StorageClass et le provisioner :
```
kubectl get storageclass
kubectl -n kube-system get pods -l app=local-path-provisioner
kubectl -n workshop describe pvc data-postgres-0
```

Si tu as changé volumeClaimTemplates, tu dois supprimer et recréer le StatefulSet (champs immuables).
kubectl exec → container not found

Tu as lancé la commande avant que le Pod soit Ready :
```
kubectl -n workshop wait --for=condition=ready pod -l app=postgres --timeout=180s
```
Image Pull / CrashLoop

Logs et describe :
```
kubectl -n workshop logs sts/postgres -c postgres --tail=100
kubectl -n workshop describe pod -l app=postgres
```
🧪 REX — Retour d’Expérience (à compléter)
Contexte cluster & SC choisie : K3d/K3s avec local-path (default).

Difficultés rencontrées :
- PVC Pending lorsque storageClassName: standard (SC inexistante).
- Immutabilité du volumeClaimTemplates → nécessité de supprimer/recréer le StatefulSet.
- kubectl exec trop tôt après delete → container not found (attendre readiness).

Points d’attention :
- Toujours vérifier kubectl get storageclass avant d’écrire storageClassName.
- Utiliser kubectl wait/rollout status avant les exec.

Améliorations possibles :
- Ajouter readiness/liveness probes sur postgres.
- Centraliser variables sensibles via SealedSecrets/External Secrets.
- Observabilité (Prometheus/Grafana + exporter Postgres).
- HPA / VPA (même si Postgres n’est pas idéalement autoscalable).
- Velero complet avec backend S3/MinIO et tests de restore.
