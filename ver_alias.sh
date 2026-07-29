#!/bin/bash
# Muestra en una tabla todos los alias SSH configurados en ~/.ssh/config
# (los que deja configurar_ssh_alias.sh), con host, usuario y puerto.

set -e

CONFIG_FILE=~/.ssh/config

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Uso: $0"
    echo
    echo "Lista en una tabla los alias SSH definidos en $CONFIG_FILE"
    echo "(alias, host, usuario y puerto)."
    exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "No existe $CONFIG_FILE, todavía no hay alias configurados." >&2
    exit 1
fi

BARRA="──────────────────────────────────────────────────────────────────"

echo "╔════════════════════════════════════════════════════════════════╗"
echo -e "║                ${YELLOW}ALIAS SSH CONFIGURADOS${RESET}                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
printf " %-22s %-18s %-14s %6s\n" "ALIAS" "HOST" "USUARIO" "PUERTO"
echo "$BARRA"

ALIAS="" DESTINO="" USUARIO="" PUERTO="" TOTAL=0

imprimir_bloque() {
    [[ -z "$ALIAS" ]] && return
    printf " %-22s %-18s %-14s %6s\n" "ssh $ALIAS" "${DESTINO:--}" "${USUARIO:--}" "${PUERTO:-22}"
    TOTAL=$((TOTAL + 1))
}

while IFS= read -r RAW || [[ -n "$RAW" ]]; do
    L="$(echo "$RAW" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$L" || "$L" == \#* ]] && continue

    if [[ "$L" =~ ^Host[[:space:]]+(.+)$ ]]; then
        imprimir_bloque
        ALIAS="${BASH_REMATCH[1]}"
        [[ "$ALIAS" == "*" ]] && ALIAS=""
        DESTINO=""; USUARIO=""; PUERTO=""
    elif [[ "$L" =~ ^HostName[[:space:]]+(.+)$ ]]; then
        DESTINO="${BASH_REMATCH[1]}"
    elif [[ "$L" =~ ^User[[:space:]]+(.+)$ ]]; then
        USUARIO="${BASH_REMATCH[1]}"
    elif [[ "$L" =~ ^Port[[:space:]]+(.+)$ ]]; then
        PUERTO="${BASH_REMATCH[1]}"
    fi
done < "$CONFIG_FILE"
imprimir_bloque

echo "$BARRA"
echo ""
echo -e "${GREEN}Total: ${TOTAL} alias configurados en ${CONFIG_FILE}${RESET}"
