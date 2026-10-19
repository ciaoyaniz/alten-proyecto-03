param(
    [string]$Destino = 'srv-dc01.lab.internal',
    [int]$Puerto = 445,
    [string]$Dns = '192.168.60.80'
)
$script:fallos = 0

function Resultado([string]$Capa, [bool]$Bien, [string]$Detalle) {
    if ($Bien) {
        Write-Host "[OK]    $Capa - $Detalle"
    } else {
        Write-Host "[FALLO] $Capa - $Detalle"
        $script:fallos++
    }
}

Write-Host "Diagnóstico de $env:COMPUTERNAME hacia ${Destino}:$Puerto"

$ip = Get-NetIPAddress -InterfaceAlias 'LAB' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
Resultado '1 IP' ($ip.IPAddress -like '192.168.60.*' -and $ip.AddressState -eq 'Preferred') "LAB tiene $($ip.IPAddress) en estado $($ip.AddressState)"

$servidores = @((Get-DnsClientServerAddress -InterfaceAlias 'LAB', 'NAT' -AddressFamily IPv4).ServerAddresses | Select-Object -Unique)
Resultado '2 DNS' ($servidores.Count -gt 0 -and -not ($servidores | Where-Object { $_ -ne $Dns })) "servidores DNS configurados: $($servidores -join ', ')"

Resultado '3 Ping' (Test-Connection -ComputerName $Dns -Count 2 -Quiet) "ping a $Dns"

$registro = Resolve-DnsName -Name $Destino -Type A -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
Resultado '4 Nombre' ([bool]$registro) "$Destino -> $($registro.IPAddress)"

$tcp = Test-NetConnection -ComputerName $Destino -Port $Puerto -WarningAction SilentlyContinue
Resultado '5 Puerto' $tcp.TcpTestSucceeded "TCP $Puerto en $Destino"

if ($script:fallos -eq 0) {
    Write-Host 'Todo correcto.'
} else {
    Write-Host "$($script:fallos) capas fallan. Arregla la primera que sale [FALLO] y vuelve a lanzarlo."
    exit 1
}

# Opciones configuradas:
# ----------------------
# -Destino, -Puerto y -Dns -> qué servicio pruebo y qué DNS tiene que usar el equipo
# Resultado -> escribe [OK] o [FALLO] por capa y cuenta los fallos
# AddressState Preferred -> una IP duplicada sale como Duplicate
# DNS de LAB y NAT -> los dos adaptadores tienen que preguntar solo al DC
# Test-Connection -Quiet -> el ping como True o False
# Resolve-DnsName -DnsOnly -> pregunta al DNS sin mirar el archivo hosts
# Where-Object Type -eq A -> se queda con la IP aunque delante venga un CNAME
# Test-NetConnection -Port -> abre la conexión TCP al puerto del servicio
# -WarningAction SilentlyContinue -> sin el aviso amarillo cuando el puerto falla
# exit 1 -> termina con error si alguna capa falla