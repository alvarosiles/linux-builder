#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Uso: $0

Hace el backup de TODAS las bases de datos conocidas (una por cada
servidor de Servisofts, usuario/contraseña postgres/postgres) en una
sola pasada. Cada corrida se guarda en su propia subcarpeta con fecha
y hora, dentro del directorio destino que elijas.

Te pregunta si querés que esto se repita todos los días y, si decís
que sí, a qué hora. Corre una primera vez en esta terminal para
probar que funciona y después queda como servicio systemd
(automatico-db-todas@<tarea>.service), así que sigue solo incluso
después de reiniciar Ubuntu. Usá stop_automatico.sh para ver o
detener la tarea.

Opciones:
  -h, --help    Mostrar esta ayuda
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ESTADO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.automatico_estado"
JOBS_DIR="$ESTADO_DIR/jobs"
mkdir -p "$JOBS_DIR"

PGUSER="postgres"
PGPASSWORD="postgres"
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

WEBHOOK_URL="https://discord.com/api/webhooks/1530357203590971483/HdNVfftTH-qb9HoCsX5pTuUpgODT74VjoxzZrJSqDeuceiyN4Ozri14yMX0_7ZjYtW4F"

notificar_discord() {
  local mensaje="$1"
  curl -s -o /dev/null \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"$mensaje\"}" \
    "$WEBHOOK_URL" || true
}

# Si nos invoca systemd (automatico-db-todas@<job>.service), no preguntamos
# nada: cargamos la configuración guardada la primera vez que se armó el ciclo.
RUN_JOB_ID=""
if [[ "${1:-}" == "--run-job" ]]; then
  RUN_JOB_ID="${2:?falta el id de la tarea}"
  JOB_FILE="$JOBS_DIR/$RUN_JOB_ID.conf"
  if [[ ! -f "$JOB_FILE" ]]; then
    echo "No existe la configuración de la tarea '$RUN_JOB_ID' ($JOB_FILE)." >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$JOB_FILE"
fi

if [[ -z "$RUN_JOB_ID" ]]; then
  read -rp "Carpeta destino para los backups [.]: " BASE_DIR
  BASE_DIR="${BASE_DIR:-.}"
  mkdir -p "$BASE_DIR"
  BASE_DIR="$(cd "$BASE_DIR" && pwd)"

  read -rp "¿Repetir este backup todos los días automáticamente? (s/n): " DIARIO
  if [[ "$DIARIO" == "s" || "$DIARIO" == "S" ]]; then
    MODO="diario"
    while true; do
      read -rp "¿A qué hora, todos los días? (HH:MM, 24h): " HORA
      [[ "$HORA" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && break
      echo "Formato inválido, probá de nuevo (ej: 02:30)."
    done
    PROGRAMACION_TXT="todos los días a las $HORA"
  else
    MODO="una-vez"
    PROGRAMACION_TXT="una sola vez"
  fi
fi

hacer_backup_todas() {
  local ts run_dir exitosos=0 fallidos=0
  ts=$(date +%Y%m%d%H%M%S)
  run_dir="$BASE_DIR/backup-$ts"
  mkdir -p "$run_dir"

  echo
  echo "Backup de todas las bases en '$run_dir'..."
  echo

  for entrada in "${BASES[@]}"; do
    IFS='|' read -r nombre host puerto db <<< "$entrada"
    printf '%-14s %-18s ' "$nombre" "$host:$puerto"
    if pg_dump \
        --host="$host" \
        --port="$puerto" \
        --username="$PGUSER" \
        --format=custom \
        --file="$run_dir/${nombre}.dump" \
        "$db" 2>"$run_dir/${nombre}.error.log"; then
      echo -e "${GREEN}OK${RESET}"
      rm -f "$run_dir/${nombre}.error.log"
      exitosos=$((exitosos + 1))
    else
      echo -e "${RED}FALLÓ${RESET} (ver $run_dir/${nombre}.error.log)"
      fallidos=$((fallidos + 1))
    fi
  done

  echo
  echo "Backup completo: $exitosos ok, $fallidos con error. Carpeta: $run_dir"
  notificar_discord "Backup de todas las bases: $exitosos ok, $fallidos con error ($run_dir) $(date '+%Y-%m-%d %H:%M:%S')"
}

# Calcula cuántos segundos faltan hasta la próxima ejecución diaria.
segundos_hasta_proxima() {
  local ahora fecha candidato
  ahora=$(date +%s)
  fecha=$(date -d "+0 days" +%F)
  candidato=$(date -d "${fecha}T${HORA}:00" +%s)
  if [[ "$candidato" -le "$ahora" ]]; then
    fecha=$(date -d "+1 days" +%F)
    candidato=$(date -d "${fecha}T${HORA}:00" +%s)
  fi

  echo $(( candidato - ahora ))
}

if [[ -z "$RUN_JOB_ID" ]]; then
  echo -e "${GREEN}✔ Configuración lista: se hará backup de todas las bases $PROGRAMACION_TXT.${RESET}"

  # Primera ejecución, visible en esta terminal.
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ejecutando..."
  hacer_backup_todas

  if [[ "$MODO" == "una-vez" ]]; then
    exit 0
  fi

  PROXIMA=$(date -d "@$(( $(date +%s) + $(segundos_hasta_proxima) ))" '+%Y-%m-%d %H:%M:%S')
  echo -e "${GREEN}✔ Listo.${RESET} Próxima ejecución: $PROXIMA ($PROGRAMACION_TXT)"
  echo
fi

# Nombre único de la tarea: sirve como id de systemd (%i) y de archivo de
# estado/config, tanto al armar el ciclo como al reanudarlo tras reiniciar.
JOB_ID="${RUN_JOB_ID:-todas-$(date +%Y%m%d%H%M%S)-$$}"
JOB_FILE="$JOBS_DIR/$JOB_ID.conf"
LOG_FILE="$ESTADO_DIR/$JOB_ID.log"
ESTADO_FILE="$ESTADO_DIR/$JOB_ID.info"
UNIDAD_SYSTEMD="/etc/systemd/system/automatico-db-todas@.service"

if [[ -z "$RUN_JOB_ID" ]]; then
  # Guarda toda la configuración necesaria para que el ciclo se pueda
  # reanudar después de un reinicio sin volver a preguntar nada.
  {
    echo "BASE_DIR=$(printf '%q' "$BASE_DIR")"
    echo "HORA=$(printf '%q' "$HORA")"
    echo "PROGRAMACION_TXT=$(printf '%q' "$PROGRAMACION_TXT")"
  } > "$JOB_FILE"
  chmod 600 "$JOB_FILE"

  # Unidad systemd "template": una instancia por cada ciclo armado
  # (automatico-db-todas@<JOB_ID>.service), para que Ubuntu la levante sola
  # al arrancar, sin depender de la terminal ni de & / disown.
  CONTENIDO_UNIDAD="$(cat <<EOF
[Unit]
Description=Servisofts backup_todas.sh - tarea %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(id -un)
ExecStart=$SCRIPT_PATH --run-job %i
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF
)"

  if [[ "$(cat "$UNIDAD_SYSTEMD" 2>/dev/null || true)" != "$CONTENIDO_UNIDAD" ]]; then
    echo "$CONTENIDO_UNIDAD" | sudo tee "$UNIDAD_SYSTEMD" >/dev/null
    sudo systemctl daemon-reload
  fi

  sudo systemctl enable --now "automatico-db-todas@${JOB_ID}.service"

  echo -e "${GREEN}✔ Ciclo persistente activado${RESET} (tarea $JOB_ID)."
  echo "Log de las próximas ejecuciones: $LOG_FILE"
  echo "Sigue solo aunque cierres la terminal o reinicies Ubuntu."
  echo "Usá stop_automatico.sh para ver o detener las tareas automáticas activas."

  exit 0
fi

# A partir de acá solo se ejecuta cuando nos invoca systemd
# (automatico-db-todas@<JOB_ID>.service), tanto en el arranque normal del
# ciclo como al reanudarlo después de un reinicio.
exec >>"$LOG_FILE" 2>&1 </dev/null

trap 'rm -f "$ESTADO_FILE"' EXIT

cat > "$ESTADO_FILE" <<EOF
JOB_ID=$(printf '%q' "$JOB_ID")
TIPO=db-todas-systemd
ACCION=$(printf '%q' "backup de todas las bases")
INTERVALO=$(printf '%q' "$PROGRAMACION_TXT")
INICIO=$(printf '%q' "$(date '+%Y-%m-%d %H:%M:%S')")
EOF

while true; do
  sleep "$(segundos_hasta_proxima)"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ejecutando..."
  hacer_backup_todas
  proxima=$(date -d "@$(( $(date +%s) + $(segundos_hasta_proxima) ))" '+%Y-%m-%d %H:%M:%S')
  echo "✔ Listo. Próxima ejecución: $proxima ($PROGRAMACION_TXT)"
done
