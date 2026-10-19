#Requires -RunAsAdministrator
param(
    [ValidatePattern('^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$')]
    [string]$MacCliente
)
$ErrorActionPreference = 'Stop'
$ambito = '192.168.60.0'
$dc = 'srv-dc01.lab.internal'

Write-Host '[1/5] Rol DHCP'
Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null

Write-Host '[2/5] Grupos de seguridad del DHCP y autorización en AD'
Add-DhcpServerSecurityGroup
Restart-Service -Name DHCPServer
if (-not (Get-DhcpServerInDC | Where-Object { $_.DnsName -eq $dc })) {
    Add-DhcpServerInDC -DnsName $dc -IPAddress 192.168.60.80
}
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name 'ConfigurationState' -Value 2

Write-Host '[3/5] Ámbito de la .100 a la .229 y exclusión de la .100 a la .109'
if (-not (Get-DhcpServerv4Scope -ScopeId $ambito -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Scope -Name 'LAB 192.168.60.0/24' -StartRange 192.168.60.100 -EndRange 192.168.60.229 -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active
}
if (-not (Get-DhcpServerv4ExclusionRange -ScopeId $ambito -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4ExclusionRange -ScopeId $ambito -StartRange 192.168.60.100 -EndRange 192.168.60.109
}

Write-Host '[4/5] Opciones del ámbito: DNS del dominio y sufijo lab.internal'
Set-DhcpServerv4OptionValue -ScopeId $ambito -DnsServer 192.168.60.80 -DnsDomain 'lab.internal'

if ($MacCliente) {
    Write-Host "[5/5] Reserva de la .220 para pc-cli01 ($MacCliente)"
    $reserva = Get-DhcpServerv4Reservation -ScopeId $ambito | Where-Object { $_.IPAddress.IPAddressToString -eq '192.168.60.220' }
    if (-not $reserva) {
        Add-DhcpServerv4Reservation -ScopeId $ambito -IPAddress 192.168.60.220 -ClientId $MacCliente -Name 'pc-cli01' -Description 'Cliente del dominio'
    }
} else {
    Write-Host '[5/5] Sin -MacCliente no creo la reserva todavía'
}

Get-DhcpServerv4Scope -ScopeId $ambito | Format-List Name, State, StartRange, EndRange, LeaseDuration

# Opciones configuradas:
# ----------------------
# -MacCliente opcional -> la primera vez lo lanzo sin MAC para probar la exclusión
# ValidatePattern -> la MAC con guiones (08-00-27-...), como la pide el DHCP
# Install-WindowsFeature DHCP -> el rol y su consola
# Add-DhcpServerSecurityGroup -> crea Administradores de DHCP y Usuarios de DHCP
# Add-DhcpServerInDC -> autoriza el servidor; sin esto no reparte en un dominio
# ConfigurationState = 2 -> quita el aviso amarillo del Administrador del servidor
# .100 a .229 -> fuera quedan las IP fijas .1, .60, .61, .62 y .80
# -LeaseDuration 8.00:00:00 -> concesión de 8 días
# exclusión .100-.109 -> dentro del ámbito pero no se reparte (futuras IP fijas)
# -DnsServer 192.168.60.80 -> opción 006; el cliente pregunta al DC
# -DnsDomain lab.internal -> opción 015; sufijo para resolver nombres cortos
# sin -Router -> la red LAB no tiene puerta de enlace; Internet va por NAT
# IPAddressToString -> compara la IP como texto
# -ClientId -> la MAC del adaptador LAB de pc-cli01