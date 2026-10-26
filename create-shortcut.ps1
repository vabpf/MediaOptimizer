<#
.SYNOPSIS
    Installs Media Optimizer for the current user and adds it to the Start menu.

.DESCRIPTION
    Copies the runtime files to %LOCALAPPDATA%\Programs\MediaOptimizer and creates
    a Start menu shortcut that points at that copy, so the folder you downloaded
    can be deleted afterwards.

    This is a per-user install: no admin rights, no registry keys, no services.
    Uninstalling is -Remove, or simply deleting the folder and the shortcut.

    Windows does not allow an application to pin itself to Start, so the final
    "Pin to Start" click has to be made by the user. The installed shortcut
    appears under Start > All apps and in Start search straight away.

.PARAMETER Remove
    Removes the Start menu shortcut and the installed files.

.PARAMETER NoInstall
    Skips the copy and points the shortcut at this folder instead. Useful for a
    portable setup, but moving or renaming the folder breaks the shortcut.

.EXAMPLE
    .\create-shortcut.ps1

.EXAMPLE
    .\create-shortcut.ps1 -Remove
#>

[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'

$appTitle   = 'Media Optimizer'
$appFolder  = 'MediaOptimizer'
$entryName  = 'MediaOptimizer.cmd'
$iconName   = 'MediaOptimizer.ico'

# Everything the installed copy needs to be self-sufficient, including this
# installer, so -Remove can be run from the installed folder too.
$runtimeFiles = @(
    'MediaOptimizer.cmd'
    'Create-Shortcut.cmd'
    'launcher.ps1'
    'create-shortcut.ps1'
    'optimize.ps1'
    'optimize.cmd'
    'MediaOptimizer.ico'
    'README.txt'
)

$here       = $PSScriptRoot.TrimEnd('\')
$installDir = Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' $appFolder)
$startDir   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcut   = Join-Path $startDir "$appTitle.lnk"

function Write-Detail {
    param([string]$Text)

    Write-Host "  $Text"
}

function Get-NormalizedPath {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

try {
    # ------------------------------------------------------------- uninstall
    if ($Remove) {
        if (Test-Path -LiteralPath $shortcut) {
            Remove-Item -LiteralPath $shortcut -Force
            Write-Detail "Removed $shortcut"
        }
        else {
            Write-Detail 'No Start menu shortcut to remove.'
        }

        # Only touch the install folder if it really is ours.
        $installed = (Test-Path -LiteralPath $installDir) -and (Test-Path -LiteralPath (Join-Path $installDir $entryName))

        if ($installed) {
            $selfDeleting = [string]::Equals(
                (Get-NormalizedPath $installDir),
                (Get-NormalizedPath $here),
                [StringComparison]::OrdinalIgnoreCase
            )

            if ($selfDeleting) {
                # cmd.exe reads a batch file line by line, so deleting the folder
                # this script is running from makes the wrapper fail mid-run.
                # Defer the delete to a helper that waits for this console to exit.
                $helper = Join-Path $env:TEMP ('mo-remove-' + [guid]::NewGuid().ToString('N') + '.ps1')
                $parentId = 0

                try {
                    $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
                }
                catch {
                    $parentId = 0
                }

                $wait = if ($parentId -gt 0) {
                    "while (Get-Process -Id $parentId -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }"
                }
                else {
                    'Start-Sleep -Seconds 5'
                }

                Set-Content -LiteralPath $helper -Encoding ASCII -Value @(
                    $wait
                    "Remove-Item -LiteralPath `"$installDir`" -Recurse -Force -ErrorAction SilentlyContinue"
                    'Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue'
                )

                Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
                    '-NoProfile'
                    '-ExecutionPolicy'
                    'Bypass'
                    '-WindowStyle'
                    'Hidden'
                    '-File'
                    $helper
                )

                Write-Detail "Queued removal of $installDir"
                Write-Host ''
                Write-Host '  The files are deleted once this window closes.' -ForegroundColor DarkGray
            }
            else {
                Remove-Item -LiteralPath $installDir -Recurse -Force
                Write-Detail "Removed $installDir"
            }
        }
        else {
            Write-Detail "Nothing installed at $installDir"
        }

        Write-Host ''
        Write-Host '  Media Optimizer has been removed.' -ForegroundColor Green
        Write-Host ''
        exit 0
    }

    # --------------------------------------------------------------- install
    if (-not (Test-Path -LiteralPath (Join-Path $here $entryName))) {
        throw "$entryName was not found next to this script. Keep the release files together in one folder."
    }

    $alreadyInstalled = [string]::Equals(
        (Get-NormalizedPath $installDir),
        (Get-NormalizedPath $here),
        [StringComparison]::OrdinalIgnoreCase
    )

    if ($NoInstall -or $alreadyInstalled) {
        $targetDir = $here
    }
    else {
        $targetDir = $installDir
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

        foreach ($name in $runtimeFiles) {
            $source = Join-Path $here $name

            if (Test-Path -LiteralPath $source) {
                Copy-Item -LiteralPath $source -Destination (Join-Path $targetDir $name) -Force
            }
        }
    }

    $targetEntry = Join-Path $targetDir $entryName
    $targetIcon  = Join-Path $targetDir $iconName

    if (-not (Test-Path -LiteralPath $startDir)) {
        New-Item -ItemType Directory -Path $startDir -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)

    $link.TargetPath       = $targetEntry
    $link.WorkingDirectory = $targetDir
    $link.Description      = 'Shrink the videos and photos in a folder, or a single file'
    $link.WindowStyle      = 1

    if (Test-Path -LiteralPath $targetIcon) {
        $link.IconLocation = "$targetIcon,0"
    }

    $link.Save()

    # Read the shortcut back rather than trusting that Save() did the right thing.
    $saved = $shell.CreateShortcut($shortcut)

    if (-not (Test-Path -LiteralPath $saved.TargetPath)) {
        throw "The shortcut was written but its target does not exist: $($saved.TargetPath)"
    }

    # ---------------------------------------------------------------- report
    Write-Host ''
    Write-Host '  Media Optimizer is ready.' -ForegroundColor Green
    Write-Host ''
    Write-Detail "Start menu:  $shortcut"
    Write-Detail "Runs:        $($saved.TargetPath)"
    Write-Host ''

    Write-Host '  To pin it to Start:' -ForegroundColor Yellow
    Write-Host '    1. Press the Windows key and type: media optimizer'
    Write-Host '    2. Right-click the result'
    Write-Host '    3. Pin to Start'
    Write-Host ''
    Write-Host '  Windows does not let an app pin itself, so that last click is yours.' -ForegroundColor DarkGray

    if ($targetDir -eq $here) {
        Write-Host ''
        Write-Host '  Note: the shortcut points at this folder, so do not move or rename it.' -ForegroundColor DarkGray
        Write-Host '        Re-run this file from the new location to fix the shortcut.' -ForegroundColor DarkGray
    }
    else {
        Write-Host ''
        Write-Host '  The folder you ran this from can now be deleted.' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  To undo everything:  Create-Shortcut.cmd -Remove' -ForegroundColor DarkGray
    Write-Host ''

    exit 0
}
catch {
    Write-Host ''
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    exit 1
}
