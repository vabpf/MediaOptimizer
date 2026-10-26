# MediaOptimizer (scripted release)

Batch-shrinks a folder of videos and photos: HEVC for video, JPEG XL for stills, metadata
and timestamps preserved, results written to an `optimized/` subfolder that mirrors the
source tree.

This branch is the **maintenance line**: a portable PowerShell implementation that needs
nothing installed except the media tools. Correctness and wording fixes only — new
features go to the app on the `master-app` branch, which is a separate root commit.

## Requirements

PowerShell (present on every Windows install) plus three tools on `PATH`:

| Tool | Needed for | Install |
|---|---|---|
| `ffmpeg` / `ffprobe` | videos | `winget install Gyan.FFmpeg` |
| `cjpegli` | photos | Not on winget — libjxl releases |
| `exiftool` | timestamps (optional) | `winget install PhilHarvey.ExifTool` |

Only what the folder actually contains is required: photos do not need `ffmpeg`, videos
do not need `cjpegli`, and `exiftool` is optional.

## Usage

| File | Purpose |
|---|---|
| `MediaOptimizer.cmd` | **Interactive.** Double-click it, or drop a folder onto it. |
| `launcher.ps1` | Prompt, path validation, dependency heads-up. |
| `optimize.cmd` | **Non-interactive.** For scripts and scheduled tasks. |
| `optimize.ps1` | The engine. Unmodified; `launcher.ps1` only supplies `-Path`. |

Supported input: MP4, MOV, JPG, JPEG — scanned recursively. Existing `optimized/` folders
and `opt_*` files are skipped, so re-running does not reprocess its own output.

## Behaviour

- Originals are never modified; output mirrors the source tree under `optimized/`
- Live progress, per-file savings, and a batch ETA
- Failures are isolated per file and reported with the tool's own diagnostics
- Video timestamps and photo EXIF are carried over via `exiftool` when available

## Packaging

`build-release.ps1 -Version 1.0.0` produces `dist\MediaOptimizer-script-1.0.0.zip`, a
`.sha256` sidecar, and a notes file with the checksum appended. It syntax-checks both
PowerShell files with the running parser, normalizes line endings to CRLF, and asserts
that every archive entry exists and uses forward-slash separators. Nothing is published
automatically — the `gh release create` command is printed at the end.
