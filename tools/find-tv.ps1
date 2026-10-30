# Найти ТВ в домашней сети: проверяет порты ADB (5555) и Cast (8008) на всех адресах вашей подсети /24.
# Первый ТВ с открытым ADB (Sony, если их несколько) сохраняется в tools\.tv_host.
# Использование: tools\find-tv.ps1              поиск
#                tools\find-tv.ps1 -Ip 192.168.1.50    не искать, сохранить этот адрес
param([string]$Ip)
. (Join-Path $PSScriptRoot 'common.ps1')

$hostFile = Join-Path $PSScriptRoot '.tv_host'

function Save-TvHost([string]$Address) {
    # WriteAllText без BOM: файл читает tv.py.
    [IO.File]::WriteAllText($hostFile, $Address)
    Write-Host "Сохранено: $Address. Дальше: tools\venv\Scripts\python.exe -I tools\tv.py --probe"
}

if ($Ip) {
    if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Это не похоже на IP-адрес: $Ip" }
    Save-TvHost $Ip
    return
}

# Все адреса подсети на порту; ждём общие 2 секунды, затем смотрим, кто успел ответить.
function Find-OpenPort([string[]]$Addresses, [int]$Port) {
    $probes = foreach ($address in $Addresses) {
        $client = New-Object Net.Sockets.TcpClient
        [pscustomobject]@{ Address = $address; Client = $client; Task = $client.ConnectAsync($address, $Port) }
    }
    Start-Sleep -Milliseconds 2000
    foreach ($probe in $probes) {
        if ($probe.Task.Status -eq 'RanToCompletion') { $probe.Address }
        $probe.Client.Close()
    }
}

$localIps = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
    ForEach-Object { $_.IPv4Address.IPAddress })
if (-not $localIps) { throw 'Не удалось определить IP этого компьютера. Он подключён к сети?' }

$adb = @()
$cast = @()
foreach ($localIp in $localIps) {
    $net = $localIp -replace '\.\d+$', ''
    Write-Host "Сканирую $net.0/24 с адреса $localIp ..."
    $addresses = 1..254 | ForEach-Object { "$net.$_" }
    $adb += @(Find-OpenPort $addresses 5555)
    $cast += @(Find-OpenPort $addresses 8008)
}

$names = @{}
foreach ($address in $cast) {
    try {
        $info = Invoke-RestMethod -Uri "http://${address}:8008/setup/eureka_info?params=name" -TimeoutSec 3
        $names[$address] = $info.name
    } catch { $names[$address] = '' }
    Write-Host "Устройство Cast: $address $($names[$address])"
}

if ($adb) {
    Write-Host "ADB открыт на: $($adb -join ', ')"
    $sony = @($adb | Where-Object { $names[$_] -match 'BRAVIA|Sony|KD-' })
    Save-TvHost $(if ($sony) { $sony[0] } else { $adb[0] })
    if ($adb.Count -gt 1 -or -not $sony) { Write-Host 'Проверьте, что это ваш Sony (следующая команда покажет марку). Если нет: tools\find-tv.ps1 -Ip <адрес>' }
} else {
    Write-Host 'Не найден ТВ с открытым ADB. На ТВ: Настройки устройства → Для разработчиков → Отладка по USB.'
    if ($cast) { Write-Host '(Ваш ТВ, вероятно, одно из устройств Cast выше: включите на нём отладку и повторите.)' }
    throw 'ТВ не найден'
}
