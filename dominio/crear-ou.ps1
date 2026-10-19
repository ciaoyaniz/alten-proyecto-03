#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$dominio = (Get-ADDomain).DistinguishedName

foreach ($ou in 'Usuarios', 'Equipos', 'Departamentos', 'Servicios TI') {
    if (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -SearchBase $dominio -SearchScope OneLevel) {
        Write-Host "[YA EXISTE] OU=$ou"
    } else {
        New-ADOrganizationalUnit -Name $ou -Path $dominio -ProtectedFromAccidentalDeletion $true
        Write-Host "[CREADA] OU=$ou"
    }
}

redircmp "OU=Equipos,$dominio" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'redircmp no ha podido cambiar el contenedor de los equipos nuevos.' }

Get-ADOrganizationalUnit -Filter * -SearchBase $dominio -SearchScope OneLevel | Format-Table Name, DistinguishedName -AutoSize

# Opciones configuradas:
# ----------------------
# Get-ADDomain).DistinguishedName -> DC=lab,DC=internal sin escribirlo a mano
# las cuatro OU del enunciado -> colgando directamente del dominio
# -SearchScope OneLevel -> busca solo en el primer nivel; no confunde con otras
# -ProtectedFromAccidentalDeletion -> no se borran sin quitar antes la protección
# redircmp OU=Equipos -> los equipos que se unen al dominio caen en Equipos