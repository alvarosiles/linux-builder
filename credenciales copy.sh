#!/usr/bin/env bash
# 🎯 🎯 🎯 Credenciales compartidas para los scripts de este repo. No se sube a
# git (ver .gitignore) porque tiene contraseñas y un webhook en texto plano.

# SSH (ver_log_facturacion.sh)
SSH_USER="servisofts"
PASS="servisofts"

# Postgres (scripts de BaseDatos/): valores por defecto que se ofrecen
# en los prompts de usuario/contraseña, o se usan directo en los
# scripts no interactivos (backup_todas.sh).
PGUSER="postgres"
PGPASSWORD="postgres"

# Discord (notificaciones de backup/restore)
WEBHOOK_URL="https://discord.com/api/webhooks/1530357203590971483/HdNVfftTH-qb9HoCsX5pTuUpgODT74VjoxzZrJSqDeuceiyN4Ozri14yMX0_7ZjYtW4F"

# Servidores/bases de datos de Servisofts (scripts bd_backup_*.sh).
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

# Atajo para los prompts de usuario/contraseña: si escribís "p" en vez
# del valor completo, se usa el default (PGUSER_DEFAULT/PGPASSWORD_DEFAULT).
# Vive acá y no en los scripts porque este archivo no se sube a git.
resolver_atajo_p() {
  local valor="$1" default="$2"
  [[ "$valor" == "p" ]] && valor="$default"
  echo "$valor"
}
