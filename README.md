# MediaOptimizer

Portable Windows app that batch-shrinks a folder of videos and photos: HEVC for video,
JPEG XL for stills, metadata and timestamps preserved, results written to an `optimized/`
subfolder that mirrors the source tree. No installer, no admin, no runtime prerequisite.

## Status

**Pre-implementation.** Planning is complete; M0 (scaffolding) is next.

| | |
|---|---|
| **App** | this branch — planned, see [implementation plan](docs/implementation-plan.md) |
| **Scripted release** | `master-script` branch — a shipped PowerShell implementation with independent history |

The `master-script` branch is a separate root commit, not a merged descendant: this app's history
is free of PowerShell files by construction. The two branches are never merged.

## Planned stack

.NET 10 LTS · WPF + WPF-UI · self-contained single-file · portable, data beside the exe.

Media dependencies come from `winget` and are resolved from `PATH` at launch, with a
manual "locate the binary" fallback for tools winget does not carry (`cjpegli`).

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
