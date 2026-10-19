#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$servidorZabbix = '192.168.60.62'
$url = 'https://cdn.zabbix.com/zabbix/binaries/stable/7.4/latest/zabbix_agent2-7.4-latest-windows-amd64-openssl.msi'
$msi = "$env:TEMP\zabbix_agent2.msi"
$logInstalacion = "$env:TEMP\zabbix_agent2_instalacion.log"

Write-Host '[1/3] Descarga del instalador de Zabbix agent 2 (7.4)'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

Write-Host '[2/3] Instalación desatendida'
$argumentos = "/i `"$msi`" /qn /l*v `"$logInstalacion`" SERVER=$servidorZabbix SERVERACTIVE=$servidorZabbix HOSTNAME=srv-dc01 ENABLEPATH=1 SKIP=fw"
$proceso = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argumentos -Wait -PassThru
if ($proceso.ExitCode -notin 0, 3010) {
    throw "msiexec ha terminado con el código $($proceso.ExitCode). Revisa $logInstalacion"
}

Write-Host "[3/3] Firewall: el 10050 solo para $servidorZabbix"
if (-not (Get-NetFirewallRule -Name 'LAB-ZabbixAgent-In' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'LAB-ZabbixAgent-In' -DisplayName 'LAB - Agente de Zabbix desde vm-zabbix' -Direction Inbound -Protocol TCP -LocalPort 10050 -RemoteAddress $servidorZabbix -Action Allow | Out-Null
}

Get-Service -Name 'Zabbix Agent 2' | Format-List Name, Status, StartType

# Opciones configuradas:
# ----------------------
# 7.4/latest -> último parche de la 7.4, la misma versión que el server
# amd64-openssl.msi -> agente 2 de 64 bits con soporte de cifrado
# Tls12 -> Windows PowerShell 5.1 no usa TLS 1.2 por defecto en todos los casos
# -UseBasicParsing -> descarga sin depender del motor de Internet Explorer
# /qn -> instalación sin ventanas
# /l*v -> log detallado para revisar si falla
# SERVER -> la IP desde la que el server pregunta al agente (comprobaciones pasivas)
# SERVERACTIVE -> a dónde envía el agente las comprobaciones activas
# HOSTNAME=srv-dc01 -> el nombre del host en Zabbix; tiene que coincidir letra a letra
# ENABLEPATH=1 -> zabbix_sender y zabbix_get en el PATH
# SKIP=fw -> no crea su regla abierta a todos; pongo la mía
# -notin 0, 3010 -> 3010 es éxito con reinicio pendiente
# -RemoteAddress 192.168.60.62 -> el 10050 solo responde a vm-zabbix