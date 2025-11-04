#!/usr/bin/env bash
set -euo pipefail

NS="workshop"
APP_LABEL="app=postgres"
FILE="${1:-}"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: $0 <backup-file.sql>"
  exit 1
fi

POD="$(kubectl -n "$NS" get po -l "$APP_LABEL" -o jsonpath='{.items[0].metadata.name}')"

echo "[i] Restauration du dump ${FILE} vers ${POD}"
kubectl -n "$NS" exec -i "$POD" -- bash -lc 'psql -U postgres' < "$FILE"

echo "[✓] Restauration terminée."
