#!/usr/bin/env bash
### 🎯 Script de control y administración de procesos en segundo plano
#
# Script encargado de supervisar y detener procesos en segundo plano,
# mediante el manejo de PIDs y la integración con systemd.
set -euo pipefail

usage() {
  cat <<EOF
Uso: $0

Muestra las tareas automáticas (automatico.sh) que están corriendo
actualmente y te deja elegir cuál detener, con menú de flechas
↑↓ + Enter.

Opciones:
  -h, --help    Mostrar esta ayuda
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RESET='\033[0m'

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carpetas de estado de los distintos scripts que corren en segundo plano.
ESTADO_DIRS=(
  "$SCRIPT_DIR/.automatico_estado"
  "$SCRIPT_DIR/../.saludo_estado"
)

TIPOS=()
CLAVES=()
ARCHIVOS=()
LINEAS=()

for ESTADO_DIR in "${ESTADO_DIRS[@]}"; do
  [[ -d "$ESTADO_DIR" ]] || continue

  for archivo in "$ESTADO_DIR"/*.info; do
    [[ -e "$archivo" ]] || continue

    CLAVE="$(basename "$archivo" .info)"

    TIPO=""; SERVIDOR=""; HOST=""; PUERTO=""; ACCION=""; INTERVALO=""; INICIO=""; JOB_ID=""
    # shellcheck source=/dev/null
    source "$archivo"

    if [[ "$TIPO" == "db-systemd" ]]; then
      if ! systemctl is-active --quiet "automatico-db@${JOB_ID}.service" 2>/dev/null; then
        # la tarea ya no está activa en systemd: era un archivo de estado viejo
        rm -f "$archivo"
        continue
      fi
      CLAVE="$JOB_ID"
      LINEA="$(printf 'JOB %-16s %-14s %-21s %s' "$JOB_ID" "$SERVIDOR" "$HOST:$PUERTO" "$ACCION - $INTERVALO (desde $INICIO)")"
    elif [[ "$TIPO" == "db-todas-systemd" ]]; then
      if ! systemctl is-active --quiet "automatico-db-todas@${JOB_ID}.service" 2>/dev/null; then
        # la tarea ya no está activa en systemd: era un archivo de estado viejo
        rm -f "$archivo"
        continue
      fi
      CLAVE="$JOB_ID"
      LINEA="$(printf 'JOB %-16s %-14s %s' "$JOB_ID" "todas-las-bases" "$ACCION - $INTERVALO (desde $INICIO)")"
    else
      if ! kill -0 "$CLAVE" 2>/dev/null; then
        # el proceso ya no existe: era un archivo de estado viejo
        rm -f "$archivo"
        continue
      fi

      case "$TIPO" in
        db)
          LINEA="$(printf 'PID %-7s %-14s %-21s %s' "$CLAVE" "$SERVIDOR" "$HOST:$PUERTO" "$ACCION - $INTERVALO (desde $INICIO)")"
          ;;
        saludo)
          LINEA="$(printf 'PID %-7s %-14s %s' "$CLAVE" "saludo-discord" "hola cada 2 min (desde $INICIO)")"
          ;;
        *)
          LINEA="$(printf 'PID %-7s %s' "$CLAVE" "tarea desconocida")"
          ;;
      esac
    fi

    TIPOS+=("$TIPO")
    CLAVES+=("$CLAVE")
    ARCHIVOS+=("$archivo")
    LINEAS+=("$LINEA")
  done
done

if [[ ${#CLAVES[@]} -eq 0 ]]; then
  echo "No hay tareas automáticas corriendo."
  exit 0
fi

OPCION=$(elegir_opcion "Tareas automáticas corriendo (↑/↓ y Enter para detener):" "" "${LINEAS[@]}")
echo

TIPO_ELEGIDO="${TIPOS[$OPCION]}"
CLAVE_ELEGIDA="${CLAVES[$OPCION]}"
ARCHIVO_ELEGIDO="${ARCHIVOS[$OPCION]}"

read -rp "¿Detener esta tarea? (s/n): " CONFIRMAR
if [[ "$CONFIRMAR" != "s" && "$CONFIRMAR" != "S" ]]; then
  echo "Cancelado."
  exit 0
fi

if [[ "$TIPO_ELEGIDO" == "db-systemd" || "$TIPO_ELEGIDO" == "db-todas-systemd" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$TIPO_ELEGIDO" == "db-todas-systemd" ]]; then
    SERVICIO="automatico-db-todas@${CLAVE_ELEGIDA}.service"
  else
    SERVICIO="automatico-db@${CLAVE_ELEGIDA}.service"
  fi
  sudo systemctl disable --now "$SERVICIO"
  rm -f "$ARCHIVO_ELEGIDO" "$SCRIPT_DIR/.automatico_estado/jobs/${CLAVE_ELEGIDA}.conf"
  echo -e "${GREEN}✔ Tarea $CLAVE_ELEGIDA detenida y desactivada.${RESET}"
else
  kill -TERM "$CLAVE_ELEGIDA" 2>/dev/null || true

  for _ in 1 2 3 4 5; do
    kill -0 "$CLAVE_ELEGIDA" 2>/dev/null || break
    sleep 0.5
  done

  if kill -0 "$CLAVE_ELEGIDA" 2>/dev/null; then
    echo "El proceso no respondió, forzando..."
    kill -KILL "$CLAVE_ELEGIDA" 2>/dev/null || true
  fi

  rm -f "$ARCHIVO_ELEGIDO"

  echo -e "${GREEN}✔ Tarea PID $CLAVE_ELEGIDA detenida.${RESET}"
fi

exit 0
