param(
    [string]$OutputDirectory,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$addonRoot = Join-Path $repositoryRoot "MythicBoost"
$tocPath = Join-Path $addonRoot "MythicBoost.toc"
$architectureCheck = Join-Path $PSScriptRoot "CheckArchitecture.py"
$localizationCheck = Join-Path $PSScriptRoot "CheckLocalization.py"
$smokeTests = Join-Path $PSScriptRoot "TestMythicBoost.py"
$releaseCheck = Join-Path $PSScriptRoot "VerifyRelease.py"

if (-not (Test-Path -LiteralPath $tocPath)) {
    throw "MythicBoost.toc was not found: $tocPath"
}

if (-not (Test-Path -LiteralPath $architectureCheck)) {
    throw "Architecture checker was not found: $architectureCheck"
}
if (-not (Test-Path -LiteralPath $smokeTests)) {
    throw "Executable smoke tests were not found: $smokeTests"
}
if (-not (Test-Path -LiteralPath $localizationCheck)) {
    throw "Localization checker was not found: $localizationCheck"
}
if (-not (Test-Path -LiteralPath $releaseCheck)) {
    throw "Release verifier was not found: $releaseCheck"
}
& python $architectureCheck
if ($LASTEXITCODE -ne 0) {
    throw "Architecture check failed. Release was not created."
}
& python $localizationCheck
if ($LASTEXITCODE -ne 0) {
    throw "Localization check failed. Release was not created."
}
& python $smokeTests
if ($LASTEXITCODE -ne 0) {
    throw "Executable smoke tests failed. Release was not created."
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot "dist"
}

$versionLine = Select-String -LiteralPath $tocPath -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) { throw "The TOC does not contain a version." }
$version = $versionLine.Matches[0].Groups[1].Value.Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid release version: $version" }

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("MythicBoost-release-" + [guid]::NewGuid().ToString("N"))
$stagedAddon = Join-Path $temporaryRoot "MythicBoost"
$archivePath = Join-Path $OutputDirectory ("MythicBoost-$version.zip")

if (Test-Path -LiteralPath $archivePath) {
    if (-not $Force) {
        throw "Release archive already exists: $archivePath. Use -Force to replace it."
    }
    Remove-Item -LiteralPath $archivePath -Force
}

try {
    New-Item -ItemType Directory -Path $stagedAddon -Force | Out-Null

    # Windows PowerShell 5.1 treats UTF-8 without BOM as the active ANSI code
    # page.  Reading the Russian metadata without an explicit encoding and
    # writing it back as UTF-8 produced valid but mojibaked release TOCs.
    $releaseTocLines = Get-Content -LiteralPath $tocPath -Encoding UTF8
    $tocEntries = $releaseTocLines | Where-Object {
        $_ -and -not $_.StartsWith("##")
    }
    foreach ($entry in $tocEntries) {
        $relativePath = $entry.Trim().Replace('/', [IO.Path]::DirectorySeparatorChar)
        $sourcePath = Join-Path $addonRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "TOC entry is missing: $entry"
        }
        $destinationPath = Join-Path $stagedAddon $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    }

    $releaseExtras = @(
        "CHANGELOG.md",
        "README.txt",
        "LICENSE-XPERL.txt",
        "NOTICE-XPERL.txt",
        "Media\MythicBoostIcon.png",
        "Media\XPerl_FrameBack.blp",
        "Media\XPerl_ThinEdge.blp"
    )
    foreach ($relativePath in $releaseExtras) {
        $sourcePath = Join-Path $addonRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Release file is missing: $relativePath"
        }
        $destinationPath = Join-Path $stagedAddon $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    }

    $stagedToc = Join-Path $stagedAddon "MythicBoost.toc"
    [IO.File]::WriteAllLines($stagedToc, $releaseTocLines, [Text.UTF8Encoding]::new($false))

    $forbidden = Get-ChildItem -LiteralPath $stagedAddon -Recurse -File | Where-Object {
        $_.Extension -in @('.ps1', '.zip', '.bak', '.old') -or $_.Name -eq 'KeystoneTimer.lua'
    }
    if ($forbidden) {
        throw "Forbidden files entered the release: $($forbidden.FullName -join ', ')"
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Compress-Archive -LiteralPath $stagedAddon -DestinationPath $archivePath -CompressionLevel Optimal

    & python $releaseCheck $archivePath
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
        throw "Release verification failed."
    }

    $hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
    [pscustomobject]@{
        Version = $version
        Archive = $archivePath
        SizeKB = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1KB, 1)
        SHA256 = $hash.Hash
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        if (-not $resolvedTemporaryRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove an unsafe temporary path: $resolvedTemporaryRoot"
        }
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}
