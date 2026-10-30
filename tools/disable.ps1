# Отключить все пакеты из списка (по одному вызову pm на команду: цепочки pm могут оборваться на первой).
# Пакеты отключаются для пользователя 0 и не удаляются. Откат: tools\restore.ps1 <тот же список>.
# Использование: tools\disable.ps1 examples\sony-bravia-kd55xf9005\debloat.txt [-DryRun]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$List,
    [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'common.ps1')

$packages = @(Read-DebloatList $List)
if (-not $packages) { throw "В списке нет ни одного пакета: $List" }

$blocked = @($packages | Where-Object { Test-Protected $_ })
if ($blocked) {
    throw "Отказ: в списке есть пакеты, без которых ТВ работать не будет. На ТВ ничего не менялось: $($blocked -join ', ')"
}

$commands = @($packages | ForEach-Object { "pm disable-user --user 0 $_" })
if ($DryRun) {
    $commands | ForEach-Object { Write-Host $_ }
    Write-Host "Пробный запуск: $($commands.Count) команд. На ТВ ничего не отправлено."
    return
}

Assert-SonyTv
$device = "$(Get-TvOutput 'getprop ro.product.device')".Trim()
if ($device -ne $TvDevice) {
    Write-Warning "Список составлен для платформы $TvDevice, а этот ТВ сообщает '$device'. Прочитайте список и уберите то, в чём не уверены."
}

& (Join-Path $PSScriptRoot 'backup.ps1')

$out = @(Invoke-Tv $commands)
$out | ForEach-Object { Write-Host $_ }

$done = @($out | Where-Object { $_ -match 'new state: disabled' }).Count
$missing = @($out | Where-Object { $_ -match 'Unknown package' }).Count
$failed = $packages.Count - $done - $missing
Write-Host ''
Write-Host "Отключено: $done. Нет на этом ТВ: $missing. Не удалось: $failed."
if ($failed -gt 0) { Write-Warning 'Часть пакетов система отключить не дала (строки с Error выше). ТВ это не вредит.' }
Write-Host 'Откат: tools\restore.ps1 <тот же список>'
