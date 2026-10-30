# Общее для всех скриптов: пути проекта, запуск внешних программ и разговор с ТВ через tools\tv.py.
$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot
$Py = Join-Path $Repo 'tools\venv\Scripts\python.exe'
$TvPy = Join-Path $Repo 'tools\tv.py'
$Backups = Join-Path $Repo 'backup'
$Toolchain = Join-Path $Repo '.toolchain'

$LauncherPackage = 'com.mihir.tvhome'
$LauncherHome = 'com.mihir.tvhome/.MainActivity'
$DefaultStockHome = 'com.google.android.tvlauncher/.MainActivity'
$TvDevice = 'BRAVIA_ATV3_4K'

# Без этих пакетов ТВ теряет HDMI, пульт, настройки, сеть или магазин приложений. disable.ps1 их не отключит.
$ProtectedPackages = @(
    'android', 'com.android.systemui', 'com.android.tv.settings', 'com.android.vending', 'com.android.bluetooth',
    'com.android.providers.*', 'com.google.android.gms', 'com.google.android.gsf*', 'com.google.android.webview',
    'com.google.android.inputmethod.latin', 'com.google.android.tvlauncher', 'com.google.android.leanbacklauncher',
    'com.sony.dtv.tvx', 'com.sony.dtv.tvx.resources', 'com.sony.dtv.tvinput.*', 'com.sony.dtv.tvplayer*',
    'com.sony.dtv.braviasync*', 'com.sony.dtv.braviabluetoothservice', 'com.sony.dtv.remotepairing',
    'com.sony.dtv.remotecontrolsettings', 'com.sony.dtv.rcplayer*', 'com.sony.dtv.rcpowerkey',
    'com.sony.dtv.uinputservice', 'com.sony.dtv.imeproxy', 'com.sony.dtv.sonysystemservice',
    'com.sony.dtv.sonyvendorservice', 'com.sony.dtv.settingsprovider', 'com.sony.dtv.configsettings',
    'com.sony.dtv.networksettings', 'com.sony.dtv.systemapp', 'com.sony.dtv.audiooutput', 'com.sony.dtv.timers',
    'com.sony.dtv.base.basicosd', 'com.sony.dtv.osdplanevisibilitymanager', 'com.sony.dtv.b2b.hotelmode',
    'com.sony.dtv.scrums.action*', 'com.mediatek.*', 'mtktvapi.agent', $LauncherPackage
)

# Запустить программу и проверить код выхода. Без 2>&1: в PowerShell 5.1 он превращает её stderr в ошибку скрипта.
function Invoke-Native {
    $exe, $rest = $args
    $ErrorActionPreference = 'Continue'
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path -Leaf $exe) завершился с кодом $LASTEXITCODE" }
}

function Assert-TvTools {
    if (-not (Test-Path -LiteralPath $Py)) { throw 'Сначала запустите .\setup.ps1' }
}

# Несколько команд за одно подключение. Через stdin, а не аргументами: 5.1 теряет в аргументах внутренние кавычки.
function Invoke-Tv {
    param([Parameter(Mandatory = $true)][string[]]$Commands)
    Assert-TvTools
    $ErrorActionPreference = 'Continue'
    $out = $Commands | & $Py -I $TvPy --batch
    if ($LASTEXITCODE -ne 0) { throw 'Команды на ТВ не выполнены: нет связи. Подробности выше.' }
    $out
}

# Одна команда, в ответе только её вывод.
function Get-TvOutput {
    param([Parameter(Mandatory = $true)][string]$Command)
    Assert-TvTools
    $ErrorActionPreference = 'Continue'
    $out = & $Py -I $TvPy $Command
    if ($LASTEXITCODE -ne 0) { throw 'Нет связи с ТВ. Подробности выше.' }
    $out
}

# В сети может быть другой телевизор на Android. Меняем только Sony, а не тот, что случайно отозвался.
function Assert-SonyTv {
    $brand = "$(Get-TvOutput 'getprop ro.product.manufacturer')".Trim()
    if ($brand -ne 'Sony') {
        throw "По сохранённому адресу отвечает не Sony, а '$brand'. На ТВ ничего не менялось. Укажите адрес своего Sony: tools\find-tv.ps1 -Ip <адрес>"
    }
}

# Кому сейчас принадлежит кнопка Home, например com.google.android.tvlauncher/.MainActivity
function Get-TvHome {
    $lines = Get-TvOutput 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
    $last = @($lines | Where-Object { $_ -match '\S' }) | Select-Object -Last 1
    "$last".Trim()
}

# Пакеты из списка: без комментариев и пустых строк, с проверкой имён (они попадают в команду на ТВ).
function Read-DebloatList {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Нет такого списка: $Path" }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $package = ($line -replace '#.*$', '').Trim()
        if (-not $package) { continue }
        if ($package -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*$') { throw "Странное имя пакета в списке: '$package'" }
        $package
    }
}

function Test-Protected {
    param([string]$Package)
    foreach ($pattern in $ProtectedPackages) { if ($Package -like $pattern) { return $true } }
    return $false
}

# Самая первая резервная копия: она описывает ТВ таким, каким он был до всех изменений.
function Get-OldestBackup {
    if (-not (Test-Path -LiteralPath $Backups)) { return }
    Get-ChildItem -LiteralPath $Backups -Directory | Sort-Object Name | Select-Object -First 1
}
