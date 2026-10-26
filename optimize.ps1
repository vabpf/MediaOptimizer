param(
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Continue'

# ============================================================
# PATH CONFIGURATION
# ============================================================

$Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Host "[ERROR] Folder not found: $Path" -ForegroundColor Red
    exit 1
}

$baseDir = (Get-Item -LiteralPath $Path).FullName
$outputDir = Join-Path $baseDir 'optimized'

# ============================================================
# MEDIA OPTIMIZATION TOOL
# ============================================================

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "              MEDIA OPTIMIZATION TOOL" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# Prevent the output folder from being included in the input scan.
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Write-Host ""
Write-Host "Target Directory: $baseDir" -ForegroundColor Cyan
Write-Host "Output Directory: $outputDir" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray

# ============================================================
# DEPENDENCY CHECKS
# ============================================================

$ffmpegAvailable = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)
$ffprobeAvailable = [bool](Get-Command ffprobe -ErrorAction SilentlyContinue)
$cjpegliAvailable = [bool](Get-Command cjpegli -ErrorAction SilentlyContinue)
$exiftoolAvailable = [bool](Get-Command exiftool -ErrorAction SilentlyContinue)

# ============================================================
# RECURSIVE FILE DISCOVERY
# ============================================================

Write-Host "[INFO] Scanning folder and subfolders..." -ForegroundColor Yellow

try {
    $files = @(
        Get-ChildItem -LiteralPath $baseDir -Recurse -File -ErrorAction Stop |
            Where-Object {
                $_.Extension -match '^\.(mp4|mov|jpg|jpeg)$' -and
                $_.FullName -notmatch '[\\/]+optimized([\\/]|$)' -and
                $_.Name -notlike 'opt_*'
            }
    )
}
catch {
    Write-Host "[ERROR] Could not scan the selected folder." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}

$totalFiles = $files.Count

Write-Host "[INFO] Found $totalFiles supported file(s)." -ForegroundColor Green

if ($totalFiles -eq 0) {
    Write-Host ""
    Write-Host "[WARNING] No supported files found." -ForegroundColor Yellow
    Write-Host "Supported extensions: MP4, MOV, JPG, JPEG" -ForegroundColor Yellow
    Write-Host "Check the selected folder and its subfolders." -ForegroundColor Yellow
    return
}

$hasVideo = [bool]($files | Where-Object {
    $_.Extension -match '^\.(mp4|mov)$'
})

$hasImage = [bool]($files | Where-Object {
    $_.Extension -match '^\.(jpg|jpeg)$'
})

if ($hasVideo -and !$ffmpegAvailable) {
    Write-Host "[ERROR] FFmpeg was not found in PATH." -ForegroundColor Red
    return
}

if ($hasVideo -and !$ffprobeAvailable) {
    Write-Host "[WARNING] ffprobe not found. Video percentage may be unavailable." -ForegroundColor Yellow
}

if ($hasImage -and !$cjpegliAvailable) {
    Write-Host "[ERROR] cjpegli was not found in PATH." -ForegroundColor Red
    return
}

if (!$exiftoolAvailable) {
    Write-Host "[INFO] exiftool not found. Metadata timestamp updates are disabled." -ForegroundColor DarkGray
}

# ============================================================
# HELPERS
# ============================================================

function Format-Time {
    param([double]$Seconds)

    if (
        $Seconds -lt 0 -or
        [double]::IsNaN($Seconds) -or
        [double]::IsInfinity($Seconds)
    ) {
        return "Calculating..."
    }

    $ts = [TimeSpan]::FromSeconds($Seconds)

    if ($ts.TotalHours -ge 1) {
        return '{0:D2}h {1:D2}m' -f [int]$ts.TotalHours, $ts.Minutes
    }

    return '{0:D2}m {1:D2}s' -f [int]$ts.TotalMinutes, $ts.Seconds
}

function Get-BatchETA {
    param(
        [string]$CurrentType = '',
        [double]$CurrentBytes = 0,
        [double]$CurrentPercent = 0
    )

    $remainingVideo = [Math]::Max(
        [double]0, [double]$totalVideoBytes - [double]$completedVideoBytes
    )

    $remainingImages = [Math]::Max(
        [double]0, [double]$totalImageBytes - [double]$completedImageBytes
    )

    # Estimate the unfinished portion of the active file.
    if ($CurrentType -eq 'video') {
        $remainingVideo = [Math]::Max(
            [double]0,
            [double]$remainingVideo - ([double]$CurrentBytes * [double]$CurrentPercent / 100.0)
        )
    }
    elseif ($CurrentType -eq 'image') {
        # Image processing does not expose reliable live byte progress.
        # Its size remains counted until the image finishes.
    }

    $etaSeconds = 0.0
    $hasRate = $false

    # Video rate: completed input bytes per second.
    if ($remainingVideo -gt 0 -and $videoElapsedSeconds -gt 0) {
        $videoRate = $completedVideoBytes / $videoElapsedSeconds

        if ($videoRate -gt 0) {
            $etaSeconds += $remainingVideo / $videoRate
            $hasRate = $true
        }
    }

    # Image rate: completed input bytes per second.
    if ($remainingImages -gt 0 -and $imageElapsedSeconds -gt 0) {
        $imageRate = $completedImageBytes / $imageElapsedSeconds

        if ($imageRate -gt 0) {
            $etaSeconds += $remainingImages / $imageRate
            $hasRate = $true
        }
    }

    # If the current type has no historical rate yet, use the
    # overall observed rate as a temporary fallback.
    if (!$hasRate) {
        $completedBytes = $completedVideoBytes + $completedImageBytes
        $elapsedByType = $videoElapsedSeconds + $imageElapsedSeconds

        if ($completedBytes -gt 0 -and $elapsedByType -gt 0) {
            $remainingBytes = $remainingVideo + $remainingImages
            $etaSeconds = $remainingBytes / ($completedBytes / $elapsedByType)
            $hasRate = $true
        }
    }

    if (!$hasRate) {
        return 'Calculating...'
    }

    return Format-Time $etaSeconds
}

# ============================================================
# PROCESSING
# ============================================================

$currentIndex = 0
$successCount = 0
$failureCount = 0

# Per-success records used by the summary statistics.
# Must be a growable list: a fixed-size array cannot accept .Add().
$successfulOutputs = [System.Collections.Generic.List[object]]::new()

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Input sizes by media type
$totalVideoBytes = [double](($files |
    Where-Object { $_.Extension -match '^\.(mp4|mov)$' } |
    Measure-Object -Property Length -Sum).Sum)

$totalImageBytes = [double](($files |
    Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' } |
    Measure-Object -Property Length -Sum).Sum)

# Track completed input bytes and actual processing time by type
$completedVideoBytes = 0.0
$completedImageBytes = 0.0
$videoElapsedSeconds = 0.0
$imageElapsedSeconds = 0.0

foreach ($file in $files) {
    $currentIndex++
    $fileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $inputPath = $file.FullName
    $extension = $file.Extension.ToLowerInvariant()

    # Keep the input folder structure under optimized.
    $relativeDirectory = $file.DirectoryName.Substring($baseDir.Length).TrimStart('\', '/')

    if ($relativeDirectory) {
        $targetSubDir = Join-Path $outputDir $relativeDirectory
    }
    else {
        $targetSubDir = $outputDir
    }

    New-Item -ItemType Directory -Path $targetSubDir -Force | Out-Null

    $outputPath = Join-Path $targetSubDir $file.Name

    $logPath = [System.IO.Path]::GetTempFileName()
    $fileSucceeded = $false

    try {
        # ----------------------------------------------------
        # VIDEO: MP4 / MOV
        # ----------------------------------------------------
        if ($extension -in @('.mp4', '.mov')) {
            $durationSeconds = 0.0

            if ($ffprobeAvailable) {
                $durationText = & ffprobe `
                    -v error `
                    -show_entries format=duration `
                    -of default=noprint_wrappers=1:nokey=1 `
                    $inputPath 2>$null

                $parsedDuration = 0.0

                if ([double]::TryParse(
                    [string]$durationText,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$parsedDuration
                )) {
                    $durationSeconds = $parsedDuration
                }
            }

            $videoPercent = 0
            $videoSpeed = ''
            $lastUpdate = [DateTime]::MinValue

            $ffmpegArgs = @(
                '-y',
                '-hide_banner',
                '-nostats',
                '-loglevel', 'error',
                '-progress', 'pipe:1',
                '-hwaccel', 'd3d11va',
                '-i', $inputPath,
                '-map_metadata', '0',
                '-vf', 'format=nv12',
                '-c:v', 'hevc_amf',
                '-usage', 'transcoding',
                '-quality', 'balanced',
                '-rc', 'cqp',
                '-qp_i', '28',
                '-qp_p', '28',
                '-qp_b', '30',
                '-movflags', 'use_metadata_tags+write_colr',
                '-c:a', 'aac',
                '-b:a', '128k',
                $outputPath
            )

            # FFmpeg stdout carries progress records.
            # FFmpeg stderr is captured for errors only.
            & ffmpeg @ffmpegArgs 2> $logPath |
                ForEach-Object {
                    $record = [string]$_

                    if ($record -match '^out_time_ms=(\d+)$') {
                        # FFmpeg reports this value in microseconds.
                        $encodedSeconds = [double]$Matches[1] / 1000000.0

                        if ($durationSeconds -gt 0) {
                            $videoPercent = [Math]::Min(
                                [double]100,
                                [Math]::Max(
                                    [double]0,
                                    [int](100 * $encodedSeconds / $durationSeconds)
                                )
                            )
                        }
                    }
                    elseif ($record -match '^speed=(.+)$') {
                        $videoSpeed = $Matches[1].Trim()
                    }
                    elseif ($record -eq 'progress=end') {
                        $videoPercent = 100
                    }

                    $now = [DateTime]::Now

                    if (
                        ($now - $lastUpdate).TotalMilliseconds -ge 250 -or
                        $record -eq 'progress=end'
                    ) {
                        $lastUpdate = $now

                        if ($durationSeconds -gt 0) {
                            $overallPercent = [int](
                                100 * (
                                    ($currentIndex - 1) +
                                    ($videoPercent / 100.0)
                                ) / $totalFiles
                            )
                        }
                        else {
                            $overallPercent = [int](
                                100 * ($currentIndex - 1) / $totalFiles
                            )
                        }

                        $status = "[$currentIndex/$totalFiles] $($file.Name)"

                        if ($durationSeconds -gt 0) {
                            $status += " | Video: $videoPercent%"
                        }
                        else {
                            $status += " | Encoding video..."
                        }

                        if ($videoSpeed) {
                            $status += " | Speed: $videoSpeed"
                        }

                        $batchETA = Get-BatchETA `
                            -CurrentType 'video' `
                            -CurrentBytes $file.Length `
                            -CurrentPercent $videoPercent

                        $status += " | Batch ETA: $batchETA"

                        Write-Progress `
                            -Id 1 `
                            -Activity 'Optimizing Media Files' `
                            -Status $status `
                            -PercentComplete $overallPercent
                    }
                }

            $ffmpegExitCode = $LASTEXITCODE

            if ($ffmpegExitCode -ne 0) {
                $diagnostics = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
                throw "FFmpeg failed with exit code $ffmpegExitCode.`n$diagnostics"
            }

            if (!(Test-Path -LiteralPath $outputPath -PathType Leaf)) {
                throw "FFmpeg exited without producing the output file."
            }

            if ($exiftoolAvailable) {
                & exiftool -q -q `
                    '-FileModifyDate<CreateDate' `
                    '-FileCreateDate<CreateDate' `
                    $outputPath *> $logPath

                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[WARNING] Could not update video timestamps: $($file.Name)" -ForegroundColor Yellow
                }
            }

            $fileSucceeded = $true
        }

        # ----------------------------------------------------
        # IMAGE: JPG / JPEG
        # ----------------------------------------------------
        elseif ($extension -in @('.jpg', '.jpeg')) {
            $overallPercent = [int](
                100 * ($currentIndex - 1) / $totalFiles
            )

            $status = "[$currentIndex/$totalFiles] $($file.Name) | Optimizing image..."
            $batchETA = Get-BatchETA -CurrentType 'image'
            $status += " | Batch ETA: $batchETA"

            Write-Progress `
                -Id 1 `
                -Activity 'Optimizing Media Files' `
                -Status $status `
                -PercentComplete $overallPercent

            & cjpegli $inputPath $outputPath -q 85 *> $logPath

            $imageExitCode = $LASTEXITCODE

            if ($imageExitCode -ne 0) {
                $diagnostics = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
                throw "cjpegli failed with exit code $imageExitCode.`n$diagnostics"
            }

            if (!(Test-Path -LiteralPath $outputPath -PathType Leaf)) {
                throw "cjpegli exited without producing the output file."
            }

            if ($exiftoolAvailable) {
                & exiftool -q -q `
                    -tagsFromFile $inputPath `
                    '-all:all>all:all' `
                    '-FileModifyDate<DateTimeOriginal' `
                    '-FileCreateDate<DateTimeOriginal' `
                    -overwrite_original `
                    $outputPath *> $logPath

                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[WARNING] Could not copy image metadata: $($file.Name)" -ForegroundColor Yellow
                }
            }

            $fileSucceeded = $true
        }

        # ----------------------------------------------------
        # RESULT
        # ----------------------------------------------------
        if ($fileSucceeded) {
            $successCount++

            $inputBytes = [double]$file.Length
            $outputBytes = [double](Get-Item -LiteralPath $outputPath).Length
            $successfulOutputs.Add([PSCustomObject]@{
                InputBytes  = $inputBytes
                OutputBytes = $outputBytes
                Extension   = $extension
            })

            if ($inputBytes -gt 0) {
                $savedPercent = [Math]::Round(
                    100 * ($inputBytes - $outputBytes) / $inputBytes,
                    1
                )
            }
            else {
                $savedPercent = 0
            }

            $savedMB = [Math]::Round(
                ($inputBytes - $outputBytes) / 1MB,
                2
            )

            Write-Progress `
                -Id 1 `
                -Activity 'Optimizing Media Files' `
                -Status "Completed: $($file.Name) | Saved $savedMB MB ($savedPercent%)" `
                -PercentComplete ([int](100 * $currentIndex / $totalFiles))

            Write-Host (
                "[OK] [{0}/{1}] {2} | Saved {3} MB ({4}%)" -f
                $currentIndex, $totalFiles, $file.Name, $savedMB, $savedPercent
            ) -ForegroundColor Green
        }
    }
    catch {
        $failureCount++

        Write-Progress -Id 1 -Activity 'Optimizing Media Files' -Completed

        Write-Host ""
        Write-Host "[ERROR] [$currentIndex/$totalFiles] $($file.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        # Keep the captured diagnostic output available for troubleshooting.
        $diagnostics = Get-Content $logPath -Raw -ErrorAction SilentlyContinue

        if (![string]::IsNullOrWhiteSpace($diagnostics)) {
            Write-Host $diagnostics -ForegroundColor DarkRed
        }
    }
    finally {
        $fileStopwatch.Stop()

        # Include attempted files in the rate history, even if they fail.
        # This prevents failed files from remaining in the ETA indefinitely.
        if ($extension -in @('.mp4', '.mov')) {
            $completedVideoBytes += [double]$file.Length
            $videoElapsedSeconds += $fileStopwatch.Elapsed.TotalSeconds
        }
        elseif ($extension -in @('.jpg', '.jpeg')) {
            $completedImageBytes += [double]$file.Length
            $imageElapsedSeconds += $fileStopwatch.Elapsed.TotalSeconds
        }

        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }
}


# ============================================================
# SUMMARY STATISTICS
# ============================================================

$originalBytes = 0.0
$outputBytes = 0.0
$successfulVideoCount = 0
$successfulImageCount = 0
$videoOriginalBytes = 0.0
$videoOutputBytes = 0.0
$imageOriginalBytes = 0.0
$imageOutputBytes = 0.0

# Aggregate only files successfully processed in this run.
# This avoids counting stale outputs left by previous runs or failed attempts.
foreach ($result in $successfulOutputs) {
    $originalBytes += $result.InputBytes
    $outputBytes += $result.OutputBytes

    if ($result.Extension -in @('.mp4', '.mov')) {
        $successfulVideoCount++
        $videoOriginalBytes += $result.InputBytes
        $videoOutputBytes += $result.OutputBytes
    }
    elseif ($result.Extension -in @('.jpg', '.jpeg')) {
        $successfulImageCount++
        $imageOriginalBytes += $result.InputBytes
        $imageOutputBytes += $result.OutputBytes
    }
}

$savedBytes = $originalBytes - $outputBytes

$savedPercent = if ($originalBytes -gt 0) {
    100 * $savedBytes / $originalBytes
}
else {
    0
}

$averageSavedPerFile = if ($successCount -gt 0) {
    $savedBytes / $successCount
}
else {
    0
}

$averageTime = if ($totalFiles -gt 0) {
    $stopwatch.Elapsed.TotalSeconds / $totalFiles
}
else {
    0
}

$processingRate = if ($stopwatch.Elapsed.TotalSeconds -gt 0) {
    $originalBytes / $stopwatch.Elapsed.TotalSeconds
}
else {
    0
}

function Format-Storage {
    param([double]$Bytes)

    $absBytes = [Math]::Abs($Bytes)
    $sign = if ($Bytes -lt 0) { '-' } else { '' }

    if ($absBytes -ge 1GB) {
        return '{0}{1:N2} GB' -f $sign, ($absBytes / 1GB)
    }
    elseif ($absBytes -ge 1MB) {
        return '{0}{1:N2} MB' -f $sign, ($absBytes / 1MB)
    }
    elseif ($absBytes -ge 1KB) {
        return '{0}{1:N2} KB' -f $sign, ($absBytes / 1KB)
    }

    return '{0}{1:N0} bytes' -f $sign, $absBytes
}


# ============================================================
# FINAL SUMMARY
# ============================================================

$stopwatch.Stop()
Write-Progress -Id 1 -Activity 'Optimizing Media Files' -Completed

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "                 PROCESSING SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host "Files" -ForegroundColor Yellow
Write-Host ("  Total files:             {0}" -f $totalFiles)
Write-Host ("  Successful:              {0}" -f $successCount) -ForegroundColor Green
Write-Host ("  Failed:                  {0}" -f $failureCount) -ForegroundColor $(if ($failureCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ("  Videos:                  {0} ({1} outputs)" -f @($files | Where-Object { $_.Extension -match '^\.(mp4|mov)$' }).Count, $successfulVideoCount)
Write-Host ("  Images:                  {0} ({1} outputs)" -f @($files | Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' }).Count, $successfulImageCount)

Write-Host ""
Write-Host "Storage" -ForegroundColor Yellow
Write-Host ("  Original size (successful files): {0}" -f (Format-Storage $originalBytes))
Write-Host ("  Output size:             {0}" -f (Format-Storage $outputBytes))

if ($savedBytes -gt 0) {
    Write-Host ("  Space saved:             {0} ({1:N1}%)" -f (Format-Storage $savedBytes), $savedPercent) -ForegroundColor Green
}
elseif ($savedBytes -lt 0) {
    Write-Host ("  Extra storage used:      {0} ({1:N1}%)" -f (Format-Storage ([Math]::Abs($savedBytes))), ([Math]::Abs($savedPercent))) -ForegroundColor Yellow
}
else {
    Write-Host "  Space saved:             0 bytes (0.0%)"
}

Write-Host ("  Average saving per file: {0}" -f (Format-Storage $averageSavedPerFile))

Write-Host ""
Write-Host "Performance" -ForegroundColor Yellow
Write-Host ("  Total duration:          {0}" -f (Format-Time $stopwatch.Elapsed.TotalSeconds))
Write-Host ("  Average time per file:   {0:N2}s" -f $averageTime)
Write-Host ("  Input processing rate:   {0}/s" -f (Format-Storage $processingRate))

Write-Host ""
Write-Host "Output" -ForegroundColor Yellow
Write-Host "  Directory: $outputDir" -ForegroundColor Cyan

Write-Host ""
if ($failureCount -gt 0) {
    Write-Host "Processing completed with errors." -ForegroundColor Red
}
elseif ($savedBytes -gt 0) {
    Write-Host "All files processed successfully. Storage reduced." -ForegroundColor Green
}
elseif ($savedBytes -lt 0) {
    Write-Host "All files processed, but total storage usage increased." -ForegroundColor Yellow
}
else {
    Write-Host "All files processed successfully." -ForegroundColor Green
}

Write-Host "========================================================" -ForegroundColor Cyan
