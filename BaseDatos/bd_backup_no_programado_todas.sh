#!/usr/bin/env bash
### 💾 Script de backup de todas las bases de datos (sin programar)
#
# Hace el backup de las 20 bases conocidas en una sola pasada, guardando
# la corrida en una subcarpeta con fecha y hora. Se ejecuta una sola
# vez y termina: no pregunta frecuencia ni queda como servicio systemd.
set -euo pipefail

usage() {
  cat <<EOF
Uso: $0

Hace el backup de TODAS las bases de datos conocidas (una por cada
servidor de Servisofts, con las credenciales de credenciales.sh) en
una sola pasada, la guarda en una subcarpeta con fecha y hora dentro
del directorio destino que elijas, y termina. A diferencia de
bd_backup_programado_todas.sh, no pregunta frecuencia ni queda como
servicio systemd.

Opciones:
  -h, --help    Mostrar esta ayuda
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CREDENCIALES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/credenciales.sh"
if [[ ! -f "$CREDENCIALES" ]]; then
  echo "Falta $CREDENCIALES (con PGUSER, PGPASSWORD y WEBHOOK_URL). Creá ese archivo primero." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CREDENCIALES"
export PGPASSWORD

# nombre|host|puerto|base de datos (orden alfabético por nombre)
BASES=(
  "caja|192.168.5.45|5432|servisofts.caja"
  "calistenia|192.168.5.18|5432|servisofts.calistenia"
  "chat|192.168.5.9|5432|servisofts.chat"
  "compra-venta|192.168.5.41|5432|servisofts.compra_venta"
  "contabilidad|192.168.5.11|5432|servisofts.contabilidad"
  "crm|192.168.5.51|5432|servisofts.crm"
  "drive|192.168.5.17|5432|servisofts.drive"
  "empresa|192.168.5.29|5432|servisofts.empresa"
  "facturacion|192.168.5.28|5432|servisofts.facturacion"
  "geolocation|192.168.5.5|5432|servisofts.geolocation"
  "inventario|192.168.5.39|5432|servisofts.inventario"
  "notification|192.168.5.33|5432|servisofts.notification"
  "proyecto|192.168.5.14|5432|servisofts.proyecto"
  "roles|192.168.5.16|5432|servisofts.roles_permisos"
  "serp|192.168.5.48|5432|servisofts.serp"
  "servicios|192.168.5.1|5432|servisofts.servicio"
  "staffprousa|192.168.5.53|5432|servisofts.StaffProUsa"
  "stats|192.168.2.2|5432|servisofts.stats"
  "usuario|192.168.5.2|5432|servisofts.usuario"
  "zkteco|192.168.5.32|5432|servisofts.zkteco"
)

GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

notificar_discord() {
  local mensaje="$1"
  curl -s -o /dev/null \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"$mensaje\"}" \
    "$WEBHOOK_URL" || true
}

read -rp "Carpeta destino para los backups [.]: " BASE_DIR
BASE_DIR="${BASE_DIR:-.}"
mkdir -p "$BASE_DIR"
BASE_DIR="$(cd "$BASE_DIR" && pwd)"

TS=$(date +%Y%m%d%H%M%S)
RUN_DIR="$BASE_DIR/backup-$TS"
mkdir -p "$RUN_DIR"

echo
echo "Backup de todas las bases en '$RUN_DIR'..."
echo

EXITOSOS=0
FALLIDOS=0

for entrada in "${BASES[@]}"; do
  IFS='|' read -r nombre host puerto db <<< "$entrada"
  printf '%-14s %-18s ' "$nombre" "$host:$puerto"
  if pg_dump \
      --host="$host" \
      --port="$puerto" \
      --username="$PGUSER" \
      --format=custom \
      --file="$RUN_DIR/${nombre}.dump" \
      "$db" 2>"$RUN_DIR/${nombre}.error.log"; then
    echo -e "${GREEN}OK${RESET}"
    rm -f "$RUN_DIR/${nombre}.error.log"
    EXITOSOS=$((EXITOSOS + 1))
  else
    echo -e "${RED}FALLÓ${RESET} (ver $RUN_DIR/${nombre}.error.log)"
    FALLIDOS=$((FALLIDOS + 1))
  fi
done

echo
echo -e "${GREEN}✔ Backup completo: $EXITOSOS ok, $FALLIDOS con error. Carpeta: $RUN_DIR${RESET}"
notificar_discord "Backup de todas las bases: $EXITOSOS ok, $FALLIDOS con error ($RUN_DIR) $(date '+%Y-%m-%d %H:%M:%S')"

exit 0
