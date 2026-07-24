#!/bin/bash
# Pide el nombre de un servicio, lo apaga y lo vuelve a encender
# (reinicio, sin pasar por el dashboard).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/servidores_config.sh"

read -r -p "Nombre del servidor a apagar: " nombre

if [ -z "${carpetas[$nombre]}" ]; then
  echo "No conozco la carpeta remota de '$nombre'. Servicios disponibles:"
  printf '  %s\n' "${!carpetas[@]}" | sort
  exit 1
fi

echo "Apagando $nombre..."
"$DIR/${ctl_script[$nombre]:-servidor_ctl.sh}" "${carpetas[$nombre]}" down "${hosts[$nombre]:-192.168.2.2}" "${base_dirs[$nombre]:-v2}" "${modos[$nombre]:-simple}"

echo "Volviendo a encender $nombre..."
"$DIR/${ctl_script[$nombre]:-servidor_ctl.sh}" "${carpetas[$nombre]}" up "${hosts[$nombre]:-192.168.2.2}" "${base_dirs[$nombre]:-v2}" "${modos[$nombre]:-simple}"
