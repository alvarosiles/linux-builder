#!/bin/bash
# Configura acceso SSH sin contraseña a un servidor y crea un alias
# para poder conectarse simplemente con: ssh <alias>

set -e

# Ctrl+C corta todo de inmediato y deja el cursor visible si quedó
# oculto por un menú.
trap 'tput cnorm 2>/dev/null || true; echo; echo "Cancelado (Ctrl+C)."; exit 130' INT

REMOTE_USER_DEFAULT="servisofts"
CONFIG_FILE=~/.ssh/config
HOSTS_CONOCIDOS=("192.168.2.1" "192.168.2.2" "192.168.2.5")

touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NARANJA='\033[38;5;208m'
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
      elif [[ -n "${ELEGIR_NARANJA_IDX:-}" && $i -eq $ELEGIR_NARANJA_IDX ]]; then
        texto="  ${items[$i]}"
        echo -e "${NARANJA}${texto:0:$ancho}${RESET}"
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

LINEAS=("${HOSTS_CONOCIDOS[@]}")
LINEAS+=("Registrar uno nuevo")
IDX_NUEVO=${#HOSTS_CONOCIDOS[@]}

ELEGIR_NARANJA_IDX="$IDX_NUEVO"
OPCION=$(elegir_opcion "¿Qué host desea configurar? (↑/↓ y Enter):" "" "${LINEAS[@]}")
unset ELEGIR_NARANJA_IDX
echo

if [[ "$OPCION" -eq "$IDX_NUEVO" ]]; then
    read -rp "Ingrese la IP del nuevo host: " REMOTE_HOST
else
    REMOTE_HOST="${HOSTS_CONOCIDOS[$OPCION]}"
fi

read -rp "Usuario remoto [${REMOTE_USER_DEFAULT}]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-$REMOTE_USER_DEFAULT}

# Alias sugerido a partir de los dos últimos octetos, ej. 192.168.2.5 -> 2.5
ALIAS_SUGERIDO=$(echo "$REMOTE_HOST" | awk -F. '{print $3"."$4}')
read -rp "Alias para conectarse con 'ssh <alias>' [${ALIAS_SUGERIDO}]: " ALIAS
ALIAS=${ALIAS:-$ALIAS_SUGERIDO}

# 1. Generar par de llaves SSH si no existe ninguna
if ! ls ~/.ssh/id_*.pub >/dev/null 2>&1; then
    echo "No se encontró ninguna llave SSH, generando una nueva..."
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi

# 2. Copiar la llave pública al servidor remoto (pedirá la contraseña una sola vez)
echo "Copiando llave pública a ${REMOTE_USER}@${REMOTE_HOST}..."
ssh-copy-id "${REMOTE_USER}@${REMOTE_HOST}"

# 3. Quitar un bloque anterior con el mismo alias (si existe) y agregar el nuevo
if grep -q "^Host ${ALIAS}$" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "/^Host ${ALIAS}$/,/^$/d" "$CONFIG_FILE"
fi

{
    echo ""
    echo "Host ${ALIAS}"
    echo "    HostName ${REMOTE_HOST}"
    echo "    User ${REMOTE_USER}"
} >> "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✔ Listo, ya se creó el alias '${ALIAS}'.${RESET}"
echo "Ahora puede conectarse simplemente escribiendo: ssh ${ALIAS}"
