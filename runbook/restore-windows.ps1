param(
  [Parameter(Mandatory=$true)]
  [string]$File
)

$ErrorActionPreference = "Stop"
if (!(Test-Path $File)) { throw "Fichier $File introuvable" }

$ns = "workshop"
$label = "app=postgres"
$pod = kubectl -n $ns get po -l $label -o "jsonpath={.items[0].metadata.name}"

Write-Host "[i] Restauration du dump $File vers $pod"
Get-Content $File -Raw | kubectl -n $ns exec -i $pod -- bash -lc 'psql -U postgres' | Out-Null

Write-Host "[✓] Restauration terminée."
