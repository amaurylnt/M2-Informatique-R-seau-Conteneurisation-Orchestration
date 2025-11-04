$ErrorActionPreference = "Stop"
$ns = "workshop"
$label = "app=postgres"
$date = Get-Date -Format "yyyy-MM-dd"
$out = "backup-$date.sql"

$pod = kubectl -n $ns get po -l $label -o "jsonpath={.items[0].metadata.name}"

Write-Host "[i] Dump logique depuis le pod $pod -> $out"
# -i obligatoire (stdin), -t optionnel
kubectl -n $ns exec -i $pod -- bash -lc 'pg_dumpall -U postgres' | Out-File -Encoding UTF8 $out

Write-Host "[✓] Fichier créé: $out"
