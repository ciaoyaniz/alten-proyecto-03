#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$dominio = Get-ADDomain
$grupos = Import-Csv -Path "$PSScriptRoot\grupos.csv" -Encoding UTF8
$usuarios = Import-Csv -Path "$PSScriptRoot\usuarios.csv" -Encoding UTF8

Write-Host "[1/3] Grupos ($($grupos.Count))"
foreach ($g in $grupos) {
    if (Get-ADGroup -Filter "Name -eq '$($g.Nombre)'") {
        Write-Host "[YA EXISTE] $($g.Nombre)"
        continue
    }
    New-ADGroup -Name $g.Nombre -GroupScope Global -GroupCategory Security -Path "OU=$($g.OU),$($dominio.DistinguishedName)" -Description $g.Descripcion
    Write-Host "[CREADO] $($g.Nombre) en OU=$($g.OU)"
}

Write-Host "[2/3] Usuarios ($($usuarios.Count)). Cambian la contraseña en su primer inicio de sesión"
$clave = Read-Host -AsSecureString 'Contraseña inicial'
foreach ($u in $usuarios) {
    if (Get-ADUser -Filter "SamAccountName -eq '$($u.Usuario)'") {
        Write-Host "[YA EXISTE] $($u.Usuario)"
        continue
    }
    $nombreCompleto = "$($u.Nombre) $($u.Apellido)"
    New-ADUser -Name $nombreCompleto -DisplayName $nombreCompleto -GivenName $u.Nombre -Surname $u.Apellido -SamAccountName $u.Usuario -UserPrincipalName "$($u.Usuario)@$($dominio.DNSRoot)" -Department $u.Departamento -Path "OU=Usuarios,$($dominio.DistinguishedName)" -AccountPassword $clave -ChangePasswordAtLogon $true -Enabled $true
    Write-Host "[CREADO] $($u.Usuario)"
}

Write-Host '[3/3] Cada usuario en el grupo de su departamento'
foreach ($u in $usuarios) {
    Add-ADGroupMember -Identity $u.Grupo -Members $u.Usuario
}

Get-ADUser -Filter * -SearchBase "OU=Usuarios,$($dominio.DistinguishedName)" -Properties Department, MemberOf |
    Sort-Object Department |
    Format-Table SamAccountName, Name, Department, @{ Name = 'Grupo'; Expression = { ($_.MemberOf | Get-ADGroup).Name } } -AutoSize

# Opciones configuradas:
# ----------------------
# $PSScriptRoot -> los CSV se leen de la carpeta del script
# -Encoding UTF8 -> Windows PowerShell leería las tildes del CSV como ANSI
# Get-ADGroup/Get-ADUser -Filter antes de crear -> se puede lanzar dos veces
# -GroupScope Global -GroupCategory Security -> grupo global de seguridad para dar permisos
# -Path OU=... -> cada grupo en la OU que dice su fila
# Read-Host -AsSecureString -> la contraseña inicial no queda en el script ni en el historial
# UserPrincipalName usuario@lab.internal -> el nombre para iniciar sesión con correo
# -Department -> el departamento visible en las propiedades del usuario
# -ChangePasswordAtLogon $true -> cada usuario pone su propia contraseña
# Add-ADGroupMember -> mete al usuario en el grupo de su fila
# @{ Name = 'Grupo'; ... } -> columna calculada con el grupo de cada usuario