<#
.SYNOPSIS
    Builds the release zip for the scripted line.

.DESCRIPTION
    Stages the payload, normalizes line endings to CRLF, syntax-checks the
    PowerShell files with the running parser, zips with a top-level folder,
    verifies every expected entry is in the archive, then writes the SHA256
    sidecar and the release notes with the checksum appended.

    Nothing is published. The publish command is printed at the end.

.EXAMPLE
    .\build-release.ps1 -Version 1.0.0
#>

[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$distDir  = Join-Path $repoRoot 'dist'
$name     = "MediaOptimizer-script-$Version"
$stageDir = Join-Path $distDir $name
$zipPath  = Join-Path $distDir "$name.zip"
$hashPath = Join-Path $distDir "$name.sha256"
$notesSrc = Join-Path $repoRoot (Join-Path 'packaging' "RELEASE-NOTES-$Version.md")
$notesDst = Join-Path $distDir "$name.notes.md"

# Source path -> name inside the archive. README.txt is renamed on purpose:
# end users should not see a "packaging" folder.
$payload = @(
    [pscustomobject]@{ Source = 'MediaOptimizer.cmd';    Target = 'MediaOptimizer.cmd' }
    [pscustomobject]@{ Source = 'launcher.ps1';          Target = 'launcher.ps1' }
    [pscustomobject]@{ Source = 'optimize.ps1';          Target = 'optimize.ps1' }
    [pscustomobject]@{ Source = 'optimize.cmd';          Target = 'optimize.cmd' }
    [pscustomobject]@{ Source = 'packaging\README.txt';  Target = 'README.txt' }
)

function Fail {
    param([string]$Message)

    Write-Host ''
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
    Write-Host ''
    exit 1
}

function Format-Size {
    param([double]$Bytes)

    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }

    return ('{0:N0} B' -f $Bytes)
}

function Convert-ToCrlf {
    param([string]$Path)

    $text = [System.IO.File]::ReadAllText($Path)
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    $text = $text -replace "`n", "`r`n"

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $text, $encoding)
}

function Assert-MsDosLineEndings {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $leaf = Split-Path -Path $Path -Leaf

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Fail "byte order mark found in $leaf"
    }

    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10) {
            if ($i -eq 0 -or $bytes[$i - 1] -ne 13) {
                Fail "line $([array]::IndexOf($bytes, 10, $i)) has an LF-only ending in $leaf"
            }
        }
    }
}

# ------------------------------------------------------------------- preflight

Write-Host ''
Write-Host "  BUILD $name" -ForegroundColor Cyan
Write-Host ('  ' + ('-' * 56)) -ForegroundColor DarkGray

foreach ($item in $payload) {
    $source = Join-Path $repoRoot $item.Source

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Fail "missing payload file: $($item.Source)"
    }
}

if (-not (Test-Path -LiteralPath $notesSrc -PathType Leaf)) {
    Fail "missing release notes: packaging\RELEASE-NOTES-$Version.md"
}

# Syntax check before packaging, using whatever parser is running (5.1 on Windows).
foreach ($item in $payload) {
    if ($item.Source -notlike '*.ps1') { continue }

    $source = Join-Path $repoRoot $item.Source
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors.Count -gt 0) {
        $first = $errors[0]
        Fail "$($item.Source) line $($first.Extent.StartLineNumber): $($first.Message)"
    }

    Write-Host "  syntax ok        $($item.Source)" -ForegroundColor DarkGray
}

Push-Location $repoRoot
try {
    $dirty = @(& git status --porcelain 2>$null)
}
catch {
    $dirty = @()
}
finally {
    Pop-Location
}

if ($dirty.Count -gt 0) {
    Write-Host '  warning          working tree has uncommitted changes' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------- stage

if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }
if (Test-Path -LiteralPath $notesDst) { Remove-Item -LiteralPath $notesDst -Force }

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

foreach ($item in $payload) {
    $target = Join-Path $stageDir $item.Target
    Copy-Item -LiteralPath (Join-Path $repoRoot $item.Source) -Destination $target -Force
    Convert-ToCrlf -Path $target
    Assert-MsDosLineEndings -Path $target
}

# ------------------------------------------------------------------------ zip

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Compress-Archive writes backslash separators under .NET Framework, which is
# invalid per the ZIP spec and breaks non-Explorer extractors. Build the entries
# by hand so every name uses a forward slash.
$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)

try {
    $zipArchive = New-Object System.IO.Compression.ZipArchive(
        $zipStream,
        [System.IO.Compression.ZipArchiveMode]::Create
    )

    try {
        foreach ($item in $payload) {
            $target = Join-Path $stageDir $item.Target
            $entryName = "$name/$($item.Target)" -replace '\\', '/'
            $entry = $zipArchive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()

            try {
                $sourceStream = [System.IO.File]::OpenRead($target)

                try { $sourceStream.CopyTo($entryStream) }
                finally { $sourceStream.Dispose() }
            }
            finally { $entryStream.Dispose() }
        }
    }
    finally {
        $zipArchive.Dispose()
    }
}
finally {
    $zipStream.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Set-Content -LiteralPath $hashPath -Value ("{0}  {1}" -f $hash, (Split-Path -Path $zipPath -Leaf)) -Encoding ASCII

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)

try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName })
}
finally {
    $archive.Dispose()
}

# Assert the invariant rather than normalizing it away: a backslash here means
# the archive will explode into loose files for anyone not using Explorer.
foreach ($entryName in $entries) {
    if ($entryName -match '\\') {
        Fail "archive entry uses a backslash separator: $entryName"
    }
}

foreach ($item in $payload) {
    $expected = "$name/$($item.Target)"

    if ($entries -notcontains $expected) {
        Fail "archive is missing $expected"
    }
}

$notes = ([System.IO.File]::ReadAllText($notesSrc)).TrimEnd()
$notes = $notes + "`r`n`r`n---`r`n`r`n" + ('**SHA256** `' + $hash + '`') + "`r`n"
[System.IO.File]::WriteAllText($notesDst, $notes, (New-Object System.Text.UTF8Encoding($false)))

# -------------------------------------------------------------------- summary

Write-Host ''
Write-Host '  payload' -ForegroundColor Yellow

$stagedBytes = 0

foreach ($item in $payload) {
    $target = Join-Path $stageDir $item.Target
    $length = (Get-Item -LiteralPath $target).Length
    $stagedBytes += $length
    Write-Host ("    {0,-20} {1,9}" -f $item.Target, (Format-Size $length))
}

$zipBytes = (Get-Item -LiteralPath $zipPath).Length

Write-Host ''
Write-Host ("  {0,-24} {1,9}" -f (Split-Path -Path $zipPath -Leaf), (Format-Size $zipBytes)) -ForegroundColor Cyan
Write-Host ("  {0} files, {1} staged, {2} in archive" -f $payload.Count, (Format-Size $stagedBytes), (Format-Size $zipBytes))
Write-Host ("  SHA256  {0}" -f $hash)
Write-Host ("  wrote   dist\{0}" -f (Split-Path -Path $hashPath -Leaf))
Write-Host ("  wrote   dist\{0}" -f (Split-Path -Path $notesDst -Leaf))
Write-Host ''
Write-Host '  Publish with:' -ForegroundColor Yellow
Write-Host ('    gh release create {0} "dist\{1}.zip" --title "{2}" --notes-file "dist\{1}.notes.md"' -f "master-script/v$Version", $name, "Scripted release $Version")
Write-Host ''

exit 0
