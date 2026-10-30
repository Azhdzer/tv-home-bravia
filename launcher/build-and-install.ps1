# Собрать APK лаунчера голыми инструментами SDK (без Gradle) и поставить его на ТВ как домашний экран.
#   launcher\build-and-install.ps1                     сборка + установка
#   launcher\build-and-install.ps1 -BuildOnly          только сборка
#   launcher\build-and-install.ps1 -StockLauncher <пакет>   если скрипт не смог сам определить стандартный лаунчер
#   launcher\build-and-install.ps1 -StockLauncher none      стандартный лаунчер не трогать
param(
    [switch]$BuildOnly,
    [string]$StockLauncher
)
. (Join-Path $PSScriptRoot '..\tools\common.ps1')

$jdk = Join-Path $Toolchain 'jdk'
if (-not (Test-Path -LiteralPath "$jdk\bin\javac.exe")) { $jdk = $env:JAVA_HOME }
$sdk = Join-Path $Toolchain 'android-sdk'
if (-not (Test-Path -LiteralPath "$sdk\platforms\android-28\android.jar")) { $sdk = $env:ANDROID_HOME }
if (-not $jdk -or -not (Test-Path -LiteralPath "$jdk\bin\javac.exe") -or
    -not $sdk -or -not (Test-Path -LiteralPath "$sdk\platforms\android-28\android.jar")) {
    throw 'Нет JDK 17 или Android SDK. Запустите .\setup.ps1 (без -NoLauncher).'
}
$env:JAVA_HOME = $jdk
$env:Path = "$jdk\bin;$env:Path"
$bt = "$sdk\build-tools\34.0.0"
# Компилируем под Android 9: любой вызов API новее этого ТВ сломает сборку, а не запуск на ТВ.
$androidJar = "$sdk\platforms\android-28\android.jar"
$src = $PSScriptRoot
$b = Join-Path $src 'build'
$apk = Join-Path $b 'tvhome.apk'
$keystore = Join-Path $src 'debug.keystore'

if (Test-Path -LiteralPath $b) { Remove-Item -LiteralPath $b -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$b\gen", "$b\classes", "$b\dex" | Out-Null

Invoke-Native "$bt\aapt2.exe" compile --dir "$src\res" -o "$b\res.zip"
Invoke-Native "$bt\aapt2.exe" link -o "$b\base.apk" -I $androidJar --manifest "$src\AndroidManifest.xml" --java "$b\gen" `
    --min-sdk-version 24 --target-sdk-version 28 "$b\res.zip"
$sources = @(Get-ChildItem -LiteralPath "$src\src", "$b\gen" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
# Кавычки у -Xlint обязательны: без них PowerShell разрежет аргумент по двоеточию.
Invoke-Native "$jdk\bin\javac.exe" -nowarn '-Xlint:-options' --release 11 -encoding UTF-8 -classpath $androidJar -d "$b\classes" @sources
Invoke-Native "$jdk\bin\jar.exe" cf "$b\classes.jar" -C "$b\classes" .
Invoke-Native "$bt\d8.bat" --min-api 24 --lib $androidJar --output "$b\dex" "$b\classes.jar"

Copy-Item -LiteralPath "$b\base.apk" -Destination "$b\unsigned.apk"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open("$b\unsigned.apk", [IO.Compression.ZipArchiveMode]::Update)
try {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$b\dex\classes.dex", 'classes.dex')
    # Обои добавляем сами, а не через aapt2 -A: под Windows он пишет пути с обратным слэшем
    # (assets/wallpapers\01.jpg), Android таких файлов не находит, и фон остаётся чёрным.
    foreach ($photo in Get-ChildItem -LiteralPath "$src\assets\wallpapers" -File) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $photo.FullName,
            "assets/wallpapers/$($photo.Name)", [IO.Compression.CompressionLevel]::NoCompression)
    }
} finally { $zip.Dispose() }
Invoke-Native "$bt\zipalign.exe" -f 4 "$b\unsigned.apk" "$b\aligned.apk"

if (-not (Test-Path -LiteralPath $keystore)) {
    Invoke-Native "$jdk\bin\keytool.exe" -genkeypair -keystore $keystore -storepass android -keypass android `
        -alias tvhome -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=tvhome'
}
Invoke-Native "$bt\apksigner.bat" sign --ks $keystore --ks-pass pass:android --out $apk "$b\aligned.apk"
Write-Host "Собрано: $apk ($((Get-Item -LiteralPath $apk).Length) байт)"
if ($BuildOnly) { return }

# Дальше ТВ меняется. Порядок важен: стандартный лаунчер отключается только после того, как новый запустился.
& (Join-Path $PSScriptRoot '..\tools\backup.ps1')

$homeNow = Get-TvHome
if (-not $StockLauncher) {
    if ($homeNow -like "$LauncherPackage/*") {
        $StockLauncher = 'none'
        Write-Host 'Этот лаунчер уже главный: обновляю только его.'
    } elseif ($homeNow -match '^(com\.google\.android\.tvlauncher|com\.google\.android\.leanbacklauncher|com\.google\.android\.apps\.tv\.launcherx)/') {
        $StockLauncher = $Matches[1]
    } else {
        throw "Home сейчас принадлежит '$homeNow', и это не известный стандартный лаунчер. На ТВ ничего не менялось. Запустите снова с -StockLauncher <пакет> или -StockLauncher none."
    }
}
Write-Host "Стандартный лаунчер: $StockLauncher"

$remoteApk = '/data/local/tmp/tvhome.apk'
Invoke-Native $Py -I $TvPy --push-b64 $apk $remoteApk
$install = Invoke-Tv @("pm install -r $remoteApk", "rm -f $remoteApk")
$install | ForEach-Object { Write-Host $_ }
if ("$install" -notmatch 'Success') {
    throw 'pm install не удался, стандартный домашний экран не тронут. Причина в выводе выше.'
}

Invoke-Tv @(
    "pm grant $LauncherPackage android.permission.ACCESS_FINE_LOCATION",
    "cmd package compile -m speed -f $LauncherPackage",
    "am force-stop $LauncherPackage"
) | ForEach-Object { Write-Host $_ }

$start = "$(Invoke-Tv @("am start -W -n $LauncherHome"))"
if ($start -notmatch 'Status: ok' -or $start -match 'Error') {
    Write-Host $start
    throw 'Новый лаунчер не запустился, стандартный домашний экран не тронут.'
}
# Status: ok ещё не значит, что приложение живо: сразу после старта оно могло упасть.
if (-not "$(Get-TvOutput "sleep 2; pidof $LauncherPackage")".Trim()) {
    throw "Новый лаунчер упал сразу после запуска, стандартный домашний экран не тронут. Причина: tools\venv\Scripts\python.exe -I tools\tv.py `"logcat -d -b crash`""
}

# На этой платформе у стандартного лаунчера приоритет HOME = 2: set-home-activity отвечает Success,
# но не действует, пока он не отключён. Поэтому назначаем до и после отключения.
# Сначала останавливаем пробный запуск: он живёт в обычной задаче, и Home открывал бы его позади других приложений.
$handover = @("am force-stop $LauncherPackage", "cmd package set-home-activity --user 0 $LauncherHome")
if ($StockLauncher -ne 'none') { $handover += "pm disable-user --user 0 $StockLauncher" }
$handover += "cmd package set-home-activity --user 0 $LauncherHome"
$handover += 'am force-stop com.android.tv.settings'
$handover += 'input keyevent KEYCODE_HOME'
Invoke-Tv $handover | ForEach-Object { Write-Host $_ }

$now = Get-TvHome
if ($now -ne $LauncherHome) {
    if ($StockLauncher -ne 'none') {
        Write-Warning "Home достался '$now', а не новому лаунчеру. Возвращаю стандартный."
        Invoke-Tv @("pm enable $StockLauncher", "cmd package set-home-activity --user 0 $homeNow", 'input keyevent KEYCODE_HOME') |
            ForEach-Object { Write-Host $_ }
    }
    throw "Лаунчер не стал домашним экраном (Home: $now). См. раздел о проблемах в ИНСТРУКЦИЯ.md."
}
Write-Host 'Установлено. Нажмите Home на пульте. Проверьте Home и изнутри приложения.'
