#!/usr/bin/env bash
### Credenciales y lista de servidores para los scripts de BaseDatos/
#
# Este archivo está en .gitignore: no se sube al repo. Completá los
# valores marcados con TU_... antes de usar los scripts de backup.

PGUSER="postgres"
PGPASSWORD="0"

# Webhook de Discord para la notificación al terminar el backup.
# Dejalo vacío ("") si no querés notificación.
WEBHOOK_URL="TU_WEBHOOK_DISCORD"

# Atajo: si en el prompt de usuario/contraseña escribís "p", se usa el
# valor por defecto pasado como segundo argumento.
resolver_atajo_p() {
  local valor="$1"
  local por_defecto="$2"
  if [[ "$valor" == "p" ]]; then
    echo "$por_defecto"
  else
    echo "$valor"
  fi
}

# Lista de servidores/bases conocidos: nombre|host|puerto|db
# IPs tomadas de ping_servidores.sh; ajustá host/puerto/db según corresponda.
BASES=(
  # "facturacion|192.168.5.28|5432|facturacion"
  "servicios_usuarios|localhost|5432|servicios_usuarios"
  # "spdf|192.168.5.46|5432|spdf"
)
