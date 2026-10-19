#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, GroupPolicy
$dominio = Get-ADDomain
$nombreGpo = 'GPO-Usuarios-Escritorio'
$ouUsuarios = "OU=Usuarios,$($dominio.DistinguishedName)"
$fondoLocal = "C:\Windows\SYSVOL\sysvol\$($dominio.DNSRoot)\scripts\fondo-lab.jpg"
$fondoRed = "\\$($dominio.DNSRoot)\NETLOGON\fondo-lab.jpg"
$raizRedirigidas = 'C:\Redirigidas'
$sidUsuariosDominio = "$($dominio.DomainSID.Value)-513"

function Invoke-Icacls {
    icacls @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls ha fallado: icacls $($args -join ' ')" }
}

Write-Host '[1/4] Fondo de pantalla en NETLOGON'
if (-not (Test-Path -Path $fondoLocal)) {
    Add-Type -AssemblyName System.Drawing
    $imagen = New-Object System.Drawing.Bitmap 1920, 1080
    $lienzo = [System.Drawing.Graphics]::FromImage($imagen)
    $lienzo.Clear([System.Drawing.Color]::FromArgb(31, 58, 95))
    $letra = New-Object System.Drawing.Font 'Segoe UI', 64
    $lienzo.DrawString('LAB.INTERNAL', $letra, [System.Drawing.Brushes]::White, 120, 460)
    $imagen.Save($fondoLocal, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $lienzo.Dispose()
    $imagen.Dispose()
}

Write-Host '[2/4] Carpeta oculta Redirigidas$ para los Documentos'
New-Item -Path $raizRedirigidas -ItemType Directory -Force | Out-Null
Invoke-Icacls $raizRedirigidas /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-3-0:(OI)(CI)(IO)F' "*${sidUsuariosDominio}:(RD,AD,RA,REA,X,RC)"
if (-not (Get-SmbShare -Name 'Redirigidas$' -ErrorAction SilentlyContinue)) {
    $autenticados = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-11').Translate([System.Security.Principal.NTAccount]).Value
    New-SmbShare -Name 'Redirigidas$' -Path $raizRedirigidas -FullAccess $autenticados -CachingMode None -Description 'Documentos redirigidos' | Out-Null
}

Write-Host "[3/4] GPO $nombreGpo con el fondo y el Panel de control bloqueado"
if (-not (Get-GPO -Name $nombreGpo -ErrorAction SilentlyContinue)) {
    New-GPO -Name $nombreGpo -Comment 'Fondo de pantalla, Documentos redirigidos y Panel de control bloqueado' | Out-Null
}
Set-GPRegistryValue -Name $nombreGpo -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' -ValueName 'Wallpaper' -Type String -Value $fondoRed | Out-Null
Set-GPRegistryValue -Name $nombreGpo -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' -ValueName 'WallpaperStyle' -Type String -Value '4' | Out-Null
Set-GPRegistryValue -Name $nombreGpo -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null

Write-Host "[4/4] Vínculo con $ouUsuarios"
$vinculos = (Get-GPInheritance -Target $ouUsuarios).GpoLinks
if (-not ($vinculos | Where-Object { $_.DisplayName -eq $nombreGpo })) {
    New-GPLink -Name $nombreGpo -Target $ouUsuarios -LinkEnabled Yes | Out-Null
}
Write-Host 'Falta la redirección de Documentos. Se configura en la consola Administración de directivas de grupo.'

# Opciones configuradas:
# ----------------------
# Import-Module ActiveDirectory, GroupPolicy -> cmdlets de AD y de GPO
# $fondoLocal en SYSVOL\...\scripts -> es la carpeta que se comparte como NETLOGON
# $fondoRed \\lab.internal\NETLOGON -> ruta que leen los clientes; todos los usuarios pueden leerla
# DomainSID-513 -> el grupo Usuarios del dominio en cualquier idioma
# Invoke-Icacls -> icacls no lanza excepción; miro $LASTEXITCODE
# System.Drawing -> dibuja un fondo azul con el texto LAB.INTERNAL
# /inheritance:r -> quita los permisos heredados de C:\
# *S-1-5-32-544 y *S-1-5-18 (OI)(CI)F -> Administradores y SYSTEM, control total
# *S-1-3-0 (OI)(CI)(IO)F -> CREATOR OWNER; cada usuario es dueño de su carpeta
# (RD,AD,RA,REA,X,RC) sin herencia -> Usuarios del dominio solo crean su carpeta en la raíz
# Redirigidas$ -> el $ oculta el recurso en la lista de recursos compartidos
# -FullAccess Usuarios autentificados -> el filtro real lo hacen los permisos NTFS
# -CachingMode None -> sin archivos sin conexión en el recurso
# Policies\System Wallpaper -> directiva Tapiz del escritorio
# WallpaperStyle 4 -> estilo Rellenar
# Policies\Explorer NoControlPanel 1 -> directiva Prohibir el acceso a Configuración de PC y a Panel de control
# New-GPLink -Target OU=Usuarios -> la GPO solo afecta a los usuarios de esa OU