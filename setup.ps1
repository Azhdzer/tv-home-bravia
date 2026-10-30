# Разовая настройка на Windows: Python-клиент ADB, JDK 17 и минимальный Android SDK для сборки лаунчера.
# JDK и SDK ставятся в папку проекта (.toolchain), систему и PATH скрипт не меняет.
#   .\setup.ps1                     всё сразу (скачает около 465 МБ, займёт около 750 МБ)
#   .\setup.ps1 -NoLauncher         только клиент ADB: хватит, если нужно лишь отключить мусор
#   .\setup.ps1 -AcceptSdkLicense   принять лицензию Android SDK автоматически, не показывая вопросы
param(
    [switch]$NoLauncher,
    [switch]$AcceptSdkLicense
)
. (Join-Path $PSScriptRoot 'tools\common.ps1')

# Инструменты SDK запускаются через .bat, а те ломаются на пробелах и не-латинице в пути.
if ($Repo -match '[^\x21-\x7E]') {
    throw "Перенесите проект в папку без пробелов и кириллицы (например D:\tv-home-bravia). Сейчас: $Repo"
}

function Get-PythonExe {
    $ErrorActionPreference = 'Continue'
    foreach ($launcher in 'python', 'py') {
        if (-not (Get-Command $launcher -ErrorAction SilentlyContinue)) { continue }
        # python из Microsoft Store бывает заглушкой: она ничего не печатает, поэтому проверяем вывод.
        $exe = & $launcher -c 'import sys; print(sys.executable if sys.version_info >= (3, 8) else str())' 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) { return "$exe".Trim() }
    }
    throw 'Нужен Python 3.8 или новее. Установите его с python.org, отметив «Add python.exe to PATH», и повторите.'
}

# Скачать, сверить SHA-256 и распаковать во временную папку. Возвращает путь к этой папке.
function Get-Archive([string]$Url, [string]$Sha256, [string]$Name) {
    $downloads = Join-Path $Toolchain 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $file = Join-Path $downloads $Name
    Write-Host "Скачиваю $Name ..."
    Invoke-Native curl.exe -L --fail --retry 3 --output $file $Url | Out-Null
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash
    if ($actual -ne $Sha256.ToUpper()) {
        Remove-Item -LiteralPath $file -Force
        throw "Контрольная сумма $Name не совпала, файл удалён. Запустите ещё раз."
    }
    $extracted = Join-Path $Toolchain "_extract-$Name"
    New-Item -ItemType Directory -Force -Path $extracted | Out-Null
    Write-Host "Распаковываю $Name ..."
    Invoke-Native tar.exe -xf $file -C $extracted | Out-Null
    Remove-Item -LiteralPath $file -Force
    $extracted
}

if (-not (Test-Path -LiteralPath $Py)) {
    $python = Get-PythonExe
    Write-Host "Создаю окружение Python ($python)"
    Invoke-Native $python -m venv (Join-Path $Repo 'tools\venv')
}
Invoke-Native $Py -m pip install -q --no-cache-dir --disable-pip-version-check -r (Join-Path $Repo 'tools\requirements.txt')
Write-Host 'Готово: Python-клиент ADB в tools\venv'
if ($NoLauncher) { return }

# JDK 17: сборка Temurin с adoptium.net, ссылка и контрольная сумма берутся из их API.
$jdk = Join-Path $Toolchain 'jdk'
if (-not (Test-Path -LiteralPath "$jdk\bin\javac.exe")) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $asset = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse' |
        Select-Object -First 1
    $package = $asset.binary.package
    $extracted = Get-Archive $package.link $package.checksum $package.name
    Move-Item -LiteralPath (Get-ChildItem -LiteralPath $extracted -Directory | Select-Object -First 1).FullName -Destination $jdk
    Remove-Item -LiteralPath $extracted -Recurse -Force
}
$env:JAVA_HOME = $jdk
Write-Host "Готово: JDK в $jdk"

# Android SDK: инструменты командной строки с официальной страницы developer.android.com/studio.
$sdk = Join-Path $Toolchain 'android-sdk'
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path -LiteralPath $sdkmanager)) {
    $extracted = Get-Archive 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' `
        '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a' 'commandlinetools-win.zip'
    New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
    Move-Item -LiteralPath (Join-Path $extracted 'cmdline-tools') -Destination "$sdk\cmdline-tools\latest"
    Remove-Item -LiteralPath $extracted -Recurse -Force
}

# Для установки пакетов SDK нужно принять лицензию Google. Не --licenses: та спросит про все лицензии SDK сразу,
# а установка спрашивает только о тех, что нужны именно этим пакетам.
if ($AcceptSdkLicense) {
    # Ответы файлом, а не конвейером: PowerShell может дописать BOM перед первым y, и тот не засчитается.
    $answers = Join-Path $Toolchain 'downloads\answers.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $answers) | Out-Null
    [IO.File]::WriteAllText($answers, ("y`r`n" * 10))
    Invoke-Native cmd.exe /c "$sdkmanager --sdk_root=$sdk platforms;android-28 build-tools;34.0.0 < $answers"
} else {
    Write-Host 'Сейчас SDK Manager покажет лицензионное соглашение Google. Прочитайте и ответьте y, если согласны.'
    Invoke-Native $sdkmanager "--sdk_root=$sdk" 'platforms;android-28' 'build-tools;34.0.0'
}
if (-not (Test-Path -LiteralPath "$sdk\platforms\android-28\android.jar")) {
    throw 'Пакеты SDK не установились: похоже, лицензия не принята. Запустите .\setup.ps1 ещё раз.'
}
Remove-Item -LiteralPath (Join-Path $Toolchain 'downloads') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Готово: Android SDK в $sdk (платформа 28, build-tools 34.0.0)"
Write-Host 'Дальше: tools\find-tv.ps1'
