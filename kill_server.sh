#!/bin/bash
# Selector interactivo de servidores (los mismos de restart_servidores.sh)
# para matarlos a la fuerza cuando quedan colgados ocupando su puerto/IP
# y un "down" normal no alcanza para liberarlos.
#
# Flujo: docker-compose kill (SIGKILL) + docker-compose rm -f del contenedor,
# vía servidor_ctl.sh / servidor_ctl_v2.sh segun corresponda a cada servicio.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/servidores_config.sh"

if ! command -v whiptail &> /dev/null; then
  echo "Falta 'whiptail'. Instalalo con: sudo apt install -y whiptail"
  exit 1
fi

nombres=($(printf '%s\n' "${!servidores[@]}" | sort))

opciones=()
for nombre in "${nombres[@]}"; do
  opciones+=("$nombre" "${servidores[$nombre]}")
done

nombre=$(whiptail --title "KILL SERVER" \
  --menu "Seleccioná el servidor a matar (docker kill + rm -f).\nUsá las flechas y Enter, Esc para salir." \
  24 70 16 \
  "${opciones[@]}" \
  3>&1 1>&2 2>&3)

# Esc / Cancelar
[ -z "$nombre" ] && exit 0

if [ -z "${carpetas[$nombre]}" ]; then
  echo "No conozco la carpeta remota de '$nombre'."
  exit 1
fi

carpeta="${carpetas[$nombre]}"
host="${hosts[$nombre]:-192.168.2.2}"
ctl="${ctl_script[$nombre]:-servidor_ctl.sh}"
base_dir="${base_dirs[$nombre]:-v2}"
modo="${modos[$nombre]:-simple}"

if ! whiptail --title "Confirmar KILL" \
  --yesno "Vas a matar '$nombre' (${servidores[$nombre]}) en $host.\n\nEsto hace docker-compose kill + rm -f del contenedor (forzado).\n\n¿Continuar?" \
  12 60; then
  exit 0
fi

echo "Matando $nombre en $host..."
"$DIR/$ctl" "$carpeta" kill "$host" "$base_dir" "$modo"
