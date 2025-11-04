#!/usr/bin/env bash
set -euo pipefail

NS="workshop"
APP_LABEL="app=postgres"
DATE="$(date +%F)"
OUT="backup-${DATE}.sql"

POD="$(kubectl -n "$NS" get po -l "$APP_LABEL" -o jsonpath='{.items[0].metadata.name}')"

echo "[i] Dump logique de toutes les DB depuis le pod ${POD} -> ${OUT}"
kubectl -n "$NS" exec -it "$POD" -- bash -lc 'pg_dumpall -U postgres' > "${OUT}"

echo "[✓] Fichier créé: ${OUT}"
