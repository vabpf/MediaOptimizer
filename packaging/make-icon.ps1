<#
.SYNOPSIS
    Regenerates MediaOptimizer.ico, the icon used by the Start menu shortcut.

.DESCRIPTION
    Draws the master artwork at 256x256 with System.Drawing, downscales it to the
    sizes the Windows shell asks for, and writes a multi-resolution .ico whose
    frames are PNG-compressed (supported since Vista).

    Run this only when the artwork changes; the generated .ico is committed so
    that building a release never needs GDI+.

.EXAMPLE
    .\packaging\make-icon.ps1

.EXAMPLE
    .\packaging\make-icon.ps1 -OutFile D:\tmp\test.ico -Preview D:\tmp\test.png
#>

[CmdletBinding()]
param(
    # Defaults to MediaOptimizer.ico at the repository root.
    [string]$OutFile,

    # Optional path for a 256x256 PNG preview, for eyeballing the artwork.
    [string]$Preview
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated while parameter defaults are evaluated under
# -File, so resolve the default here instead.
if (-not $OutFile) {
    $OutFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'MediaOptimizer.ico'
}

Add-Type -AssemblyName System.Drawing

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$master = 256

function New-RoundedRectangle {
    param(
        [single]$X,
        [single]$Y,
        [single]$Width,
        [single]$Height,
        [single]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2

    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    return $path
}

# ------------------------------------------------------------------ artwork

$bitmap = New-Object System.Drawing.Bitmap($master, $master, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$canvas = [System.Drawing.Graphics]::FromImage($bitmap)
$canvas.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$canvas.Clear([System.Drawing.Color]::Transparent)

try {
    # Tile: blue gradient, generous corner radius so it reads as an app icon.
    $tile = New-RoundedRectangle -X 0 -Y 0 -Width 256 -Height 256 -Radius 56
    $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(0, 256)),
        [System.Drawing.Color]::FromArgb(255, 59, 130, 246),
        [System.Drawing.Color]::FromArgb(255, 29, 78, 216)
    )
    $canvas.FillPath($gradient, $tile)

    # Glyph: a downward arrow over a bar -- "make this smaller".
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $canvas.FillRectangle($white, 110, 42, 36, 76)

    $head = @(
        (New-Object System.Drawing.PointF(70, 104)),
        (New-Object System.Drawing.PointF(186, 104)),
        (New-Object System.Drawing.PointF(128, 188))
    )
    $canvas.FillPolygon($white, $head)

    $bar = New-RoundedRectangle -X 70 -Y 202 -Width 116 -Height 26 -Radius 13
    $canvas.FillPath($white, $bar)
}
finally {
    $canvas.Dispose()
}

if ($Preview) {
    $bitmap.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "  preview  $Preview"
}

# ------------------------------------------------------------------- frames

$frames = @()

foreach ($size in $sizes) {
    $scaled = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $surface = [System.Drawing.Graphics]::FromImage($scaled)

    try {
        $surface.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $surface.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $surface.DrawImage($bitmap, 0, 0, $size, $size)
    }
    finally {
        $surface.Dispose()
    }

    $buffer = New-Object System.IO.MemoryStream

    try {
        $scaled.Save($buffer, [System.Drawing.Imaging.ImageFormat]::Png)
        $frames += , @($size, $buffer.ToArray())
    }
    finally {
        $buffer.Dispose()
        $scaled.Dispose()
    }
}

$bitmap.Dispose()

# ---------------------------------------------------------------- ico writer

$stream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create)
$writer = New-Object System.IO.BinaryWriter($stream)

try {
    $writer.Write([uint16]0)              # reserved
    $writer.Write([uint16]1)              # 1 = icon
    $writer.Write([uint16]$frames.Count)

    # Every directory entry is 16 bytes; image data follows the whole directory.
    $offset = 6 + (16 * $frames.Count)

    foreach ($frame in $frames) {
        $size = [int]$frame[0]
        $data = [byte[]]$frame[1]

        # 256 is encoded as 0 in the directory.
        $dimension = if ($size -ge 256) { 0 } else { $size }

        $writer.Write([byte]$dimension)   # width
        $writer.Write([byte]$dimension)   # height
        $writer.Write([byte]0)            # palette colour count
        $writer.Write([byte]0)            # reserved
        $writer.Write([uint16]1)          # colour planes
        $writer.Write([uint16]32)         # bits per pixel
        $writer.Write([uint32]$data.Length)
        $writer.Write([uint32]$offset)

        $offset += $data.Length
    }

    foreach ($frame in $frames) {
        $writer.Write([byte[]]$frame[1])
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

$length = (Get-Item -LiteralPath $OutFile).Length
Write-Host "  wrote    $OutFile  ($($frames.Count) sizes, $length bytes)"
