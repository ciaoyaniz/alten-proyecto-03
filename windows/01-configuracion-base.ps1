#Requires -RunAsAdministrator
param(
    [string]$NombreEquipo = 'srv-dc01',
    [string]$IpLab = '192.168.60.80'
)
$ErrorActionPreference = 'Stop'

Write-Host '[1/6] Adaptadores NAT y LAB'
foreach ($nombre in 'NAT', 'LAB') {
    if (-not (Get-NetAdapter -Name $nombre -ErrorAction SilentlyContinue)) {
        throw "Falta el adaptador $nombre. Renómbralo antes con Rename-NetAdapter comparando la MAC con VirtualBox."
    }
}

Write-Host "[2/6] IP fija $IpLab en LAB sin puerta de enlace"
Set-NetIPInterface -InterfaceAlias 'LAB' -Dhcp Disabled
Get-NetIPAddress -InterfaceAlias 'LAB' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceAlias 'LAB' -IPAddress $IpLab -PrefixLength 24 | Out-Null
Set-DnsClientServerAddress -InterfaceAlias 'LAB' -ResetServerAddresses
Set-DnsClient -InterfaceAlias 'NAT' -RegisterThisConnectionsAddress $false

Write-Host '[3/6] Zona horaria de Madrid'
Set-TimeZone -Id 'Romance Standard Time'

Write-Host '[4/6] Escritorio remoto con NLA y solo desde la red del laboratorio'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1
Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' | Enable-NetFirewallRule -PassThru | Set-NetFirewallRule -RemoteAddress '192.168.60.0/24'

Write-Host '[5/6] Firewall activo y ping desde el laboratorio'
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True
if (-not (Get-NetFirewallRule -Name 'LAB-ICMPv4-In' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'LAB-ICMPv4-In' -DisplayName 'LAB - Ping desde 192.168.60.0/24' -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -RemoteAddress '192.168.60.0/24' -Action Allow | Out-Null
}

Write-Host "[6/6] Nombre del equipo $NombreEquipo"
if ($env:COMPUTERNAME -ne $NombreEquipo) {
    Rename-Computer -NewName $NombreEquipo -Force
    Write-Host "Reinicia con Restart-Computer para que se aplique el nombre $NombreEquipo."
}
Get-NetIPConfiguration -InterfaceAlias 'LAB'

# Opciones configuradas:
# ----------------------
# #Requires -RunAsAdministrator -> no arranca si PowerShell no está abierto como administrador
# param(...) -> nombre e IP con valor por defecto; se pueden cambiar al lanzarlo
# $ErrorActionPreference = 'Stop' -> para en el primer error en vez de seguir
# Get-NetAdapter NAT/LAB -> los adaptadores ya tienen que estar renombrados
# Set-NetIPInterface -Dhcp Disabled -> LAB deja de pedir IP por DHCP
# Remove-NetIPAddress -> borra la 169.254.x.x antes de poner la fija
# New-NetIPAddress sin -DefaultGateway -> la salida a Internet va por NAT; una sola ruta por defecto
# -ResetServerAddresses -> LAB sin DNS hasta el PASO 3
# RegisterThisConnectionsAddress $false -> la IP 10.0.2.15 de NAT no se registra en DNS
# Romance Standard Time -> zona de Madrid con cambio de hora
# fDenyTSConnections 0 -> activa el Escritorio remoto
# UserAuthentication 1 -> NLA; pide usuario y contraseña antes de abrir la sesión
# @FirewallAPI.dll,-28752 -> el grupo de reglas de Escritorio remoto en cualquier idioma
# -RemoteAddress 192.168.60.0/24 -> RDP solo desde la red del laboratorio
# Set-NetFirewallProfile ... True -> firewall encendido en los tres perfiles
# -IcmpType 8 -> deja pasar el ping (echo request) para el bloque 2 y Zabbix
# Rename-Computer sin -Restart -> el reinicio lo hago yo al terminar