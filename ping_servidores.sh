#!/bin/bash
# Version anterior del dashboard: solo monitoreo (ping + estado/latencia),
# sin logica de encendido y sin source de servidores_config.sh. Sirve de
# referencia o para un cron que solo necesite chequear estado sin interaccion.

export LC_NUMERIC=C

declare -A servidores=(
  ["empresa"]="192.168.5.29"
  ["servicios"]="192.168.5.1"
  ["roles"]="192.168.5.16"
  ["usuario"]="192.168.5.2"
  ["facturacion"]="192.168.5.28"
  ["spdf"]="192.168.5.46"
  ["drive"]="192.168.5.17"
  ["notification"]="192.168.5.33"
  ["chat"]="192.168.5.9"
  ["calistenia"]="192.168.5.18"
  ["geolocation"]="192.168.5.5"
  ["proyecto"]="192.168.5.14"
  ["serp"]="192.168.5.48"
  ["caja"]="192.168.5.45"
  ["compra-venta"]="192.168.5.41"
  ["crm"]="192.168.5.51"
  ["inventario"]="192.168.5.39"
  ["contabilidad"]="192.168.5.11"
  
  ["sqr"]="192.168.5.34"
  ["zkteco"]="192.168.5.32"


  
  ["nginx"]="192.168.2.3"
  ["wireguard"]="192.168.2.4"


)

grupos_nombres=("CORE SERVICES" "PLATAFORMA SERVICES" "CALISTENIA BOLIVIA" "SISTEMA EMPRESARIAL")
grupos_servidores=(
  "nginx wireguard"
  "empresa servicios roles usuario"
  "facturacion spdf drive notification chat"
  "calistenia geolocation proyecto sqr zkteco"
  "serp caja compra-venta crm inventario contabilidad"
)

online=0
offline=0
alertas=()

LINEA="────────────────────────────────────────────────────────────"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              MONITOR DE SERVICIOS - RED INTERNA            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
printf " %-22s %-15s %-14s %8s\n" "SERVICIO" "IP" "ESTADO" "LATENCIA"
echo "$LINEA"

for i in "${!grupos_nombres[@]}"; do
  echo ""
  echo " ${grupos_nombres[$i]}"
  echo "$LINEA"

  for nombre in ${grupos_servidores[$i]}; do
    ip="${servidores[$nombre]}"
    resultado=$(ping -c 1 -W 1 "$ip" 2>/dev/null)

    if [ $? -eq 0 ]; then
      latencia_ms=$(echo "$resultado" | grep -oP 'time=\K[0-9.]+')
      printf -v latencia "%.0f ms" "$latencia_ms"
      estado="🟢 ONLINE"
      online=$((online + 1))
    else
      latencia="---"
      estado="🔴 OFFLINE"
      offline=$((offline + 1))
      alertas+=("$nombre ($ip) no responde")
    fi

    printf " %-22s %-15s %-14s %8s\n" "$nombre" "$ip" "$estado" "$latencia"
  done
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo " RESUMEN DEL SISTEMA"
echo ""

total=$((online + offline))
disponibilidad=$(awk -v o="$online" -v t="$total" 'BEGIN { printf "%.1f", (t > 0 ? o / t * 100 : 0) }')

printf " 🟢 SERVICIOS ACTIVOS  : %d\n" "$online"
printf " 🔴 SERVICIOS CAÍDOS   : %d\n" "$offline"
printf " 📊 DISPONIBILIDAD     : %s%%\n" "$disponibilidad"

if [ "${#alertas[@]}" -gt 0 ]; then
  echo ""
  echo " ⚠️  ALERTAS:"
  for alerta in "${alertas[@]}"; do
    echo "    - $alerta"
  done
fi

echo ""
printf " ⏱  Última actualización : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf " 🔄 Próxima revisión     : %s\n" "$(date -d '+5 minutes' '+%H:%M:%S')"
echo "════════════════════════════════════════════════════════════"
