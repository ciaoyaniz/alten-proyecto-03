#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$zona = 'lab.internal'
$zonaInversa = '60.168.192.in-addr.arpa'
$equipos = [ordered]@{ 'vm-docker-app' = '192.168.60.60'; 'vm-postgres' = '192.168.60.61'; 'vm-zabbix' = '192.168.60.62' }
$alias = [ordered]@{ 'app' = 'vm-docker-app'; 'bd' = 'vm-postgres'; 'zabbix' = 'vm-zabbix' }

Write-Host "[1/3] Zona inversa $zonaInversa integrada en AD"
if (-not (Get-DnsServerZone -Name $zonaInversa -ErrorAction SilentlyContinue)) {
    Add-DnsServerPrimaryZone -NetworkId '192.168.60.0/24' -ReplicationScope Domain -DynamicUpdate Secure
}

Write-Host '[2/3] Registros A con su PTR de las VM de los proyectos 1 y 2'
foreach ($nombre in $equipos.Keys) {
    if (Get-DnsServerResourceRecord -ZoneName $zona -Name $nombre -RRType A -ErrorAction SilentlyContinue) {
        Write-Host "[YA EXISTE] $nombre"
    } else {
        Add-DnsServerResourceRecordA -ZoneName $zona -Name $nombre -IPv4Address $equipos[$nombre] -CreatePtr
        Write-Host "[CREADO] $nombre -> $($equipos[$nombre])"
    }
}

Write-Host '[3/3] Alias CNAME'
foreach ($nombre in $alias.Keys) {
    if (Get-DnsServerResourceRecord -ZoneName $zona -Name $nombre -RRType CName -ErrorAction SilentlyContinue) {
        Write-Host "[YA EXISTE] $nombre"
    } else {
        Add-DnsServerResourceRecordCName -ZoneName $zona -Name $nombre -HostNameAlias "$($alias[$nombre]).$zona"
        Write-Host "[CREADO] $nombre -> $($alias[$nombre]).$zona"
    }
}

ipconfig /registerdns | Out-Null
Get-DnsServerResourceRecord -ZoneName $zonaInversa -RRType Ptr | Format-Table HostName, RecordData -AutoSize

# Opciones configuradas:
# ----------------------
# [ordered]@{...} -> tabla nombre-IP; se recorre en el mismo orden
# 60.168.192.in-addr.arpa -> la red 192.168.60 escrita al revés
# -NetworkId 192.168.60.0/24 -> crea la zona inversa sin escribir su nombre
# -ReplicationScope Domain -> la zona vive en AD y se replica con el dominio
# -DynamicUpdate Secure -> solo los equipos del dominio actualizan sus registros
# Get-...ResourceRecord antes de crear -> el script se puede lanzar dos veces
# -CreatePtr -> crea también el PTR en la zona inversa
# CNAME app, bd y zabbix -> alias que apuntan al nombre completo de cada VM
# ipconfig /registerdns -> el DC registra su propio PTR en la zona nueva