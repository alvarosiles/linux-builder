#!/usr/bin/env bash
### 🎯 Visualización log de facturación
#
# Se conecta por SSH al servidor de facturación, levanta el stack con
# ./servisofts.sh up (respondiendo solo el menú y la contraseña) y deja
# el log de los contenedores pegado en la terminal en vivo.
set -euo pipefail

usage() {
  cat <<EOF
Uso: $0

Se conecta por SSH al servidor de facturación (192.168.2.5), entra a
servicios/facturacion y corre ./servisofts.sh up, respondiendo solo
automáticamente la opción "1" y la contraseña que pide ese script.
Se queda pegado mostrando el log en vivo (docker compose attach):
Ctrl+C para salir.

Opciones:
  -h, --help    Mostrar esta ayuda
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Este script necesita 'sshpass' (instalalo con: sudo apt install sshpass)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENCIALES="$SCRIPT_DIR/credenciales.sh"
if [[ ! -f "$CREDENCIALES" ]]; then
  echo "Falta $CREDENCIALES (con SSH_USER y PASS). Creá ese archivo primero." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CREDENCIALES"

HOST="192.168.2.5"

echo "Conectando a $SSH_USER@$HOST..."
echo

# El script remoto (servisofts.sh up) muestra un menú y después pide
# contraseña; se lo respondemos por stdin sin intervención manual.
printf '1\n%s\n' "$PASS" | sshpass -p "$PASS" ssh -tt \
  -o StrictHostKeyChecking=no \
  "$SSH_USER@$HOST" \
  'cd servicios/facturacion && ./servisofts.sh up'
