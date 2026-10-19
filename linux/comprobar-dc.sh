#!/usr/bin/env bash
set -euo pipefail

DC="${1:-192.168.60.80}"
DOMINIO=lab.internal
FALLOS=0

if ! command -v dig > /dev/null; then
  echo "ERROR: falta dig. Instálalo con: sudo apt install -y bind9-dnsutils" >&2
  exit 1
fi

comprobar() {
  local descripcion="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "[OK]    ${descripcion}"
  else
    echo "[FALLO] ${descripcion}"
    FALLOS=$((FALLOS + 1))
  fi
}

resuelve_a() {
  [[ "$(dig +short @"$DC" "$1" A | tail -n 1)" == "$2" ]]
}

resuelve_cname() {
  [[ "$(dig +short @"$DC" "$1" CNAME)" == "$2." ]]
}

resuelve_ptr() {
  [[ "$(dig +short @"$DC" -x "$1")" == "$2." ]]
}

anuncia_dc() {
  dig +short @"$DC" "_ldap._tcp.dc._msdcs.${DOMINIO}" SRV | grep -q "srv-dc01.${DOMINIO}."
}

puerto_abierto() {
  timeout 3 bash -c "echo > /dev/tcp/${DC}/$1"
}

latencia_ms() {
  ping -c 3 -q "$DC" | awk -F/ '/^rtt/ {print $5}'
}

comprobar "srv-dc01 resuelve a ${DC}"                    resuelve_a "srv-dc01.${DOMINIO}" "$DC"
comprobar "vm-zabbix resuelve a 192.168.60.62"           resuelve_a "vm-zabbix.${DOMINIO}" 192.168.60.62
comprobar "vm-docker-app resuelve a 192.168.60.60"       resuelve_a "vm-docker-app.${DOMINIO}" 192.168.60.60
comprobar "vm-postgres resuelve a 192.168.60.61"         resuelve_a "vm-postgres.${DOMINIO}" 192.168.60.61
comprobar "zabbix es un alias de vm-zabbix"              resuelve_cname "zabbix.${DOMINIO}" "vm-zabbix.${DOMINIO}"
comprobar "La .62 resuelve en inverso a vm-zabbix"       resuelve_ptr 192.168.60.62 "vm-zabbix.${DOMINIO}"
comprobar "${DC} resuelve en inverso a srv-dc01"         resuelve_ptr "$DC" "srv-dc01.${DOMINIO}"
comprobar "El DNS anuncia srv-dc01 como DC (SRV)"        anuncia_dc
comprobar "Puerto 53 (DNS) abierto"                      puerto_abierto 53
comprobar "Puerto 445 (SMB) abierto"                     puerto_abierto 445
comprobar "Puerto 3389 (RDP) abierto"                    puerto_abierto 3389
comprobar "Puerto 10050 (agente de Zabbix) abierto"      puerto_abierto 10050
echo "Latencia media hasta ${DC}: $(latencia_ms || echo 'sin respuesta') ms"

if [[ "$FALLOS" -eq 0 ]]; then
  echo "Todo correcto."
else
  echo "${FALLOS} comprobaciones han fallado."
  exit 1
fi

# Opciones configuradas:
# ----------------------
# set -euo pipefail -> para en el primer error, variable sin definir o tubería que falla
# DC="${1:-192.168.60.80}" -> la IP del DC es el primer argumento; si falta, la .80
# command -v dig -> dig viene en bind9-dnsutils
# comprobar() -> ejecuta una prueba, escribe [OK] o [FALLO] y cuenta los fallos
# dig +short @"$DC" -> pregunta directamente al DNS del DC y solo da la respuesta
# tail -n 1 -> con un CNAME delante, la última línea es la IP
# "$2." -> dig termina los nombres con un punto
# dig -x -> consulta inversa (PTR)
# _ldap._tcp.dc._msdcs -> el registro SRV que buscan los clientes para encontrar el DC
# /dev/tcp + timeout 3 -> prueba el puerto sin instalar nada; corta si el firewall no contesta
# awk -F/ '/^rtt/ {print $5}' -> la media de la línea rtt min/avg/max de ping
# exit 1 -> termina con error si algo falla