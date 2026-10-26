<#
    Media Optimizer - interactive launcher (the double-click entry point).

    Wraps optimize.ps1 with a file-or-folder prompt, path validation and a
    dependency check scoped to what is actually being processed: a folder of MP4
    only needs ffmpeg, a folder of JPG only needs cjpegli, and a mixed folder
    needs both. exiftool is always optional.

    optimize.ps1 is called through its own -Path contract and nothing else.

    Usage
        MediaOptimizer.cmd                    prompts for a folder or file
        MediaOptimizer.cmd "D:\Photos"        skips the prompt
        Drop a folder or file onto MediaOptimizer.cmd in Explorer - same as above.

    Written for Windows PowerShell 5.1 (no PS7-only syntax).
#>

[CmdletBinding()]
param(
    [string]$Path
)

$ErrorActionPreference = 'Stop'

$enginePath = Join-Path -Path $PSScriptRoot -ChildPath 'optimize.ps1'
$rule = '-' * 62

try { $Host.UI.RawUI.WindowTitle = 'Media Optimizer' } catch { }

# ---------------------------------------------------------------- presentation

function Show-Banner {
    Write-Host ''
    Write-Host '  MEDIA OPTIMIZER' -ForegroundColor Cyan
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host '  Shrinks videos and photos - a whole folder, or a single file.'
    Write-Host '  Results go into an "optimized" subfolder beside it, so your'
    Write-Host '  originals are never changed or deleted.'
}

function Show-PromptHelp {
    Write-Host ''
    Write-Host '  Drag a folder or a file into this window, or paste its path,' -ForegroundColor White
    Write-Host '  then press Enter.' -ForegroundColor White
    Write-Host ''
    Write-Host '  Pressing Enter on an empty line quits.' -ForegroundColor DarkGray
    Write-Host ''
}

function Format-Count {
    param(
        [int]$Count,
        [string]$Singular
    )

    if ($Count -eq 1) {
        return "1 $Singular"
    }

    return "$Count ${Singular}s"
}

# Explorer wraps dragged paths in quotes; tolerate those and expand %VARS%.
function Resolve-Target {
    param([string]$InputText)

    $value = $InputText.Trim()

    if ($value.Length -ge 2) {
        $first = $value.Substring(0, 1)
        $last = $value.Substring($value.Length - 1, 1)

        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $value = $value.Substring(1, $value.Length - 2).Trim()
        }
    }

    $value = [Environment]::ExpandEnvironmentVariables($value)

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $value)) {
        throw "Not found: $value"
    }

    $item = Get-Item -LiteralPath $value

    return [pscustomobject]@{
        FullName = $item.FullName
        IsFile   = -not $item.PSIsContainer
    }
}

# Counts what the engine will actually process, using the same exclusion rules,
# so the preflight can never promise more than the run delivers.
function Get-MediaSummary {
    param($Target)

    $summary = [pscustomobject]@{
        VideoCount = 0
        ImageCount = 0
        Found      = $false
    }

    if ($Target.IsFile) {
        $extension = [System.IO.Path]::GetExtension($Target.FullName).ToLowerInvariant()

        if ($extension -eq '.mp4' -or $extension -eq '.mov') {
            $summary.VideoCount = 1
        }
        elseif ($extension -eq '.jpg' -or $extension -eq '.jpeg') {
            $summary.ImageCount = 1
        }

        $summary.Found = ($summary.VideoCount + $summary.ImageCount) -gt 0
        return $summary
    }

    foreach ($file in (Get-ChildItem -LiteralPath $Target.FullName -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($file.FullName -match '[\\/]+optimized([\\/]|$)') {
            continue
        }

        if ($file.Name -like 'opt_*') {
            continue
        }

        $extension = $file.Extension.ToLowerInvariant()

        if ($extension -eq '.mp4' -or $extension -eq '.mov') {
            $summary.VideoCount++
        }
        elseif ($extension -eq '.jpg' -or $extension -eq '.jpeg') {
            $summary.ImageCount++
        }
    }

    $summary.Found = ($summary.VideoCount + $summary.ImageCount) -gt 0
    return $summary
}

function Format-MediaSummary {
    param($Summary)

    $parts = @()

    if ($Summary.VideoCount -gt 0) {
        $parts += (Format-Count -Count $Summary.VideoCount -Singular 'video')
    }

    if ($Summary.ImageCount -gt 0) {
        $parts += (Format-Count -Count $Summary.ImageCount -Singular 'photo')
    }

    return ($parts -join ', ')
}

# Returns $true when the run can start. Only tools this selection needs block it.
function Test-Requirements {
    param($Summary)

    $required = @()
    $optional = @()

    if ($Summary.VideoCount -gt 0) {
        if (-not (Get-Command -Name 'ffmpeg' -ErrorAction SilentlyContinue)) {
            $required += [pscustomobject]@{
                Tool    = 'ffmpeg'
                Reason  = "needed to shrink $(Format-Count -Count $Summary.VideoCount -Singular 'video')"
                Install = 'winget install Gyan.FFmpeg'
            }
        }
        elseif (-not (Get-Command -Name 'ffprobe' -ErrorAction SilentlyContinue)) {
            $optional += [pscustomobject]@{
                Tool    = 'ffprobe'
                Reason  = 'video progress percentages will be unavailable'
                Install = 'winget install Gyan.FFmpeg'
            }
        }
    }

    if ($Summary.ImageCount -gt 0 -and -not (Get-Command -Name 'cjpegli' -ErrorAction SilentlyContinue)) {
        $required += [pscustomobject]@{
            Tool    = 'cjpegli'
            Reason  = "needed to shrink $(Format-Count -Count $Summary.ImageCount -Singular 'photo')"
            Install = 'download from github.com/libjxl/libjxl/releases'
        }
    }

    if (-not (Get-Command -Name 'exiftool' -ErrorAction SilentlyContinue)) {
        $optional += [pscustomobject]@{
            Tool    = 'exiftool'
            Reason  = 'timestamps and photo metadata will not be preserved'
            Install = 'winget install PhilHarvey.ExifTool'
        }
    }

    if ($required.Count -gt 0) {
        Write-Host ''
        Write-Host '  Missing a tool that this selection needs:' -ForegroundColor Red

        foreach ($item in $required) {
            Write-Host ''
            Write-Host ("    {0}  - {1}" -f $item.Tool, $item.Reason) -ForegroundColor Yellow
            Write-Host ("      {0}" -f $item.Install) -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host '  Install it, then run this window again.' -ForegroundColor White
        return $false
    }

    if ($optional.Count -gt 0) {
        Write-Host ''
        Write-Host '  Heads up:' -ForegroundColor Yellow

        foreach ($item in $optional) {
            Write-Host ''
            Write-Host ("    {0}  - {1}" -f $item.Tool, $item.Reason) -ForegroundColor Yellow
            Write-Host ("      {0}" -f $item.Install) -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host '  Press Enter to continue, or Ctrl+C to stop.' -ForegroundColor White
        [void](Read-Host)
    }

    return $true
}

# ------------------------------------------------------------------------ main

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    Write-Host ''
    Write-Host '  [ERROR] optimize.ps1 is missing from this folder.' -ForegroundColor Red
    Write-Host '          MediaOptimizer.cmd, launcher.ps1 and optimize.ps1 must stay' -ForegroundColor Red
    Write-Host '          together in the same folder.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

Show-Banner

$target = $null
$summary = $null

# A folder or file dropped onto the .cmd arrives here as -Path.
if (-not [string]::IsNullOrWhiteSpace($Path)) {
    try {
        $candidate = Resolve-Target -InputText $Path
    }
    catch {
        Write-Host ''
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        $candidate = $null
    }

    if ($null -ne $candidate) {
        $candidateSummary = Get-MediaSummary -Target $candidate

        if ($candidateSummary.Found) {
            $target = $candidate
            $summary = $candidateSummary
        }
        else {
            Write-Host ''
            Write-Host '  No MP4, MOV, JPG or JPEG found in that selection.' -ForegroundColor Yellow
        }
    }
}

if ($null -eq $target) {
    Show-PromptHelp

    while ($null -eq $target) {
        $entered = Read-Host '  Folder or file'

        if ([string]::IsNullOrWhiteSpace($entered)) {
            Write-Host ''
            Write-Host '  Nothing to do. Closing.' -ForegroundColor DarkGray
            exit 0
        }

        try {
            $candidate = Resolve-Target -InputText $entered
        }
        catch {
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            Write-Host '  Try again, or press Enter to quit.' -ForegroundColor DarkGray
            Write-Host ''
            continue
        }

        $candidateSummary = Get-MediaSummary -Target $candidate

        if (-not $candidateSummary.Found) {
            Write-Host '  No MP4, MOV, JPG or JPEG found there.' -ForegroundColor Yellow
            Write-Host '  Try another folder or file, or press Enter to quit.' -ForegroundColor DarkGray
            Write-Host ''
            continue
        }

        $target = $candidate
        $summary = $candidateSummary
    }
}

Write-Host ''

if ($target.IsFile) {
    Write-Host "  File:   $($target.FullName)" -ForegroundColor Cyan
}
else {
    Write-Host "  Folder: $($target.FullName)" -ForegroundColor Cyan
}

Write-Host "  Media:  $(Format-MediaSummary -Summary $summary)" -ForegroundColor Cyan
Write-Host "  $rule" -ForegroundColor DarkGray

if (-not (Test-Requirements -Summary $summary)) {
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host '  Starting. Press Ctrl+C to cancel.' -ForegroundColor DarkGray
Write-Host ''

$LASTEXITCODE = 0
$exitCode = 0

try {
    & $enginePath -Path $target.FullName
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Host ''
    Write-Host "  Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

if ($null -eq $exitCode) {
    $exitCode = 0
}

exit $exitCode
