# MediaOptimizer

Batch-optimizes a folder of videos and photos: HEVC for video, JPEG XL for stills,
metadata and timestamps preserved, output written to an `optimized/` subfolder that
mirrors the source tree.

## Releases

| Release | Contents | Status |
|---|---|---|
| **1 — scripted, portable** | `MediaOptimizer.cmd` + `launcher.ps1` + `optimize.ps1` | **shipping now** |
| 2 — desktop app | .NET 10 / WPF portable app | planned, see [implementation plan](docs/implementation-plan.md) |

Release 1 needs only PowerShell (present on every Windows install); the media tools come
from winget. It exists to ship value now and to pressure-test the wizard wording before
it is rebuilt in XAML.

## Entry points

| File | Purpose |
|---|---|
| `MediaOptimizer.cmd` | **Interactive.** Double-click it, or drop a folder onto it. |
| `launcher.ps1` | Prompt, path validation, dependency heads-up. Wraps `optimize.ps1` without modifying it. |
| `optimize.cmd` | **Non-interactive.** For scripts and scheduled tasks. |
| `optimize.ps1` | The engine. Reference behaviour for the .NET port. |

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

- [Implementation plan](docs/implementation-plan.md) — locked decisions, milestones,
  behaviour-parity checklist, risks
- [Hardware acceleration detection](docs/hardware-acceleration.md) — why encoder
  enumeration is insufficient, the probe/benchmark pipeline, and per-encoder profiles

## External tools

| Tool | Purpose | Install |
|---|---|---|
| `ffmpeg` / `ffprobe` | Video transcode, duration probing | `winget install Gyan.FFmpeg` |
| `cjpegli` | JPEG XL still encoding | Not on winget — libjxl releases |
| `exiftool` | Metadata and timestamp preservation | `winget install PhilHarvey.ExifTool` |
