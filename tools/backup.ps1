# Сохранить состояние ТВ в backup\<дата-время>: какие пакеты включены и отключены, кому принадлежит Home.
# disable.ps1 и build-and-install.ps1 запускают его сами перед изменениями; restore.ps1 берёт данные из самой старой копии.
# Использование: tools\backup.ps1
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-Packages([string]$Flag) {
    @(Get-TvOutput "pm list packages $Flag") | Where-Object { $_ -match '\S' } |
        ForEach-Object { ($_ -replace '^package:', '').Trim() } | Sort-Object
}

Assert-SonyTv

# Сначала всё прочитать, потом создать папку: неполная копия не должна стать «самой старой».
$all = Get-Packages ''
$enabled = Get-Packages '-e'
$disabled = Get-Packages '-d'
$homeActivity = Get-TvHome
if (-not $all) { throw 'ТВ не вернул список пакетов, копия не создана' }
$props = Get-TvOutput 'getprop'
$display = Get-TvOutput 'wm size; wm density'

$dir = Join-Path $Backups (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'packages-all.txt') -Value $all -Encoding Ascii
Set-Content -LiteralPath (Join-Path $dir 'packages-enabled.txt') -Value $enabled -Encoding Ascii
Set-Content -LiteralPath (Join-Path $dir 'packages-disabled.txt') -Value $disabled -Encoding Ascii
Set-Content -LiteralPath (Join-Path $dir 'home.txt') -Value $homeActivity -Encoding Ascii
Set-Content -LiteralPath (Join-Path $dir 'getprop.txt') -Value $props -Encoding UTF8
Set-Content -LiteralPath (Join-Path $dir 'display.txt') -Value $display -Encoding UTF8
Write-Host "Резервная копия: $dir ($(@($all).Count) пакетов, Home: $homeActivity)"
