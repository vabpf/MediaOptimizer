# Scripted release 1.0.0

First shipped release of the PowerShell implementation. Portable: unzip and run.
No installer, no admin rights, no runtime to install.

## What it does

- Shrinks MP4/MOV to HEVC and JPG/JPEG to JPEG XL
- Accepts a whole folder, or a single file
- Originals are never modified; results go to an `optimized` folder that mirrors the
  source tree
- Live progress, per-file savings, batch ETA, and a run summary
- Timestamps and photo metadata preserved through ExifTool (optional)

## Requirements

| Tool | Needed for | Install |
|---|---|---|
| `ffmpeg` / `ffprobe` | videos | `winget install Gyan.FFmpeg` |
| `cjpegli` | photos | not on winget — see libjxl releases |
| `exiftool` | timestamps (optional) | `winget install PhilHarvey.ExifTool` |

The launcher checks only for what the selection needs: a photo folder never asks for
FFmpeg, a video folder never asks for cjpegli.

## Changes since the original script

- **Fixed a broken launcher.** `optimize.cmd` pointed at `OptimizeMedia.ps1`, a filename
  that did not exist, at a hardcoded `C:\Tools\...` path. It now resolves `optimize.ps1`
  relative to itself, so the folder can live anywhere.
- **New interactive entry point.** `MediaOptimizer.cmd` prompts for a folder or file,
  accepts a pasted path or a drag-and-drop, validates it, and re-prompts on bad input
  instead of closing.
- **Single-file support.** Drop one video or photo instead of a folder. Output lands in an
  `optimized` folder beside it.
- **Dependency checks scoped to the selection**, replacing a single blanket warning.
- **Actionable install guidance** when a required tool is missing, including the exact
  `winget` command.
- **Exit codes are propagated**, so scheduled tasks can detect failure.

## Known limitations

- **AMD only.** Video encoding uses `hevc_amf` with `d3d11va` decode. NVIDIA and Intel GPUs
  are not supported in this release.
- **Subtitle and attachment tracks are not copied** into the output video.
- **Re-running overwrites** existing files in `optimized`. Originals are never touched.
- Unsupported inputs are anything other than MP4, MOV, JPG, JPEG.

## Files

`MediaOptimizer.cmd`, `launcher.ps1`, `optimize.ps1`, `optimize.cmd`, `README.txt` — keep
them together.

## Windows may block the download

The `.zip` carries Mark-of-the-Web. Right-click the **zip before extracting** → Properties
→ Unblock → OK. `README.txt` in the archive repeats this for end users.

## Verification

`build-release.ps1` parse-checks both PowerShell files with the Windows PowerShell parser,
normalizes line endings to CRLF, and verifies every expected entry is present in the
resulting archive before the checksum is written.
