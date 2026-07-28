#!/usr/bin/env bash
### 🗄️ Script interactivo de backup/restore por servidor
#
# Muestra un menú con los servidores/bases conocidos, se conecta al que
# elijas, lista sus bases de datos y te deja hacer un backup o restaurar
# un dump, todo con menús de flechas dentro de la misma terminal.
set -euo pipefail

usage() {
  cat <<EOF
Uso: $0

Muestra un menú (flechas ↑↓ + Enter) con los servidores/bases de
datos conocidos, lista las bases de datos disponibles en el que
elijas y te deja hacer un backup de la que selecciones. Todo dentro
de la misma terminal, sin ventanas de diálogo.

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
  echo "Falta $CREDENCIALES (con PGUSER y PGPASSWORD). Creá ese archivo primero." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CREDENCIALES"
PGUSER_DEFAULT="$PGUSER"
PGPASSWORD_DEFAULT="$PGPASSWORD"

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
RESET='\033[0m'

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

LINEAS=()
for i in "${!BASES[@]}"; do
  IFS='|' read -r NOMBRE HOST PUERTO DB <<< "${BASES[$i]}"
  LINEAS+=("$(printf '%-14s %s' "$NOMBRE" "$HOST:$PUERTO")")
done

ENCABEZADO=$(printf '%-14s %s' "server" "ip")
OPCION=$(elegir_opcion "lista de servidores" "$ENCABEZADO" "${LINEAS[@]}")
echo

IFS='|' read -r NOMBRE PGHOST PGPORT _ <<< "${BASES[$OPCION]}"

read -rp "Usuario [$PGUSER_DEFAULT]: " PGUSER
PGUSER="${PGUSER:-$PGUSER_DEFAULT}"
PGUSER="$(resolver_atajo_p "$PGUSER" "$PGUSER_DEFAULT")"

read -rsp "Contraseña [Enter = la de siempre]: " PGPASSWORD
echo
PGPASSWORD="${PGPASSWORD:-$PGPASSWORD_DEFAULT}"
PGPASSWORD="$(resolver_atajo_p "$PGPASSWORD" "$PGPASSWORD_DEFAULT")"
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

if [[ "$ACCION" -eq 0 ]]; then
  DBOPCION=$(elegir_opcion "Seleccioná la base de datos para backup (↑/↓ y Enter):" "" "${DBS[@]}")
  echo

  PGDATABASE="${DBS[$DBOPCION]}"

  read -rp "Directorio destino [.]: " TARGET
  TARGET="${TARGET:-.}"
  mkdir -p "$TARGET"

  TS=$(date +%Y%m%d%H%M%S)
  OUTFILE="$TARGET/${PGDATABASE}-${TS}.dump"

  echo
  echo "Generando backup de '$PGDATABASE'..."
  echo

  TOTAL_TABLAS=$(psql \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --tuples-only \
    --no-align \
    --pset=pager=off \
    --command="SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema');")

  ANCHO=30

  barra_progreso() {
    local porc=$1
    local llenas=$(( porc * ANCHO / 100 ))
    local vacias=$(( ANCHO - llenas ))
    printf '['
    [[ $llenas -gt 0 ]] && printf '%0.s#' $(seq 1 "$llenas")
    [[ $vacias -gt 0 ]] && printf '%0.s.' $(seq 1 "$vacias")
    printf '] %3d%% (%d/%d tablas)' "$porc" "$PROCESADAS" "$TOTAL_TABLAS"
  }

  pg_dump \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --format=custom \
    --file="$OUTFILE" \
    --verbose \
    "$PGDATABASE" 2>&1 >/dev/null | {
      PROCESADAS=0
      printf '\r%s' "$(barra_progreso 0)"
      while IFS= read -r LINEA; do
        if [[ "$LINEA" == *"dumping contents of table"* ]]; then
          PROCESADAS=$((PROCESADAS + 1))
          if [[ "$TOTAL_TABLAS" -gt 0 ]]; then
            PORC=$((PROCESADAS * 100 / TOTAL_TABLAS))
          else
            PORC=100
          fi
          [[ $PORC -gt 100 ]] && PORC=100
          printf '\r%s' "$(barra_progreso "$PORC")"
        fi
      done
      printf '\r%s\n' "$(PROCESADAS=$TOTAL_TABLAS barra_progreso 100)"
    }

  echo "Backup creado: $OUTFILE"
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
fi

exit 0
