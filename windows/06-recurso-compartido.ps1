#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$dominio = Get-ADDomain
$raiz = 'C:\Empresa'
$departamentos = [ordered]@{ 'Administracion' = 'GG-Administracion'; 'Ventas' = 'GG-Ventas'; 'RRHH' = 'GG-RRHH'; 'Direccion' = 'GG-Direccion' }
$sidUsuariosDominio = "$($dominio.DomainSID.Value)-513"
$sidDireccion = (Get-ADGroup -Identity 'GG-Direccion').SID.Value

function Invoke-Icacls {
    icacls @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls ha fallado: icacls $($args -join ' ')" }
}

Write-Host '[1/4] Carpetas de los departamentos'
foreach ($d in $departamentos.Keys) {
    New-Item -Path "$raiz\Departamentos\$d" -ItemType Directory -Force | Out-Null
}

Write-Host '[2/4] Permisos NTFS por grupo'
Invoke-Icacls $raiz /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' "*${sidUsuariosDominio}:(RX)"
Invoke-Icacls "$raiz\Departamentos" /grant:r "*${sidUsuariosDominio}:(RX)"
foreach ($d in $departamentos.Keys) {
    $sidGrupo = (Get-ADGroup -Identity $departamentos[$d]).SID.Value
    $reglas = @("*${sidGrupo}:(OI)(CI)M")
    if ($sidGrupo -ne $sidDireccion) {
        $reglas += "*${sidDireccion}:(OI)(CI)RX"
    }
    Invoke-Icacls "$raiz\Departamentos\$d" /grant:r $reglas
}

Write-Host '[3/4] Recurso compartido Empresa con enumeración basada en el acceso'
if (-not (Get-SmbShare -Name 'Empresa' -ErrorAction SilentlyContinue)) {
    $autenticados = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-11').Translate([System.Security.Principal.NTAccount]).Value
    $administradores = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value
    New-SmbShare -Name 'Empresa' -Path $raiz -ChangeAccess $autenticados -FullAccess $administradores -FolderEnumerationMode AccessBased -Description 'Carpetas de la empresa' | Out-Null
}

Write-Host '[4/4] Auditoría de los accesos a Departamentos'
auditpol /set /subcategory:'{0CCE921D-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'auditpol no ha podido activar la auditoría del sistema de archivos.' }
$todos = New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'
$regla = New-Object System.Security.AccessControl.FileSystemAuditRule($todos, 'ReadData, CreateFiles, AppendData, Delete', 'ContainerInherit, ObjectInherit', 'None', 'Success, Failure')
$acl = Get-Acl -Path "$raiz\Departamentos" -Audit
$acl.SetAuditRule($regla)
Set-Acl -Path "$raiz\Departamentos" -AclObject $acl

Get-SmbShare -Name 'Empresa' | Format-List Name, Path, FolderEnumerationMode
icacls "$raiz\Departamentos\Ventas"

# Opciones configuradas:
# ----------------------
# [ordered]@{ carpeta = grupo } -> cada departamento con el grupo que lo usa
# DomainSID-513 y SID de los grupos -> icacls con *SID funciona en cualquier idioma
# /inheritance:r en C:\Empresa -> no hereda los permisos de C:\
# Administradores y SYSTEM (OI)(CI)F -> control total en todo el árbol
# Usuarios del dominio (RX) sin (OI)(CI) -> pueden entrar en Empresa y Departamentos, nada más
# grupo del departamento (OI)(CI)M -> modificar en su carpeta y lo que hay dentro
# GG-Direccion (OI)(CI)RX -> Dirección lee todas las carpetas
# -ChangeAccess Usuarios autentificados -> permiso de compartición Cambiar; manda NTFS
# -FullAccess Administradores -> control total por la red para administrar
# -FolderEnumerationMode AccessBased -> cada usuario solo ve las carpetas que puede abrir
# auditpol {0CCE921D-...} -> subcategoría Sistema de archivos por GUID, en cualquier idioma
# S-1-1-0 -> Todos; se audita a cualquiera que entre
# ReadData, CreateFiles, AppendData, Delete -> lecturas, escrituras y borrados
# 'Success, Failure' -> registra los accesos permitidos y los denegados
# Get-Acl -Audit / SetAuditRule -> añade la regla de auditoría (SACL) a Departamentos