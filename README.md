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
| `Create-Shortcut.cmd` | **Optional install.** Copies to `%LOCALAPPDATA%` and adds a Start menu entry. |
| `launcher.ps1` | Prompt, path validation, dependency heads-up. |
| `create-shortcut.ps1` | Install and removal logic behind `Create-Shortcut.cmd`. |
| `optimize.cmd` | **Non-interactive.** For scripts and scheduled tasks. |
| `optimize.ps1` | The engine. Unmodified; `launcher.ps1` only supplies `-Path`. |
| `MediaOptimizer.ico` | Nine-size icon used by the Start menu entry. |

Supported input: MP4, MOV, JPG, JPEG — scanned recursively. Existing `optimized/` folders
and `opt_*` files are skipped, so re-running does not reprocess its own output.

## Start menu shortcut

`Create-Shortcut.cmd` does a per-user install: copy the runtime files to
`%LOCALAPPDATA%\Programs\MediaOptimizer`, then create a Start menu shortcut pointing at
that copy, so the folder you downloaded can be deleted afterwards. No admin rights, no
registry writes, no services, no `PATH` changes.

```
Create-Shortcut.cmd             install + Start menu entry
Create-Shortcut.cmd -NoInstall  shortcut only, keep the files where they are
Create-Shortcut.cmd -Remove     undo both
```

Pinning to Start is the one step that cannot be automated. Windows 10 and 11 have no
supported API for an application to pin itself — the old `pintostart` verb was removed —
so the shortcut lands in Start search and under All apps, and the user right-clicks it
once. The installer prints those steps.

`-Remove` run from the installed folder cannot delete that folder immediately, because
`cmd.exe` reads batch files line by line and would fail mid-run. It hands the delete to a
hidden helper that waits for the console to exit, then removes the folder.

## Behaviour

- Originals are never modified; output mirrors the source tree under `optimized/`
- Live progress, per-file savings, and a batch ETA
- Failures are isolated per file and reported with the tool's own diagnostics
- Video timestamps and photo EXIF are carried over via `exiftool` when available

## Packaging

`build-release.ps1 -Version 1.0.1` produces `dist\MediaOptimizer-script-1.0.1.zip`, a
`.sha256` sidecar, and a notes file with the checksum appended. It syntax-checks every
PowerShell file in the payload, normalizes line endings to CRLF, copies binary payloads
byte-for-byte while asserting their hashes, and asserts that every archive entry exists
and uses forward-slash separators. Nothing is published automatically — the
`gh release create` command is printed at the end.
