# Implementation plan

Status: **approved** · Target: v1.0 · Estimate: **~10–11 developer-days**

Replaces `optimize.ps1` with a portable Windows desktop app. Behaviour parity with the
script is the acceptance bar; the defects listed below are fixed along the way.

---

## 1. Locked decisions

| Area | Decision | Why |
|---|---|---|
| Runtime | **.NET 10 LTS** | .NET 8 leaves support 2026-11-10. .NET 10 is supported to 2028. |
| UI | **WPF + WPF-UI** (Fluent/Mica) | WinUI 3 costs ~2x time and ~2–3x size for no functional gain here. WPF has built-in `DataGrid` and drag-drop. |
| Distribution | **Portable, self-contained, single-file** | No installer, no admin, no prerequisite runtime. See §2. |
| Dependency source | **winget → system `PATH`** | Already present on target machines. `cjpegli` has no winget package, so manual locate is mandatory. |
| Encoder choice | Probe, don't enumerate; **Balanced** default | See `docs/hardware-acceleration.md`. |
| App data | `<app>\data\` → `%LOCALAPPDATA%\MediaOptimizer\` fallback | Portable, but survives read-only media. |
| MVVM | `CommunityToolkit.Mvvm` (source generators) | ~100KB, no runtime reflection, keeps view models testable. |
| DI | None — plain constructor injection | A container earns nothing at this size. |
| Logging | Custom `RunLog` → `data\logs\run-{ts}.log` | Avoids a logging dependency; output is user-facing anyway. |
| Tests | xunit on `MediaOptimizer.Core` only | UI is thin by design; all logic worth testing is in Core. |
| Processing | **Sequential** | Matches the existing ETA model. Parallelism is a v2 concern. |

---

## 2. Distribution shape

```
MediaOptimizer\                     <- unzip anywhere, run. No install, no admin.
   MediaOptimizer.exe               <- self-contained single-file, ~70-100MB (measure)
   data\
      settings.json
      hardware.json                 <- probe cache, fingerprinted
      logs\
```

Publish properties:

```xml
<PublishSingleFile>true</PublishSingleFile>
<SelfContained>true</SelfContained>
<RuntimeIdentifier>win-x64</RuntimeIdentifier>
<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
<EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
<PublishTrimmed>false</PublishTrimmed>   <!-- WPF is not trim-safe -->
<PublishReadyToRun>false</PublishReadyToRun> <!-- size over startup; revisit if slow -->
```

Accepted consequences, stated plainly:

- **Size floor is fixed.** WPF supports neither trimming nor NativeAOT, so ~70–100MB is
  the floor for a self-contained WPF app. Trimming would break XAML/reflection.
- Single-file extraction writes native libs to `%TEMP%` on first run. Acceptable; if
  "leaves no trace" becomes a hard requirement, ship the folder layout instead.
- Unsigned exe trips SmartScreen on first run. **Sign before distributing outside the
  team.**
- No context-menu integration, no file associations by default. Both are opt-in `HKCU`
  writes later — portable means *needs* nothing, not *touches* nothing.

---

## 3. Solution structure

```
MediaOptimizer.sln
Directory.Build.props              # shared TFM, version, analyzers, nullable
src/MediaOptimizer.Core/           # no UI references — fully testable
  Model/        MediaFile, FileResult, BatchSummary, EncoderChoice, EncoderSettings
  Scanner/      MediaScanner.cs
  Tools/        ToolLocator.cs, ToolRequirement.cs, PathRefresher.cs, ToolProvisioner.cs
  Encoders/     EncoderProfile.cs, Profiles.cs, EncoderDetector.cs, ProbeCache.cs
  Process/      ProcessRunner.cs, JobObject.cs, ProgressParser.cs
  Pipeline/     FfmpegRunner.cs, JpegliRunner.cs, MetadataWriter.cs, BatchJob.cs, EtaEstimator.cs
  Settings/     SettingsStore.cs, AppPaths.cs
src/MediaOptimizer.App/            # WPF
  App.xaml(.cs), MainWindow.xaml
  Views/        OnboardingView, QueueView, SummaryView
  ViewModels/   OnboardingViewModel, QueueViewModel, SummaryViewModel
tests/MediaOptimizer.Core.Tests/
docs/
```

Core has **zero** references to WPF. This is what makes the ETA math, scanner rules and
argument builders unit-testable, and is the main reason the port is low-risk.

### Key abstractions

```csharp
// One per encoder family. Builds the full command line, including hwaccel/filter pairing.
interface IEncoderProfile {
    string Name { get; }              // "hevc_nvenc"
    EncoderKind Kind { get; }         // Nvenc | Amf | Qsv | Software
    ProcessPlan Build(MediaFile input, string outputPath, EncoderSettings q);
    (string key, string value)[] QualityArgs(EncoderSettings q);
}

record ProcessPlan(string Exe, IReadOnlyList<string> Args, string OutputPath);

interface IToolLocator {
    ToolStatus Resolve(ToolKind kind);   // Found(path) | Missing(guidance)
}
```

---

## 4. Behaviour parity checklist

Extracted from `optimize.ps1`. Every row becomes a test or an explicit acceptance check.

| # | Behaviour | Note |
|---|---|---|
| 1 | Recursive scan of `mp4`, `mov`, `jpg`, `jpeg`, **or a single file** of those types | case-insensitive |
| 2 | Exclude any path segment `optimized`; exclude `opt_*` files | regex in script |
| 3 | Output mirrors source tree under `optimized\` | preserves structure |
| 4 | `optimized\` created *before* scanning | prevents self-inclusion |
| 5 | Dependency gating per media type | ffmpeg only if video; cjpegli only if stills |
| 6 | `ffprobe` duration → per-file percent | absent ⇒ "Encoding video…" |
| 7 | Parse `speed=` for display | cosmetic |
| 8 | Batch ETA weighted by bytes, per type; failed files stay in rate history | see §6 |
| 9 | Per-file saved MB and percent | both shown |
| 10 | Summary: totals, video/image split, saved, avg/file, rate/s | full port |
| 11 | Missing folder ⇒ non-zero exit; zero supported files ⇒ clean message | |
| 12 | `-map_metadata 0` on video; full metadata + timestamps via exiftool | |
| 13 | Failures isolated per file; diagnostics captured | temp log per file |

### ⚠️ `out_time_ms` is microseconds

The field **named** `out_time_ms` is reported in **microseconds**. The script divides by
`1e6` and is correct. Newer ffmpeg also emits `out_time_us`. The port must prefer
`out_time_us`, fall back to `out_time_ms` **as microseconds**, and never treat it as
milliseconds — getting this wrong yields a 1000x progress error that looks like a UI bug.

---

## 5. Milestones

### M0 — Scaffolding (0.5 d)

- Solution, `Core` + `App` + test projects, `Directory.Build.props`, `.editorconfig`
- `AppPaths` (app-dir → `%LOCALAPPDATA%` fallback), `SettingsStore` (JSON)
- CI-friendly `dotnet build` / `dotnet test`

**Done when:** `dotnet test` runs green with one placeholder test; app window opens with
"Hello" in fluent chrome.

### M1 — Tools and onboarding (3 d)

- `ToolLocator`: resolution order = settings override → `PATH` → `Missing`
- `PathRefresher`: re-read `Machine` + `User` `PATH` from registry, rebuild process env
- `ToolProvisioner`: `winget install --id <id> -e --accept-package-agreements
  --accept-source-agreements`, streamed output, no elevation
- Manual locate fallback (`FolderPicker` → validate with `--version`)
- Onboarding view: 4 rows (`ffmpeg`/`ffprobe`, `cjpegli`, `exiftool`), per-row status,
  actionable fix, "Continue" gated only on what the chosen folder actually needs

**Done when:** on a machine without ffmpeg, clicking Install results in a passing
re-detection **without restarting the app**; cjpegli can be pointed at manually.

> This milestone exists first because the stale-`PATH` bug is the single most likely
> support ticket. Re-reading the registry is not optional.

### M2 — Encoder detection (2 d)

- 4 profiles with their own args, hwaccel pairing and filter chains
- Smoke test (1s synthetic clip, 10s timeout) → benchmark (3s 1080p, warm-up + median of 3)
- `ProbeCache` with `gpuName + driverVersion + ffmpegVersion + buildHash` fingerprint
- Ranking: Fastest / Smallest / **Balanced**; manual override honoured

**Done when:** on AMD, NVIDIA, Intel and GPU-less machines the app picks a working
encoder, and an unusable one is never selected. Cache hit ⇒ no probing on relaunch.

### M3 — Pipeline (2.5 d)

- `MediaScanner` implementing §4 rows 1–4, including single-file input
- `FfmpegRunner`: `-progress pipe:1`, async parsing, `JobObject` cancel
  (`KILL_ON_JOB_CLOSE` so cancel never orphans `ffmpeg.exe`)
- `JpegliRunner`
- `MetadataWriter`: exiftool in **`-stay_open True -@ -`** mode, one process per batch
- `EtaEstimator` ported from `Get-BatchETA`
- `SetThreadExecutionState` to block sleep during a run

**Done when:** cancel stops the child process tree and leaves no partial output; a
1,000-photo batch spawns **one** exiftool process.

### M4 — UI (2 d)

- Queue `DataGrid`: name, type, size, progress, saved, status
- Overall progress + ETA, cancel, drag-drop folder
- Summary view (port of the console summary)
- On failure: expandable diagnostics; offer "retry on next encoder"

**Done when:** a real 20-file mixed folder completes end-to-end without touching a
console.

### M5 — Packaging (0.5–1 d)

- `publish.ps1`: single-file self-contained build, version stamp, zip
- Icon, file description, semver from `Directory.Build.props`
- Report the actual binary size (this is the first real datapoint on §2's estimate)
- README: run instructions, dependency table, known limitations

**Done when:** the zip unzips on a clean Windows VM with no .NET installed and runs.

---

## 6. Improvements over current behaviour

These are cheap, and they remove the script's worst user-facing outcomes:

| Change | Rationale |
|---|---|
| **Discard an encode that grows the file** | If output ≥ input, keep the original, skip writing, and report it. Eliminates the current "total storage usage increased" result — an anti-feature for a shrinking tool. |
| exiftool `-stay_open` | ~1–2s per file × 1,000 photos = 20–30 min of pure process launch. |
| Demote a failing encoder mid-run | Smoke test can pass while real media fails (10-bit, unusual profile). Fall back instead of failing every file. |
| Surface the `optimized\` overwrite count | Re-runs currently overwrite silently. Show "overwriting N existing files" with a skip option. |
| Block sleep during a run | A 2-hour batch dying to a laptop lid is a bad first impression. |
| **Accept a single file as input** | Dropping one video or photo to re-encode is common; the scripted release supports it, so the app must match. |
| **Scope the tool check to the selection** | A photo-only folder must not be blocked by a missing `ffmpeg`, and vice versa. The scripted release already behaves this way. |

---

## 7. Known limitations (v1, documented not fixed)

- **Subtitle and attachment streams are dropped.** Both the script and the planned port
  map only the default video + one audio track. Fixing needs `-map 0` plus per-stream
  codec decisions; out of scope for v1, documented in README.
- **10-bit / HDR sources** may be rejected by some hardware encoders. Mitigation is the
  mid-run demotion above, not true HDR passthrough.
- **No parallel encoding.** Sequential preserves the ETA model and keeps disk contention
  low; revisit if throughput becomes the complaint.
- **Software-only fallback is slow.** `libx265` on a large batch is hours, not minutes.
  The UI must show the chosen encoder and its measured fps *before* the run starts.

---

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| `WPF-UI` lacks `net10.0-windows` support | Blocks M0 | Verify in M0. Fall back to .NET built-in Fluent `ThemeMode` (net9+), or pin to .NET 9 if necessary. |
| Single-file size exceeds ~100MB | Distribution friction | Measured in M5. Fall back to folder layout, or accept — users already install ~170MB of ffmpeg/exiftool. |
| `winget` package IDs change | Onboarding breaks | IDs isolated in one table; manual locate always available as the universal fallback. |
| Encoder arg semantics differ per driver | Failed encodes | Per-profile args + mid-run demotion + the probe cache records what actually worked. |
| exiftool `-stay_open` hangs | Batch stalls | Per-command timeout, restart the process on timeout, and degrade to "metadata not copied". |

---

## 9. Test strategy

Unit tests target `Core` only:

| Area | Cases |
|---|---|
| `MediaScanner` | exclusions (`optimized` segment, `opt_*`), case-insensitivity, nesting, empty folder |
| `ProgressParser` | real `-progress` lines, `out_time_us` **and** `out_time_ms`-as-microseconds, `progress=end`, truncated/interleaved output |
| `EtaEstimator` | ported numeric vectors from the script's logic, incl. zero-rate and failed-file cases |
| `Profiles` | argument order snapshot per encoder — encoder options must follow `-i` |
| `ToolLocator` | resolution precedence, missing-tool guidance, override wins over `PATH` |
| `ProbeCache` | fingerprint match skips probing; any component change invalidates |

Manual acceptance (per milestone, on real Windows hardware): AMD, NVIDIA, Intel, and a
GPU-less VM if available.

---

## 10. Definition of done (v1.0)

1. Zip runs on a clean Windows 11 VM with no .NET installed.
2. A mixed folder of MP4/MOV/JPG completes with metadata and timestamps preserved.
3. Cancel mid-encode leaves no `ffmpeg.exe` running and no partial output.
4. Onboarding recovers from a missing `ffmpeg` without restarting the app.
5. Summary numbers reconcile: `successful + failed == total`.
6. `dotnet test` green; Core has no WPF references.
