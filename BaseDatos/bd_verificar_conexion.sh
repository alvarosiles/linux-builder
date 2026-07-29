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

exit 0
