# Отменить всё: включить пакеты из списка, вернуть стандартный домашний экран и сделать его главным.
# Пакеты, отключённые ещё до первого запуска (см. самую старую копию в backup\), останутся отключёнными.
# Использование: tools\restore.ps1 examples\sony-bravia-kd55xf9005\debloat.txt [-DryRun]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$List,
    [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'common.ps1')

$packages = @(Read-DebloatList $List)
$stockHome = $DefaultStockHome
$alreadyOff = @()

$oldest = Get-OldestBackup
if ($oldest) {
    $alreadyOff = @(Get-Content -LiteralPath (Join-Path $oldest.FullName 'packages-disabled.txt'))
    $recorded = "$(Get-Content -LiteralPath (Join-Path $oldest.FullName 'home.txt'))".Trim()
    # Запись годится, только если это обычный лаунчер, а не наш и не экран выбора Android.
    if ($recorded -match 'launcher' -and $recorded -notlike "$LauncherPackage/*") { $stockHome = $recorded }
    Write-Host "По резервной копии $($oldest.Name): Home вернётся к $stockHome"
} else {
    Write-Warning "Резервных копий нет: Home вернётся к $stockHome, а все пакеты из списка будут включены."
}

$stockPackage = ($stockHome -split '/')[0]
$commands = @($packages | Where-Object { $alreadyOff -notcontains $_ } | ForEach-Object { "pm enable $_" })
$commands += "pm enable $stockPackage"
$commands += "cmd package set-home-activity --user 0 $stockHome"
$commands += 'am force-stop com.android.tv.settings'
$commands += 'input keyevent KEYCODE_HOME'

if ($DryRun) {
    $commands | ForEach-Object { Write-Host $_ }
    Write-Host "Пробный запуск: $($commands.Count) команд. На ТВ ничего не отправлено."
    return
}

Assert-SonyTv
Invoke-Tv $commands | ForEach-Object { Write-Host $_ }

$now = Get-TvHome
if ($now -like "$stockPackage/*") {
    Write-Host "Готово. Кнопка Home снова открывает $now."
} else {
    Write-Warning "Home сейчас принадлежит '$now', а ожидался $stockHome. Нажмите Home на пульте; если откроется не тот экран, см. раздел о проблемах в ИНСТРУКЦИЯ.md."
}
Write-Host "Лаунчер остался установленным, но не мешает. Удалить: tools\venv\Scripts\python.exe -I tools\tv.py `"pm uninstall $LauncherPackage`""
