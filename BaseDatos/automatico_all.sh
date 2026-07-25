#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Uso: $0

Muestra un menú (flechas ↑↓ + Enter) con los servidores/bases de
datos conocidos, pide usuario y contraseña, te deja elegir hacer
backup o restaurar, y después cada cuánto tiempo repetirlo (2 min,
10 min, 1 hora, 6 horas, o todos los días a una hora específica).
Corre una primera vez en esta terminal para probar que funciona, y
después queda como servicio systemd (automatico-db@<tarea>.service),
así que sigue solo incluso después de reiniciar Ubuntu.

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

# Si nos invoca systemd (automatico-db@<job>.service), no preguntamos nada:
# cargamos la configuración guardada la primera vez que se armó el ciclo.
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
  export PGPASSWORD
fi

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

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RESET='\033[0m'

WEBHOOK_URL="https://discord.com/api/webhooks/1530357203590971483/HdNVfftTH-qb9HoCsX5pTuUpgODT74VjoxzZrJSqDeuceiyN4Ozri14yMX0_7ZjYtW4F"

notificar_discord() {
  local mensaje="$1"
  curl -s -o /dev/null \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"$mensaje\"}" \
    "$WEBHOOK_URL" || true
}

# Menú de flechas genérico: recibe el texto del prompt, una línea de
# encabezado opcional (vacía si no aplica) y las opciones, devuelve por
# stdout el índice elegido (0-based).
elegir_opcion() {
  local prompt="$1"
  local encabezado="$2"
  shift 2
  local -a items=("$@")
  local total=${#items[@]}
  local selected=0
  local key rest

  dibujar() {
    local ancho=$(( $(tput cols) - 1 ))
    local texto
    for i in "${!items[@]}"; do
      tput el
      if [[ $i -eq $selected ]]; then
        texto="> ${items[$i]}"
        echo -e "${YELLOW}${texto:0:$ancho}${RESET}"
      else
        texto="  ${items[$i]}"
        echo "${texto:0:$ancho}"
      fi
    done
  }

  echo -e "${YELLOW}${prompt}${RESET}" >&2
  echo >&2
  [[ -n "$encabezado" ]] && echo " $encabezado" >&2
  tput civis >&2
  dibujar >&2
  while true; do
    IFS= read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
      read -rsn2 -t 0.01 rest || true
      case "$rest" in
        '[A') ((selected--)) || true; [[ $selected -lt 0 ]] && selected=$((total - 1)) ;;
        '[B') ((selected++)) || true; [[ $selected -ge $total ]] && selected=0 ;;
      esac
    elif [[ -z $key ]]; then
      break
    fi
    tput cuu "$total" >&2
    dibujar >&2
  done
  tput cnorm >&2

  echo "$selected"
}

if [[ -z "$RUN_JOB_ID" ]]; then
  LINEAS=()
  for i in "${!BASES[@]}"; do
    IFS='|' read -r NOMBRE HOST PUERTO DB <<< "${BASES[$i]}"
    LINEAS+=("$(printf '%-14s %s' "$NOMBRE" "$HOST:$PUERTO")")
  done

  ENCABEZADO=$(printf '%-14s %s' "server" "ip")
  OPCION=$(elegir_opcion "lista de servidores" "$ENCABEZADO" "${LINEAS[@]}")
  echo

  IFS='|' read -r NOMBRE PGHOST PGPORT _ <<< "${BASES[$OPCION]}"

  read -rp "Usuario [postgres]: " PGUSER
  PGUSER="${PGUSER:-postgres}"
  [[ "$PGUSER" == "p" ]] && PGUSER="postgres"

  read -rsp "Contraseña: " PGPASSWORD
  echo
  [[ "$PGPASSWORD" == "p" ]] && PGPASSWORD="postgres"
  export PGPASSWORD

  echo
  echo "Conectando a '$NOMBRE' ($PGHOST:$PGPORT)..."
  echo

  mapfile -t DBS < <(psql \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname=postgres \
    --tuples-only \
    --no-align \
    --pset=pager=off \
    --command="SELECT datname FROM pg_database ORDER BY datname;")

  ACCIONES=("Hacer backup" "Restaurar un backup")
  ACCION=$(elegir_opcion "¿Qué querés hacer? (↑/↓ y Enter):" "" "${ACCIONES[@]}")
  echo
fi

hacer_backup() {
  echo
  echo "Generando backup de '$PGDATABASE'..."
  echo

  TS=$(date +%Y%m%d%H%M%S)
  local outfile="$TARGET/${PGDATABASE}-${TS}.dump"

  local total_tablas
  total_tablas=$(psql \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --tuples-only \
    --no-align \
    --pset=pager=off \
    --command="SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema');")

  local ancho=30

  barra_progreso() {
    local porc=$1
    local llenas=$(( porc * ancho / 100 ))
    local vacias=$(( ancho - llenas ))
    printf '['
    [[ $llenas -gt 0 ]] && printf '%0.s#' $(seq 1 "$llenas")
    [[ $vacias -gt 0 ]] && printf '%0.s.' $(seq 1 "$vacias")
    printf '] %3d%% (%d/%d tablas)' "$porc" "$procesadas" "$total_tablas"
  }

  pg_dump \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --format=custom \
    --file="$outfile" \
    --verbose \
    "$PGDATABASE" 2>&1 >/dev/null | {
      procesadas=0
      printf '\r%s' "$(barra_progreso 0)"
      while IFS= read -r linea; do
        if [[ "$linea" == *"dumping contents of table"* ]]; then
          procesadas=$((procesadas + 1))
          if [[ "$total_tablas" -gt 0 ]]; then
            porc=$((procesadas * 100 / total_tablas))
          else
            porc=100
          fi
          [[ $porc -gt 100 ]] && porc=100
          printf '\r%s' "$(barra_progreso "$porc")"
        fi
      done
      printf '\r%s\n' "$(procesadas=$total_tablas barra_progreso 100)"
    }

  echo "Backup creado: $outfile"
  notificar_discord "Backup \\\"$PGDATABASE\\\" realizado $(date '+%Y-%m-%d %H:%M:%S')"
}

hacer_restore() {
  echo
  echo "Restaurando '$DUMPFILE' en '$PGDATABASE'..."

  pg_restore \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --clean \
    --if-exists \
    --no-owner \
    --verbose \
    "$DUMPFILE"

  echo "Restauración completada."
  notificar_discord "Restauración \\\"$PGDATABASE\\\" realizada $(date '+%Y-%m-%d %H:%M:%S')"
}

if [[ -z "$RUN_JOB_ID" ]]; then
  if [[ "$ACCION" -eq 0 ]]; then
    DBOPCION=$(elegir_opcion "Seleccioná la base de datos para backup (↑/↓ y Enter):" "" "${DBS[@]}")
    echo

    PGDATABASE="${DBS[$DBOPCION]}"

    read -rp "Directorio destino [.]: " TARGET
    TARGET="${TARGET:-.}"
    mkdir -p "$TARGET"
    TARGET="$(cd "$TARGET" && pwd)"
  else
    read -rp "Directorio con backups [.]: " BACKUP_DIR
    BACKUP_DIR="${BACKUP_DIR:-.}"

    mapfile -t DUMPS < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.dump' | sort)

    if [[ ${#DUMPS[@]} -eq 0 ]]; then
      echo "No se encontraron archivos .dump en '$BACKUP_DIR'." >&2
      exit 1
    fi

    DUMPLINEAS=()
    for f in "${DUMPS[@]}"; do
      DUMPLINEAS+=("$(basename "$f")")
    done

    DUMPOPCION=$(elegir_opcion "Seleccioná el backup a restaurar (↑/↓ y Enter):" "" "${DUMPLINEAS[@]}")
    echo

    DUMPFILE="${DUMPS[$DUMPOPCION]}"
    SUGERIDA=$(basename "$DUMPFILE" | sed -E 's/-[0-9]{14}\.dump$//')

    read -rp "Base de datos destino [$SUGERIDA]: " PGDATABASE
    PGDATABASE="${PGDATABASE:-$SUGERIDA}"

    EXISTE="no"
    for db in "${DBS[@]}"; do
      [[ "$db" == "$PGDATABASE" ]] && EXISTE="si"
    done

    if [[ "$EXISTE" == "no" ]]; then
      read -rp "La base '$PGDATABASE' no existe. ¿Crearla? (s/n): " CREAR
      if [[ "$CREAR" == "s" || "$CREAR" == "S" ]]; then
        createdb \
          --host="$PGHOST" \
          --port="$PGPORT" \
          --username="$PGUSER" \
          "$PGDATABASE"
      else
        echo "Cancelado." >&2
        exit 1
      fi
    fi

    DUMPFILE="$(cd "$(dirname "$DUMPFILE")" && pwd)/$(basename "$DUMPFILE")"
  fi

  FRECUENCIA_TXT=("2 min" "10 min" "1 hora" "6 horas" "hora en específico")
  FRECUENCIA_SEG=(120 600 3600 21600 0)

  FRECOPCION=$(elegir_opcion "¿Cada qué tiempo querés que se ejecute? (↑/↓ y Enter):" "" "${FRECUENCIA_TXT[@]}")
  echo

  if [[ "$FRECOPCION" -eq 4 ]]; then
    MODO="diario"

    HORAS_TXT=("6 am" "10 am" "12 pm" "18 pm" "23 pm")
    HORAS_24=("06:00" "10:00" "12:00" "18:00" "23:00")

    HORAOPCION=$(elegir_opcion "¿A qué hora? (↑/↓ y Enter):" "" "${HORAS_TXT[@]}")
    echo

    HORA="${HORAS_24[$HORAOPCION]}"
    PROGRAMACION_TXT="todos los días a las ${HORAS_TXT[$HORAOPCION]}"
  else
    MODO="intervalo"
    INTERVALO_SEG="${FRECUENCIA_SEG[$FRECOPCION]}"
    PROGRAMACION_TXT="cada ${FRECUENCIA_TXT[$FRECOPCION]}"
  fi
fi

# Calcula cuántos segundos faltan hasta la próxima ejecución.
segundos_hasta_proxima() {
  if [[ "$MODO" == "intervalo" ]]; then
    echo "$INTERVALO_SEG"
    return
  fi

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
  if [[ "$ACCION" -eq 0 ]]; then
    ACCION_TXT="backup de '$PGDATABASE'"
  else
    ACCION_TXT="restauración de '$DUMPFILE' en '$PGDATABASE'"
  fi

  echo -e "${GREEN}✔ Automatización configurada con éxito: se hará $ACCION_TXT $PROGRAMACION_TXT.${RESET}"
  echo

  # Primera ejecución, visible en esta terminal.
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ejecutando..."
  if [[ "$ACCION" -eq 0 ]]; then
    hacer_backup
  else
    hacer_restore
  fi
  PROXIMA=$(date -d "@$(( $(date +%s) + $(segundos_hasta_proxima) ))" '+%Y-%m-%d %H:%M:%S')
  echo -e "${GREEN}✔ Listo.${RESET} Próxima ejecución: $PROXIMA ($PROGRAMACION_TXT)"
  echo
fi

# Nombre único de la tarea: sirve como id de systemd (%i) y de archivo de
# estado/config, tanto al armar el ciclo como al reanudarlo tras reiniciar.
JOB_ID="${RUN_JOB_ID:-$(date +%Y%m%d%H%M%S)-$$}"
JOB_FILE="$JOBS_DIR/$JOB_ID.conf"
LOG_FILE="$ESTADO_DIR/$JOB_ID.log"
ESTADO_FILE="$ESTADO_DIR/$JOB_ID.info"
UNIDAD_SYSTEMD="/etc/systemd/system/automatico-db@.service"

if [[ -z "$RUN_JOB_ID" ]]; then
  # Guarda toda la configuración necesaria para que el ciclo se pueda
  # reanudar después de un reinicio sin volver a preguntar nada.
  {
    echo "NOMBRE=$(printf '%q' "$NOMBRE")"
    echo "PGHOST=$(printf '%q' "$PGHOST")"
    echo "PGPORT=$(printf '%q' "$PGPORT")"
    echo "PGUSER=$(printf '%q' "$PGUSER")"
    echo "PGPASSWORD=$(printf '%q' "$PGPASSWORD")"
    echo "ACCION=$(printf '%q' "$ACCION")"
    echo "PGDATABASE=$(printf '%q' "$PGDATABASE")"
    if [[ "$ACCION" -eq 0 ]]; then
      echo "TARGET=$(printf '%q' "$TARGET")"
    else
      echo "DUMPFILE=$(printf '%q' "$DUMPFILE")"
    fi
    echo "MODO=$(printf '%q' "$MODO")"
    if [[ "$MODO" == "intervalo" ]]; then
      echo "INTERVALO_SEG=$(printf '%q' "$INTERVALO_SEG")"
    else
      echo "HORA=$(printf '%q' "$HORA")"
    fi
    echo "PROGRAMACION_TXT=$(printf '%q' "$PROGRAMACION_TXT")"
    echo "ACCION_TXT=$(printf '%q' "$ACCION_TXT")"
  } > "$JOB_FILE"
  chmod 600 "$JOB_FILE"

  # Unidad systemd "template": una instancia por cada ciclo armado
  # (automatico-db@<JOB_ID>.service), para que Ubuntu la levante sola
  # al arrancar, sin depender de la terminal ni de & / disown.
  CONTENIDO_UNIDAD="$(cat <<EOF
[Unit]
Description=Servisofts automatico.sh - tarea %i
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

  sudo systemctl enable --now "automatico-db@${JOB_ID}.service"

  echo -e "${GREEN}✔ Ciclo persistente activado${RESET} (tarea $JOB_ID)."
  echo "Log de las próximas ejecuciones: $LOG_FILE"
  echo "Sigue solo aunque cierres la terminal o reinicies Ubuntu."
  echo "Ya podés usar esta terminal para otra cosa, por ejemplo correr $0 de nuevo para armar otro ciclo."
  echo "Usá stop_automatico.sh para ver o detener las tareas automáticas activas."

  exit 0
fi

# A partir de acá solo se ejecuta cuando nos invoca systemd
# (automatico-db@<JOB_ID>.service), tanto en el arranque normal del
# ciclo como al reanudarlo después de un reinicio.
exec >>"$LOG_FILE" 2>&1 </dev/null

trap 'rm -f "$ESTADO_FILE"' EXIT

cat > "$ESTADO_FILE" <<EOF
JOB_ID=$(printf '%q' "$JOB_ID")
TIPO=db-systemd
SERVIDOR=$(printf '%q' "$NOMBRE")
HOST=$(printf '%q' "$PGHOST")
PUERTO=$(printf '%q' "$PGPORT")
ACCION=$(printf '%q' "$ACCION_TXT")
INTERVALO=$(printf '%q' "$PROGRAMACION_TXT")
INICIO=$(printf '%q' "$(date '+%Y-%m-%d %H:%M:%S')")
EOF

while true; do
  sleep "$(segundos_hasta_proxima)"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ejecutando..."
  if [[ "$ACCION" -eq 0 ]]; then
    hacer_backup
  else
    hacer_restore
  fi
  proxima=$(date -d "@$(( $(date +%s) + $(segundos_hasta_proxima) ))" '+%Y-%m-%d %H:%M:%S')
  echo "✔ Listo. Próxima ejecución: $proxima ($PROGRAMACION_TXT)"
done
