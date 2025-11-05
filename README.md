# M2-Informatique-R-seau-Conteneurisation-Orchestration

# TP S4 — Ingress, TLS, Config & Secrets  
**Module : Conteneurisation & Orchestration (Kubernetes)**  

---

## 🎯 Objectifs du TP

Ce TP a pour objectif de :
- Exposer deux services HTTP (Front + API) derrière un **Ingress Controller NGINX** ;
- Sécuriser les flux via un certificat **TLS** géré par **cert-manager** (ClusterIssuer `selfsigned`) ;
- Gérer des paramètres via un **ConfigMap** et un **Secret** ;
- Mettre en œuvre un **rollback** rapide d’une release défectueuse.

---

## ⚙️ Architecture cible

| Élément | Description |
|----------|-------------|
| `/front` | Service web statique (image NGINX) |
| `/api` | Service API HTTP (image httpbin) |
| TLS | Certificat auto-signé géré par cert-manager |
| Ingress Controller | NGINX |
| Namespace | `workshop` |

📁 Arborescence du projet
k8s/
├─ 00-namespace.yaml
├─ 10-configmap.yaml
├─ 11-secret.yaml
├─ 20-deploy-front.yaml
├─ 21-svc-front.yaml
├─ 30-deploy-api.yaml
├─ 31-svc-api.yaml
├─ 40-clusterissuer.yaml
├─ 50-ingress.yaml
├─ manifest.yaml      
README.md
🧱 Prérequis

Docker Desktop ou Docker Engine
k3d + kubectl + Helm
Ports 80 et 443 libres
Ajout dans /etc/hosts (ou C:\Windows\System32\drivers\etc\hosts) :
127.0.0.1  workshop.local

🚀 Déploiement complet

## 1️⃣ Lancer le cluster et l’environnement

chmod +x scripts/*.sh
./scripts/bootstrap.sh
Ce script exécute automatiquement :
- la création du cluster k3d
- l’installation d’Ingress NGINX
- l’installation de cert-manager
- le déploiement des manifests du TP

🧩 Vérification du déploiement
kubectl -n workshop get deploy,po,svc,ingress

Résultat attendu :
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
deploy/api     2/2     2            2           2m
deploy/front   2/2     2            2           2m

NAME           TYPE        CLUSTER-IP     PORT(S)   AGE
svc/api        ClusterIP   10.43.191.xxx  80/TCP    2m
svc/front      ClusterIP   10.43.132.xxx  80/TCP    2m

NAME           CLASS   HOSTS            ADDRESS   PORTS   AGE
ingress/web    nginx   workshop.local             80,443  2m

🔍 Tests d’accès
🌐 HTTP
- curl -v  http://workshop.local/front

🔒 HTTPS (certificat self-signed)
- curl -vk https://workshop.local/front
- curl -vk https://workshop.local/api/get

Résultats attendus :
/front → affiche la page “Welcome to nginx / Hello from NGINX Demo”
/api/get → renvoie une réponse JSON de httpbin (status 200)

## Diagramme

<img width="837" height="131" alt="diagramme_L7_ingress_TLS" src="https://github.com/user-attachments/assets/231dda56-4551-4360-9770-e73bd7dfccf7" />

### 🔁 Rollback d’une release
## 1️⃣ Casser volontairement le front :
kubectl -n workshop set image deployment/front front=nginx:broken
kubectl -n workshop rollout status deploy/front

## 2️⃣ Observer l’échec :
kubectl -n workshop get pods -l app=front

## 3️⃣ Revenir à la version stable :
kubectl -n workshop rollout undo deployment/front
kubectl -n workshop rollout status deploy/front

## 4️⃣ Vérifier que le front est de nouveau accessible :
curl -vk https://workshop.local/front

🧠 Choix techniques
Élément	- Choix	- Justification
Ingress Controller	- NGINX	Référence Kubernetes - simple et stable
TLS	- cert-manager + ClusterIssuer selfsigned	- Permet un HTTPS local sans dépendance externe
Front	- nginxdemos/hello:plain-text	- Image légère, facile à tester
API	- kennethreitz/httpbin	- Fournit des endpoints HTTP de test
ConfigMap	- BANNER_TEXT	- Stockage de configuration non sensible
Secret	- DB_USER, DB_PASS	- Variables sensibles isolées
Rollback	- kubectl rollout undo	- Retour rapide à la dernière version stable

## 🔄 Retour d’expérience (REX)

### ✅ Ce que j’ai réussi
- J’ai réussi à déployer un cluster Kubernetes complet avec **Ingress NGINX** et **cert-manager**.  
- Les deux services (Front et API) sont désormais accessibles en HTTPS via le nom de domaine local `workshop.local`.  
- Le déploiement des **ConfigMap** et **Secret** fonctionne correctement, avec injection des variables d’environnement dans les pods.  
- J’ai compris comment exécuter un **rollback** Kubernetes pour revenir à une version stable après une erreur d’image.

### ⚠️ Difficultés rencontrées
- J’ai eu des problèmes d’**ImagePullBackOff** au début (les images n’étaient pas téléchargées depuis GHCR).  
  → J’ai contourné ce problème en remplaçant par une image Docker Hub (`nginxdemos/hello:plain-text`), plus accessible.  
- J’ai eu des erreurs de **résolution DNS** sur `workshop.local`, corrigées en ajoutant la ligne `127.0.0.1 workshop.local` dans le fichier `hosts`.  
- L’installation de **Helm** et du **cert-manager** m’a pris du temps au début, le dépôt officiel ayant changé d’URL récemment.

### 🧠 Ce que j’ai appris
- Le rôle précis de chaque ressource Kubernetes (Deployment, Service, Ingress, Secret, ConfigMap, etc.).  
- La différence entre un **Service L4 (ClusterIP)** et un **Ingress L7**, et comment l’Ingress gère le routage HTTPs.  
- L’importance de **cert-manager** pour automatiser la gestion TLS, même en environnement local.  
- Comment gérer des erreurs de déploiement via `kubectl rollout undo`, et suivre l’état d’un déploiement en direct.

### 🚀 Pistes d’amélioration personnelle
- Automatiser le déploiement complet via un **pipeline GitHub Actions**.  
- Tester une configuration **Ingress TLS avec Let's Encrypt staging**.  
- Explorer les outils d’observabilité (Prometheus / Grafana) pour visualiser les métriques du cluster.  
- Créer un **chart Helm** pour packager cette application et simplifier les déploiements futurs.

💡 En résumé : ce TP m’a permis de consolider mes compétences Kubernetes, de comprendre le rôle de l’Ingress et du TLS dans une architecture L7, et d’améliorer ma capacité à diagnostiquer des problèmes réseau et applicatifs en autonomie.
