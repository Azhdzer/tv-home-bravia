# Набрать текст в поле на ТВ (сначала откройте на нём экранную клавиатуру). Только латиница: команда
# input text на Android не умеет вводить кириллицу.
#
#   tools\type.ps1 "hello world"        набрать текст
#   tools\type.ps1                      спросить текст скрыто (для паролей; не попадёт в историю команд)
#   tools\type.ps1 -Enter "query"       затем нажать Enter
#   tools\type.ps1 -DryRun "a b"        показать команду, но не отправлять
param(
    [switch]$Enter,
    [switch]$DryRun,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Words
)
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Words) {
    $text = $Words -join ' '
} else {
    $secure = Read-Host 'Текст для ввода на ТВ (скрыт)' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if (-not $text) { throw 'Нечего набирать' }
if ($text -match '[^\x20-\x7E]') { throw 'Команда input text вводит только латиницу, цифры и знаки. Кириллицу наберите с пульта.' }

# input text превращает %s в пробел, а настоящий пробел считает концом аргумента.
# Значит, пробелы заменяем на %s, а всё заключаем в одинарные кавычки для оболочки ТВ.
$escaped = $text.Replace("'", "'\''").Replace(' ', '%s')
$commands = @("input text '$escaped'")
if ($Enter) { $commands += 'input keyevent KEYCODE_ENTER' }

if ($DryRun) {
    $commands | ForEach-Object { Write-Host $_ }
    return
}
Invoke-Tv $commands | Out-Null
Write-Host "Набрано символов: $($text.Length)"
