<#
.SYNOPSIS
    Копирует аддон из репозитория в папку аддонов World of Warcraft.

.DESCRIPTION
    Игра грузит аддон из своей папки, а не из репозитория, и это отдельная
    копия — не ссылка. Пока её не обновить, любые правки остаются невидимыми:
    коммит есть, пуш есть, в игре старый код и полное непонимание, почему
    «ничего не поменялось после релоада».

    Ссылку вместо копии здесь не делаем сознательно: репозиторий лежит в
    OneDrive, а он умеет держать файлы заглушками «только в облаке» —
    игра такой файл не прочитает.

    После запуска достаточно /reload, перезаходить в игру не нужно.
#>
[CmdletBinding()]
param(
    # Папка _retail_ внутри установленной игры.
    [string] $GamePath = "D:\Games\World of Warcraft\_retail_"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$source = Join-Path (Split-Path -Parent $PSScriptRoot) "MythicBoost"
if (-not (Test-Path $source)) { throw "Не найден исходник аддона: $source" }

$addons = Join-Path $GamePath "Interface\AddOns"
if (-not (Test-Path $addons)) { throw "Не найдена папка аддонов: $addons" }

$target = Join-Path $addons "MythicBoost"

$tocPath = Join-Path $source "MythicBoost.toc"
$versionLine = Select-String -LiteralPath $tocPath -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) { throw "В TOC нет версии." }
$version = $versionLine.Matches[0].Groups[1].Value.Trim()

# /MIR удаляет в приёмнике то, чего нет в источнике: иначе файлы, выброшенные
# из аддона, продолжают грузиться игрой и ломают его самым непонятным образом.
robocopy $source $target /MIR /NFL /NDL /NJH /NP | Out-Null
$code = $LASTEXITCODE

# robocopy: 0 — нечего копировать, 1..7 — скопировано или удалено, 8 и выше — сбой.
if ($code -ge 8) { throw "robocopy завершился с кодом $code" }

Write-Output "MythicBoost $version -> $target"
Write-Output $(if ($code -eq 0) { "Изменений не было." } else { "Файлы обновлены. В игре достаточно /reload." })
