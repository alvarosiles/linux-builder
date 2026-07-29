#!/bin/bash
# Muestra en una tabla todos los alias SSH configurados en ~/.ssh/config
# (los que deja configurar_ssh_alias.sh), con host, usuario y puerto, y
# permite eliminar uno existente o crear uno nuevo desde el mismo menú.

set -e

trap 'tput cnorm 2>/dev/null || true; echo; echo "Cancelado (Ctrl+C)."; exit 130' INT

CONFIG_FILE=~/.ssh/config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURAR_SCRIPT="$SCRIPT_DIR/configurar_ssh_alias.sh"

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NARANJA='\033[38;5;208m'
RESET='\033[0m'

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Uso: $0"
    echo
    echo "Lista en una tabla los alias SSH definidos en $CONFIG_FILE"
    echo "(alias, host, usuario y puerto) y deja eliminar uno o crear uno nuevo."
    exit 0
fi

touch "$CONFIG_FILE"

# Menú de flechas genérico (mismo que usa configurar_ssh_alias.sh).
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

# Lee $CONFIG_FILE y llena los arrays globales ALIASES_ARR / DESTINO_ARR /
# USUARIO_ARR / PUERTO_ARR, uno por cada bloque "Host" (se ignora "Host *").
parsear_config() {
    ALIASES_ARR=(); DESTINO_ARR=(); USUARIO_ARR=(); PUERTO_ARR=()
    local alias="" destino="" usuario="" puerto=""

    guardar_bloque() {
        [[ -z "$alias" ]] && return
        ALIASES_ARR+=("$alias")
        DESTINO_ARR+=("${destino:--}")
        USUARIO_ARR+=("${usuario:--}")
        PUERTO_ARR+=("${puerto:-22}")
    }

    while IFS= read -r RAW || [[ -n "$RAW" ]]; do
        local L
        L="$(echo "$RAW" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [[ -z "$L" || "$L" == \#* ]] && continue

        if [[ "$L" =~ ^Host[[:space:]]+(.+)$ ]]; then
            guardar_bloque
            alias="${BASH_REMATCH[1]}"
            [[ "$alias" == "*" ]] && alias=""
            destino=""; usuario=""; puerto=""
        elif [[ "$L" =~ ^HostName[[:space:]]+(.+)$ ]]; then
            destino="${BASH_REMATCH[1]}"
        elif [[ "$L" =~ ^User[[:space:]]+(.+)$ ]]; then
            usuario="${BASH_REMATCH[1]}"
        elif [[ "$L" =~ ^Port[[:space:]]+(.+)$ ]]; then
            puerto="${BASH_REMATCH[1]}"
        fi
    done < "$CONFIG_FILE"
    guardar_bloque
}

mostrar_tabla() {
    local BARRA="──────────────────────────────────────────────────────────────────"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║                ${YELLOW}ALIAS SSH CONFIGURADOS${RESET}                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ ${#ALIASES_ARR[@]} -eq 0 ]]; then
        echo " (todavía no hay alias configurados)"
        echo ""
        return
    fi

    printf " %-22s %-18s %-14s %6s\n" "ALIAS" "HOST" "USUARIO" "PUERTO"
    echo "$BARRA"
    for i in "${!ALIASES_ARR[@]}"; do
        printf " %-22s %-18s %-14s %6s\n" "ss ${ALIASES_ARR[$i]}" "${DESTINO_ARR[$i]}" "${USUARIO_ARR[$i]}" "${PUERTO_ARR[$i]}"
    done
    echo "$BARRA"
    echo ""
    echo -e "${GREEN}Total: ${#ALIASES_ARR[@]} alias configurados en ${CONFIG_FILE}${RESET}"
}

# Borra del archivo el bloque "Host <alias exacto>" en el índice dado.
eliminar_alias() {
    local idx="$1"
    local target="Host ${ALIASES_ARR[$idx]}"
    awk -v target="$target" '
        /^Host / {
            skip = ($0 == target)
            if (skip) next
        }
        skip && /^$/ { skip = 0; next }
        skip { next }
        { print }
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

while true; do
    parsear_config
    mostrar_tabla
    echo ""

    OPCIONES=("Eliminar un alias" "Crear uno nuevo" "Salir")
    ACCION=$(elegir_opcion "¿Qué querés hacer? (↑/↓ y Enter):" "" "${OPCIONES[@]}")
    echo

    case "$ACCION" in
        0)
            if [[ ${#ALIASES_ARR[@]} -eq 0 ]]; then
                echo "No hay alias para eliminar."
                echo
                continue
            fi
            IDX=$(elegir_opcion "Seleccioná el alias a eliminar (↑/↓ y Enter):" "" "${ALIASES_ARR[@]}")
            echo
            read -rp "¿Eliminar 'ss ${ALIASES_ARR[$IDX]}' (${DESTINO_ARR[$IDX]})? (s/n): " CONFIRMAR
            if [[ "$CONFIRMAR" == "s" || "$CONFIRMAR" == "S" ]]; then
                eliminar_alias "$IDX"
                echo -e "${GREEN}✔ Alias eliminado.${RESET}"
            else
                echo "Cancelado."
            fi
            echo
            ;;
        1)
            "$CONFIGURAR_SCRIPT"
            echo
            ;;
        2)
            exit 0
            ;;
    esac
done
