<#
    Media Optimizer - interactive launcher (the double-click entry point).

    Wraps optimize.ps1 with a folder prompt, friendly wording and a dependency
    heads-up. optimize.ps1 is deliberately NOT modified: it stays the behavioural
    reference for the .NET port (see docs/implementation-plan.md).

    Usage
        MediaOptimizer.cmd                   prompts for a folder
        MediaOptimizer.cmd "D:\Photos"       skips the prompt
        Drop a folder onto MediaOptimizer.cmd in Explorer - same as above.

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
    Write-Host '  Shrinks the videos and photos in a folder.'
    Write-Host '  Results go into an "optimized" subfolder - your originals are'
    Write-Host '  never changed or deleted.'
}

function Show-PromptHelp {
    Write-Host ''
    Write-Host '  Drag a folder into this window, or paste its path, then press' -ForegroundColor White
    Write-Host '  Enter.' -ForegroundColor White
    Write-Host ''
    Write-Host '  Pressing Enter on an empty line quits.' -ForegroundColor DarkGray
    Write-Host ''
}

# Explorer wraps dragged paths in quotes; tolerate those and a stray trailing
# separator, and expand %VARS%.
function Resolve-TargetFolder {
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

    if (Test-Path -LiteralPath $value -PathType Container) {
        return (Get-Item -LiteralPath $value).FullName
    }

    if (Test-Path -LiteralPath $value -PathType Leaf) {
        throw "That is a file, not a folder: $value"
    }

    throw "That folder does not exist: $value"
}

# Informational only - optimize.ps1 still decides what each file needs.
function Show-MissingTools {
    $checks = @(
        @{
            Label   = 'ffmpeg + ffprobe'
            Tools   = @('ffmpeg', 'ffprobe')
            Need    = 'shrink videos'
            Install = 'winget install Gyan.FFmpeg'
        },
        @{
            Label   = 'cjpegli'
            Tools   = @('cjpegli')
            Need    = 'shrink photos'
            Install = 'github.com/libjxl/libjxl/releases'
        },
        @{
            Label   = 'exiftool'
            Tools   = @('exiftool')
            Need    = 'keep original timestamps'
            Install = 'winget install PhilHarvey.ExifTool'
        }
    )

    $missing = @()

    foreach ($check in $checks) {
        $present = $false

        foreach ($tool in $check.Tools) {
            if (Get-Command -Name $tool -ErrorAction SilentlyContinue) {
                $present = $true
            }
        }

        if (-not $present) {
            $missing += $check
        }
    }

    if ($missing.Count -eq 0) {
        return
    }

    Write-Host ''
    Write-Host '  Some helper tools are missing on this PC:' -ForegroundColor Yellow

    foreach ($check in $missing) {
        Write-Host ''
        Write-Host ("    {0}  - for {1}" -f $check.Label, $check.Need) -ForegroundColor Yellow
        Write-Host ("      {0}" -f $check.Install) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  You can continue anyway; only the files that need a missing' -ForegroundColor DarkGray
    Write-Host '  tool will fail.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Press Enter to continue, or Ctrl+C to stop and install first.' -ForegroundColor White
    [void](Read-Host)
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

# A folder dropped onto the .cmd arrives here as -Path.
if (-not [string]::IsNullOrWhiteSpace($Path)) {
    try {
        $target = Resolve-TargetFolder -InputText $Path
    }
    catch {
        Write-Host ''
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $target) {
    Show-PromptHelp

    while (-not $target) {
        $entered = Read-Host '  Folder'

        if ([string]::IsNullOrWhiteSpace($entered)) {
            Write-Host ''
            Write-Host '  Nothing to do. Closing.' -ForegroundColor DarkGray
            exit 0
        }

        try {
            $target = Resolve-TargetFolder -InputText $entered
        }
        catch {
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            Write-Host '  Try again, or press Enter to quit.' -ForegroundColor DarkGray
            Write-Host ''
        }
    }
}

Write-Host ''
Write-Host "  Folder: $target" -ForegroundColor Cyan
Write-Host "  $rule" -ForegroundColor DarkGray

Show-MissingTools

Write-Host ''
Write-Host '  Starting. Press Ctrl+C to cancel.' -ForegroundColor DarkGray
Write-Host ''

$LASTEXITCODE = 0
$exitCode = 0

try {
    & $enginePath -Path $target
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
