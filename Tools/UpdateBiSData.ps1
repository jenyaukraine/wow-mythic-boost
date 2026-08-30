param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\MythicBoost\Data\SeasonTop.lua')
)

$ErrorActionPreference = 'Stop'

# Murlok.io exposes current top-character snapshots as JSON. WoW addons cannot
# make HTTP requests, so this build-time helper aggregates the most common item
# for every slot and writes a compact Lua snapshot that ships with MythicBoost.
$specs = @(
    @{ ID = 250; Class = 'death-knight'; Spec = 'blood' },
    @{ ID = 251; Class = 'death-knight'; Spec = 'frost' },
    @{ ID = 252; Class = 'death-knight'; Spec = 'unholy' },
    @{ ID = 577; Class = 'demon-hunter'; Spec = 'havoc' },
    @{ ID = 581; Class = 'demon-hunter'; Spec = 'vengeance' },
    @{ ID = 1480; Class = 'demon-hunter'; Spec = 'devourer' },
    @{ ID = 102; Class = 'druid'; Spec = 'balance' },
    @{ ID = 103; Class = 'druid'; Spec = 'feral' },
    @{ ID = 104; Class = 'druid'; Spec = 'guardian' },
    @{ ID = 105; Class = 'druid'; Spec = 'restoration' },
    @{ ID = 1467; Class = 'evoker'; Spec = 'devastation' },
    @{ ID = 1468; Class = 'evoker'; Spec = 'preservation' },
    @{ ID = 1473; Class = 'evoker'; Spec = 'augmentation' },
    @{ ID = 253; Class = 'hunter'; Spec = 'beast-mastery' },
    @{ ID = 254; Class = 'hunter'; Spec = 'marksmanship' },
    @{ ID = 255; Class = 'hunter'; Spec = 'survival' },
    @{ ID = 62; Class = 'mage'; Spec = 'arcane' },
    @{ ID = 63; Class = 'mage'; Spec = 'fire' },
    @{ ID = 64; Class = 'mage'; Spec = 'frost' },
    @{ ID = 268; Class = 'monk'; Spec = 'brewmaster' },
    @{ ID = 270; Class = 'monk'; Spec = 'mistweaver' },
    @{ ID = 269; Class = 'monk'; Spec = 'windwalker' },
    @{ ID = 65; Class = 'paladin'; Spec = 'holy' },
    @{ ID = 66; Class = 'paladin'; Spec = 'protection' },
    @{ ID = 70; Class = 'paladin'; Spec = 'retribution' },
    @{ ID = 256; Class = 'priest'; Spec = 'discipline' },
    @{ ID = 257; Class = 'priest'; Spec = 'holy' },
    @{ ID = 258; Class = 'priest'; Spec = 'shadow' },
    @{ ID = 259; Class = 'rogue'; Spec = 'assassination' },
    @{ ID = 260; Class = 'rogue'; Spec = 'outlaw' },
    @{ ID = 261; Class = 'rogue'; Spec = 'subtlety' },
    @{ ID = 262; Class = 'shaman'; Spec = 'elemental' },
    @{ ID = 263; Class = 'shaman'; Spec = 'enhancement' },
    @{ ID = 264; Class = 'shaman'; Spec = 'restoration' },
    @{ ID = 265; Class = 'warlock'; Spec = 'affliction' },
    @{ ID = 266; Class = 'warlock'; Spec = 'demonology' },
    @{ ID = 267; Class = 'warlock'; Spec = 'destruction' },
    @{ ID = 71; Class = 'warrior'; Spec = 'arms' },
    @{ ID = 72; Class = 'warrior'; Spec = 'fury' },
    @{ ID = 73; Class = 'warrior'; Spec = 'protection' }
)

function Escape-LuaString([string]$Value) {
    if ($null -eq $Value) { return '' }
    return $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", ' ')
}

function Get-TopItems($Guide) {
    $characters = @($Guide.Characters)
    $counts = @{}
    foreach ($character in $characters) {
        foreach ($item in @($character.Equipment.Items)) {
            if (-not $item.ItemID -or -not $item.Slot) { continue }
            $slot = [string]$item.Slot
            # Rings and trinkets are interchangeable; combine both positions,
            # then keep the two most common unique items for the pair.
            if ($slot -like 'ring-*') { $slot = 'ring' }
            if ($slot -like 'trinket-*') { $slot = 'trinket' }
            if (-not $counts.ContainsKey($slot)) { $counts[$slot] = @{} }
            $key = [string]$item.ItemID
            if (-not $counts[$slot].ContainsKey($key)) {
                $counts[$slot][$key] = [pscustomobject]@{
                    ItemID = [int]$item.ItemID
                    Name = [string]$item.Name
                    Slot = $slot
                    Count = 0
                }
            }
            $counts[$slot][$key].Count++
        }
    }

    $result = @()
    foreach ($slot in ($counts.Keys | Sort-Object)) {
        $limit = if ($slot -in @('ring', 'trinket')) { 2 } else { 1 }
        $best = @($counts[$slot].Values | Sort-Object -Property `
            @{ Expression = 'Count'; Descending = $true }, `
            @{ Expression = 'ItemID'; Ascending = $true } | Select-Object -First $limit)
        foreach ($item in $best) {
            $share = if ($characters.Count) { [math]::Round($item.Count * 100 / $characters.Count) } else { 0 }
            $result += [pscustomobject]@{
                ItemID = $item.ItemID
                Name = $item.Name
                Slot = $item.Slot
                Share = [int]$share
            }
        }
    }
    return $result | Sort-Object Slot, ItemID
}

$handler = [System.Net.Http.HttpClientHandler]::new()
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(30)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0 Safari/537.36 MythicBoost-BiS-Updater/1.0')

$snapshots = @()
try {
    foreach ($spec in $specs) {
        $uri = "https://murlok.io/api/guides/$($spec.Class)/$($spec.Spec)/m+"
        Write-Host ("[{0}/40] {1}/{2}" -f ($snapshots.Count + 1), $spec.Class, $spec.Spec)
        $json = $client.GetStringAsync($uri).GetAwaiter().GetResult()
        $guide = $json | ConvertFrom-Json
        $snapshots += [pscustomobject]@{
            ID = $spec.ID
            Class = $spec.Class
            Spec = $spec.Spec
            Season = [string]$guide.Season
            UpdatedAt = [string]$guide.UpdatedAt
            Characters = @($guide.Characters).Count
            Items = @(Get-TopItems $guide)
        }
        Start-Sleep -Milliseconds 150
    }
}
finally {
    $client.Dispose()
    $handler.Dispose()
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('local _, JP = ...')
$lines.Add('-- Generated by Tools/UpdateBiSData.ps1; do not edit by hand.')
$lines.Add('JP.SeasonTopData = {')
$lines.Add(('    generatedAt = "{0}",' -f [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')))
$lines.Add('    source = "Murlok.io top Mythic+ players",')
$lines.Add('    endpoint = "https://murlok.io/api/guides/{class}/{spec}/m+",')
$lines.Add('    specs = {')
foreach ($snapshot in $snapshots) {
    $lines.Add(('        [{0}] = {{ class = "{1}", spec = "{2}", season = "{3}", updatedAt = "{4}", sample = {5}, items = {{' -f
        $snapshot.ID, $snapshot.Class, $snapshot.Spec, (Escape-LuaString $snapshot.Season),
        (Escape-LuaString $snapshot.UpdatedAt), $snapshot.Characters))
    foreach ($item in $snapshot.Items) {
        $lines.Add(('            [{0}] = {{ slot = "{1}", share = {2}, name = "{3}" }},' -f
            $item.ItemID, (Escape-LuaString $item.Slot), $item.Share, (Escape-LuaString $item.Name)))
    }
    $lines.Add('        } },')
}
$lines.Add('    },')
$lines.Add('}')
$resolvedOutput = Join-Path (Resolve-Path -LiteralPath $outputDir).Path (Split-Path -Leaf $OutputPath)
[System.IO.File]::WriteAllLines($resolvedOutput, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0} specs to {1}" -f $snapshots.Count, $OutputPath)
