# MediaOptimizer

Batch-optimizes a folder of videos and photos: HEVC for video, JPEG XL for stills,
metadata and timestamps preserved, output written to an `optimized/` subfolder that
mirrors the source tree.

## Status

**Pre-port.** The working implementation is a PowerShell script; a .NET desktop app
replaces it.

| | |
|---|---|
| `optimize.ps1` | Current implementation. Reference behaviour for the port. |
| `optimize.cmd` | Launcher shim. Resolves `optimize.ps1` relative to its own location. |

## Current behaviour worth preserving

- Recursive scan of MP4, MOV, JPG, JPEG; skips `optimized/` and `opt_*` files
- Per-media-type dependency gating: `ffmpeg` required only if videos exist,
  `cjpegli` only if stills exist
- Timestamps and EXIF carried over via `exiftool` (optional, degrades gracefully)
- Live progress + batch ETA from `ffmpeg -progress`

## Known defects to fix during the port

- Video pipeline hardcodes AMD AMF (`hevc_amf`, `d3d11va`) — fails on NVIDIA/Intel
- Re-running silently overwrites `optimized/`

## Planned stack

.NET 10 LTS · WPF + WPF-UI · **portable** — self-contained single-file exe, no installer,
no admin, data stored beside the exe.

Media dependencies are **system-installed via winget** and resolved from `PATH` at
launch, with a manual "locate the binary" fallback for tools winget does not carry
(`cjpegli`).

## Docs

- [Hardware acceleration detection](docs/hardware-acceleration.md) — why encoder
  enumeration is insufficient, the probe/benchmark pipeline, and per-encoder profiles

## External tools

| Tool | Purpose | Install |
|---|---|---|
| `ffmpeg` / `ffprobe` | Video transcode, duration probing | `winget install Gyan.FFmpeg` |
| `cjpegli` | JPEG XL still encoding | Not on winget — libjxl releases |
| `exiftool` | Metadata and timestamp preservation | `winget install PhilHarvey.ExifTool` |
