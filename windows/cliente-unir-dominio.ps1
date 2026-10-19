#Requires -RunAsAdministrator
param(
    [string]$NombreEquipo = 'pc-cli01'
)
$ErrorActionPreference = 'Stop'
$dc = '192.168.60.80'

Write-Host '[1/3] Adaptadores NAT y LAB con IP del laboratorio'
foreach ($nombre in 'NAT', 'LAB') {
    if (-not (Get-NetAdapter -Name $nombre -ErrorAction SilentlyContinue)) {
        throw "Falta el adaptador $nombre. Renómbralo antes con Rename-NetAdapter comparando la MAC con VirtualBox."
    }
}
$ip = (Get-NetIPAddress -InterfaceAlias 'LAB' -AddressFamily IPv4).IPAddress
if ($ip -notlike '192.168.60.*') {
    throw "LAB tiene la IP $ip. Revisa el DHCP de srv-dc01 antes de unir el equipo."
}

Write-Host "[2/3] La NAT también pregunta al DNS del dominio ($dc)"
Set-DnsClientServerAddress -InterfaceAlias 'NAT' -ServerAddresses $dc
Set-DnsClient -InterfaceAlias 'NAT' -RegisterThisConnectionsAddress $false
Clear-DnsClientCache
if (-not (Resolve-DnsName -Name '_ldap._tcp.dc._msdcs.lab.internal' -Type SRV -DnsOnly -ErrorAction SilentlyContinue)) {
    throw 'El DNS no devuelve el registro SRV del controlador de dominio. Revisa el DNS antes de seguir.'
}

Write-Host "[3/3] Unión a lab.internal como $NombreEquipo. El equipo se reinicia al terminar"
$credencial = Get-Credential -UserName 'LAB\Administrador' -Message 'Cuenta del dominio que puede unir equipos'
if ($env:COMPUTERNAME -ne $NombreEquipo) {
    Add-Computer -DomainName 'lab.internal' -NewName $NombreEquipo -Credential $credencial -Restart -Force
} else {
    Add-Computer -DomainName 'lab.internal' -Credential $credencial -Restart -Force
}

# Opciones configuradas:
# ----------------------
# Get-NetAdapter NAT/LAB -> los adaptadores ya tienen que estar renombrados
# -notlike 192.168.60.* -> sin IP del DHCP del dominio no tiene sentido seguir
# DNS de NAT = 192.168.60.80 -> el 10.0.2.3 de VirtualBox no conoce lab.internal
# RegisterThisConnectionsAddress $false -> la 10.0.2.15 del cliente no se registra en DNS
# Clear-DnsClientCache -> borra las respuestas malas que tenga guardadas
# Resolve-DnsName SRV _ldap._tcp.dc._msdcs -> comprueba que el cliente encuentra el DC
# Get-Credential LAB\Administrador -> pide la contraseña en una ventana; no queda escrita
# Add-Computer -NewName -> cambia el nombre y une al dominio en un solo reinicio
# -Restart -Force -> reinicia sin preguntar al terminar