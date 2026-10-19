#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'srv-dc01') {
    throw 'El servidor todavía no se llama srv-dc01. Lanza antes 01-configuracion-base.ps1 y reinicia.'
}
if ((Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
    throw 'El servidor ya pertenece a un dominio.'
}

Write-Host '[1/2] Rol Servicios de dominio de Active Directory'
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

Write-Host '[2/2] Bosque nuevo lab.internal con DNS. El servidor se reinicia solo al terminar'
$dsrm = Read-Host -AsSecureString 'Contraseña del modo de restauración (DSRM)'
Import-Module ADDSDeployment
Install-ADDSForest -DomainName 'lab.internal' -DomainNetbiosName 'LAB' -ForestMode 'WinThreshold' -DomainMode 'WinThreshold' -InstallDns -SafeModeAdministratorPassword $dsrm -Force

# Opciones configuradas:
# ----------------------
# COMPUTERNAME -ne srv-dc01 -> el nombre se cambia antes de promover, nunca después
# PartOfDomain -> no deja promover un servidor que ya está en un dominio
# AD-Domain-Services -IncludeManagementTools -> el rol y sus consolas
# Read-Host -AsSecureString -> pide la contraseña DSRM sin mostrarla ni guardarla
# -DomainName lab.internal -> nombre DNS del dominio
# -DomainNetbiosName LAB -> nombre corto para LAB\usuario
# WinThreshold -> nivel funcional Windows Server 2016, el más alto de 2022
# -InstallDns -> instala DNS y crea la zona lab.internal integrada en AD
# -Force -> no pregunta y reinicia al acabar