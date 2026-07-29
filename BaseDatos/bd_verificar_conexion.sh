#!/usr/bin/env bash
### 🔌 Script para verificar conexión con las bases de datos
#
# Prueba la conexión (pg_isready + login real) contra todos los
# servidores/bases conocidos en credenciales.sh, o contra uno elegido
# del menú, y muestra OK/FALLÓ para cada uno. No modifica nada.
set -euo pipefail

trap 'tput cnorm 2>/dev/null || true; echo; echo "Cancelado (Ctrl+C)."; exit 130' INT

usage() {
  cat <<EOF
Uso: $0

Verifica la conexión con las bases de datos conocidas (credenciales.sh):
para cada una hace un pg_isready y un login real (SELECT 1) y muestra
si respondió OK o FALLÓ. Si respondió OK, además lista todas las bases
de datos que existen en ese servidor y, al final, te deja elegir una
de ellas para sacarle un backup (con pg_dump).

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

# En Windows (Git Bash) psql/pg_isready no suelen estar en el PATH.
if ! command -v pg_isready >/dev/null 2>&1 || ! command -v psql >/dev/null 2>&1; then
  for dir in "/c/Program Files/PostgreSQL"/*/bin "/c/Program Files (x86)/PostgreSQL"/*/bin; do
    if [[ -x "$dir/psql.exe" ]]; then
      export PATH="$PATH:$dir"
      break
    fi
  done
fi

if ! command -v pg_isready >/dev/null 2>&1 || ! command -v psql >/dev/null 2>&1; then
  echo "No se encontró pg_isready/psql. Instalá PostgreSQL client o agregá su carpeta bin al PATH." >&2
  exit 1
fi

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# Menú de flechas genérico (igual que en bd_backup_no_programado_individual.sh):
# recibe el prompt, un encabezado opcional y las opciones, devuelve el índice elegido.
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

echo "Verificando conexión con ${#BASES[@]} base(s)..."
echo

EXITOSOS=0
FALLIDOS=0

# Todas las bases de datos reales encontradas en los servidores que
# respondieron OK, para poder elegir una al final y sacarle backup.
ENCONTRADAS_SERVIDOR=()
ENCONTRADAS_HOST=()
ENCONTRADAS_PUERTO=()
ENCONTRADAS_DB=()

for entrada in "${BASES[@]}"; do
  IFS='|' read -r nombre host puerto db <<< "$entrada"
  printf '%-14s %-18s ' "$nombre" "$host:$puerto"

  if ! pg_isready --host="$host" --port="$puerto" --timeout=5 >/dev/null 2>&1; then
    echo -e "${RED}FALLÓ${RESET} (servidor no responde)"
    FALLIDOS=$((FALLIDOS + 1))
    continue
  fi

  if psql \
      --host="$host" \
      --port="$puerto" \
      --username="$PGUSER" \
      --dbname="$db" \
      --tuples-only \
      --no-align \
      --pset=pager=off \
      --command="SELECT 1;" >/dev/null 2>/dev/null; then
    echo -e "${GREEN}OK${RESET}"
    EXITOSOS=$((EXITOSOS + 1))

    bases_del_servidor="$(psql \
      --host="$host" \
      --port="$puerto" \
      --username="$PGUSER" \
      --dbname="$db" \
      --tuples-only \
      --no-align \
      --pset=pager=off \
      --command="SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null)"
    while IFS= read -r nombre_bd; do
      nombre_bd="${nombre_bd%$'\r'}"
      if [[ -n "$nombre_bd" ]]; then
        echo "               - $nombre_bd"
        ENCONTRADAS_SERVIDOR+=("$nombre")
        ENCONTRADAS_HOST+=("$host")
        ENCONTRADAS_PUERTO+=("$puerto")
        ENCONTRADAS_DB+=("$nombre_bd")
      fi
    done <<< "$bases_del_servidor"
  else
    echo -e "${RED}FALLÓ${RESET} (login o base '$db' no accesible)"
    FALLIDOS=$((FALLIDOS + 1))
  fi
done

echo
echo -e "${GREEN}✔ Verificación completa: $EXITOSOS ok, $FALLIDOS con error.${RESET}"

if [[ ${#ENCONTRADAS_DB[@]} -eq 0 ]]; then
  exit 0
fi

SCRIPT_PROGRAMADO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bd_backup_programado_individual.sh"

echo
OPCIONES_BACKUP=("Backup ahora" "Restaurar un backup ahora" "Programar backup" "Programar restauración" "No, gracias")
OPCION_BACKUP=$(elegir_opcion "¿Qué querés hacer con estas bases? (↑/↓ y Enter):" "" "${OPCIONES_BACKUP[@]}")
echo

case "$OPCION_BACKUP" in
  4) exit 0 ;;
  2) exec "$SCRIPT_PROGRAMADO" --accion backup ;;
  3) exec "$SCRIPT_PROGRAMADO" --accion restore ;;
esac

if [[ "$OPCION_BACKUP" -eq 1 ]]; then
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

  LINEAS=()
  for i in "${!ENCONTRADAS_DB[@]}"; do
    LINEAS+=("$(printf '%-14s %-18s %s' "${ENCONTRADAS_SERVIDOR[$i]}" "${ENCONTRADAS_HOST[$i]}:${ENCONTRADAS_PUERTO[$i]}" "${ENCONTRADAS_DB[$i]}")")
  done
  LINEAS+=("$(printf '%-14s %-18s %s' "otra" "-" "escribir el nombre a mano")")
  IDX_OTRA=${#ENCONTRADAS_DB[@]}

  ENCABEZADO=$(printf '%-14s %-18s %s' "server" "host:puerto" "base de datos")
  OPCION=$(elegir_opcion "Seleccioná el servidor/base destino (↑/↓ y Enter):" "$ENCABEZADO" "${LINEAS[@]}")
  echo

  if [[ "$OPCION" -eq "$IDX_OTRA" ]]; then
    read -rp "Host destino: " PGHOST
    read -rp "Puerto destino [5432]: " PGPORT
    PGPORT="${PGPORT:-5432}"
  else
    PGHOST="${ENCONTRADAS_HOST[$OPCION]}"
    PGPORT="${ENCONTRADAS_PUERTO[$OPCION]}"
  fi

  read -rp "Base de datos destino [$SUGERIDA]: " PGDATABASE
  PGDATABASE="${PGDATABASE:-$SUGERIDA}"

  EXISTE="no"
  for db in "${ENCONTRADAS_DB[@]}"; do
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
  echo "Restaurando '$DUMPFILE' en '$PGDATABASE' ($PGHOST:$PGPORT)..."

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

  echo -e "${GREEN}✔ Restauración completada.${RESET}"

  exit 0
fi

LINEAS=()
for i in "${!ENCONTRADAS_DB[@]}"; do
  LINEAS+=("$(printf '%-14s %-18s %s' "${ENCONTRADAS_SERVIDOR[$i]}" "${ENCONTRADAS_HOST[$i]}:${ENCONTRADAS_PUERTO[$i]}" "${ENCONTRADAS_DB[$i]}")")
done

echo
ENCABEZADO=$(printf '%-14s %-18s %s' "server" "host:puerto" "base de datos")
OPCION=$(elegir_opcion "Seleccioná la base de datos para backup (↑/↓ y Enter):" "$ENCABEZADO" "${LINEAS[@]}")
echo

PGHOST="${ENCONTRADAS_HOST[$OPCION]}"
PGPORT="${ENCONTRADAS_PUERTO[$OPCION]}"
PGDATABASE="${ENCONTRADAS_DB[$OPCION]}"

echo
OPCIONES_FILAS=("Primeras 10 filas por tabla" "Primeras 100 filas por tabla" "Toda la data (backup completo)")
OPCION_FILAS=$(elegir_opcion "¿Cuántas filas por tabla querés guardar? (↑/↓ y Enter):" "" "${OPCIONES_FILAS[@]}")
echo

read -rp "Directorio destino [.]: " TARGET
TARGET="${TARGET:-.}"
mkdir -p "$TARGET"

TS=$(date +%Y%m%d%H%M%S)

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

if [[ "$OPCION_FILAS" -eq 2 ]]; then
  OUTFILE="$TARGET/${PGDATABASE}-${TS}.dump"

  echo
  echo "Generando backup completo de '$PGDATABASE' ($PGHOST:$PGPORT)..."
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

  echo -e "${GREEN}✔ Backup creado: $OUTFILE${RESET}"
else
  if [[ "$OPCION_FILAS" -eq 0 ]]; then
    LIMITE=10
  else
    LIMITE=100
  fi

  OUTFILE="$TARGET/${PGDATABASE}-${TS}-primeras${LIMITE}filas.sql"

  echo
  echo "Generando backup de '$PGDATABASE' ($PGHOST:$PGPORT) con las primeras $LIMITE filas por tabla..."
  echo

  # Solo el esquema (estructura); los datos se agregan tabla por tabla abajo.
  pg_dump \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --schema-only \
    --no-owner \
    --file="$OUTFILE" \
    "$PGDATABASE"

  mapfile -t TABLAS < <(psql \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --tuples-only \
    --no-align \
    --pset=pager=off \
    --command="SELECT quote_ident(schemaname) || '.' || quote_ident(tablename) FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1;")

  TOTAL_TABLAS=${#TABLAS[@]}
  PROCESADAS=0
  printf '\r%s' "$(barra_progreso 0)"

  for tabla in "${TABLAS[@]}"; do
    tabla="${tabla%$'\r'}"
    [[ -z "$tabla" ]] && continue

    {
      echo
      echo "COPY $tabla FROM stdin;"
    } >> "$OUTFILE"

    psql \
      --host="$PGHOST" \
      --port="$PGPORT" \
      --username="$PGUSER" \
      --dbname="$PGDATABASE" \
      --tuples-only \
      --no-align \
      --pset=pager=off \
      --command="\\copy (SELECT * FROM $tabla LIMIT $LIMITE) TO STDOUT" | sed $'s/\r$//' >> "$OUTFILE"

    echo '\.' >> "$OUTFILE"

    PROCESADAS=$((PROCESADAS + 1))
    if [[ "$TOTAL_TABLAS" -gt 0 ]]; then
      PORC=$((PROCESADAS * 100 / TOTAL_TABLAS))
    else
      PORC=100
    fi
    printf '\r%s' "$(barra_progreso "$PORC")"
  done
  printf '\r%s\n' "$(barra_progreso 100)"

  echo -e "${GREEN}✔ Backup creado: $OUTFILE${RESET} (solo primeras $LIMITE filas por tabla; restaurar con psql -f, no con pg_restore)"
fi

exit 0
