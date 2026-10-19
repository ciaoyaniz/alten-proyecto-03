#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$ipLab = '192.168.60.80'
$ipNat = (Get-NetIPAddress -InterfaceAlias 'NAT' -AddressFamily IPv4).IPAddress

Write-Host "[1/5] El DC se pregunta a sí mismo por la IP $ipLab en los dos adaptadores"
Set-DnsClientServerAddress -InterfaceAlias 'LAB' -ServerAddresses $ipLab
Set-DnsClientServerAddress -InterfaceAlias 'NAT' -ServerAddresses $ipLab
Set-DnsClient -InterfaceAlias 'NAT' -RegisterThisConnectionsAddress $false

Write-Host "[2/5] El servicio DNS solo escucha en $ipLab"
dnscmd /ResetListenAddresses $ipLab | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'dnscmd no ha podido cambiar las direcciones de escucha.' }
Restart-Service -Name DNS

Write-Host '[3/5] Reenviadores para resolver los nombres de Internet'
Set-DnsServerForwarder -IPAddress 1.1.1.1, 8.8.8.8

Write-Host "[4/5] Registros A que apuntan a la NAT ($ipNat)"
foreach ($zona in 'lab.internal', '_msdcs.lab.internal') {
    Get-DnsServerResourceRecord -ZoneName $zona -RRType A |
        Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $ipNat } |
        Remove-DnsServerResourceRecord -ZoneName $zona -Force
}
ipconfig /registerdns | Out-Null
Restart-Service -Name Netlogon

Write-Host '[5/5] Hora del dominio desde es.pool.ntp.org'
w32tm /config /manualpeerlist:es.pool.ntp.org /syncfromflags:manual /reliable:yes /update | Out-Null
Restart-Service -Name w32time

Get-DnsServerResourceRecord -ZoneName 'lab.internal' -RRType A | Format-Table HostName, RecordData -AutoSize

# Opciones configuradas:
# ----------------------
# $ipNat -> la 10.0.2.15 que da VirtualBox; se busca en vez de escribirla
# DNS del cliente = 192.168.60.80 en LAB y NAT -> el DC usa su DNS; nunca el 10.0.2.3 de VirtualBox
# RegisterThisConnectionsAddress $false -> repetido por si la promoción lo cambió
# dnscmd /ResetListenAddresses -> DNS solo atiende en LAB; no publica la IP de NAT
# $LASTEXITCODE -> dnscmd no lanza excepción; miro su código de salida
# Set-DnsServerForwarder -> lo que no es lab.internal se pregunta fuera
# lab.internal y _msdcs.lab.internal -> las dos zonas donde el DC registra sus A
# Remove-DnsServerResourceRecord -Force -> borra los A con 10.0.2.15 sin preguntar
# ipconfig /registerdns + Netlogon -> vuelve a registrar solo lo bueno
# w32tm /reliable:yes -> el DC es la fuente de hora del dominio