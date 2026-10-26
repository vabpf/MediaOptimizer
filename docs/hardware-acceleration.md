# Hardware acceleration: detection and selection

Status: proposed · Applies to: `MediaOptimizer.Core`

## Problem

The current script hardcodes one vendor's pipeline:

```powershell
-hwaccel d3d11va
-vf format=nv12
-c:v hevc_amf -usage transcoding -quality balanced -rc cqp -qp_i 28 -qp_p 28 -qp_b 30
```

That is **AMD AMF only**. On an NVIDIA or Intel machine every video fails, and even on
AMD the `-vf format=nv12` filter forces frames back through system memory, discarding
much of the benefit of hardware decode.

## Key finding: encoder enumeration is not detection

`ffmpeg -encoders` reports what was *compiled into the build*, not what the machine can
*run*. Measured on a container without GPU passthrough:

| Encoder | Listed | Actually encodes |
|---|---|---|
| `libx265` | yes | yes |
| `hevc_nvenc` | yes | **no** (no NVIDIA device) |
| `hevc_qsv` | yes | **no** (no Intel iGPU) |
| `hevc_vaapi` | yes | **no** (no `/dev/dri`) |

The same is true of `-hwaccel` modes: `d3d11va`, `cuda`, `qsv`, `vaapi` were all listed
and all failed.

Therefore detection must be **behavioural**: attempt a real encode of a synthetic clip
and record success or failure.

## Detection pipeline

Runs on first launch and whenever the fingerprint changes. No user input required —
the test clip is generated with `lavfi`, so probing works before any media is chosen.

### Stage 0 — Cache

Fingerprint = `gpuName` + `driverVersion` + `ffmpegVersion` + `ffmpegBuildHash` +
`schemaVersion`. Stored at `<app>\data\hardware.json`, falling back to
`%LOCALAPPDATA%\MediaOptimizer\hardware.json` when the app folder is read-only (portable
media, locked-down share). A matching fingerprint skips stages 1–4, so the normal launch
path costs ~0ms.

### Stage 1 — Enumerate

`ffmpeg -hide_banner -encoders`, filter for `hevc_*` and `libx265`. Cheap pre-filter to
avoid launching doomed processes.

### Stage 2 — Smoke test

One 1-second 1280x720 `testsrc2` encode per candidate, using that candidate's profile.
10s timeout. Record `pass`/`fail` plus the final stderr line, which becomes the
diagnostic shown in the UI ("hevc_nvenc: no capable devices found").

### Stage 3 — Benchmark

Only candidates that passed. 3-second 1080p `testsrc2`, one warm-up then median of 3
runs. Measure:

- `fps` — from `-progress` `out_time_us` against wall clock
- `outputBytes` — size at that encoder's calibrated quality setting

### Stage 4 — Rank

See "Ranking policy" below.

### Stage 5 — Persist and expose

Written to `hardware.json`; surfaced in settings as e.g.
`Detected: NVIDIA NVENC · 412 fps · quality 28`, with a manual override dropdown.
Overrides are always honoured — the benchmark is a default, not a cage.

## Encoder profiles

Each candidate supplies its own argument set. A single shared argument list cannot work:
`-qp_i/-qp_p` are AMF-only, `-cq` is NVENC-only, `-global_quality` is QSV-only, and
`-preset p6` is meaningless to `libx265` (which wants `veryfast`…`placebo`).

| Profile | Decode pairing | Encoder args | Filter chain |
|---|---|---|---|
| `hevc_nvenc` | `-hwaccel cuda -hwaccel_output_format cuda` | `-preset p6 -tune hq -rc vbr -cq 28 -b:v 0 -spatial-aq 1 -temporal-aq 1` | `scale_cuda=format=nv12` |
| `hevc_amf` | `-hwaccel d3d11va` | `-usage transcoding -quality balanced -rc cqp -qp_i 28 -qp_p 28 -qp_b 30` | `format=nv12` |
| `hevc_qsv` | `-hwaccel qsv` | `-preset medium -global_quality 28 -look_ahead 0` | `format=nv12,hwupload=extra_hw_frames=64` |
| `libx265` | none (software) | `-crf 28 -preset medium -tag:v hvc1` | `format=nv12` |

### Gotcha: hardware filters are not interchangeable

With `-hwaccel_output_format cuda`, frames stay on the GPU and **software `-vf` filters
fail outright**. The filter chain must match the profile (`scale_cuda`, `vpp_qsv`, etc.).
This is why `FilterChain` is a field on the profile rather than a constant.

### Gotcha: argument ordering

Encoder options must follow `-i`. `-preset` placed before the input is parsed as an
*input* option and either errors out or is silently ignored. Unit-test the built
argument list against expected shape.

## Ranking policy

Naive `max(fps)` is **wrong for this app**. Its purpose is storage reduction, and
hardware encoders are typically 2–4x faster than `libx265` but produce *larger files at
equal perceptual quality*. Picking the fastest candidate would quietly defeat the point
of the tool.

So ranking depends on a user preference, defaulting to **Balanced**:

| Preference | Rule |
|---|---|
| **Fastest** | highest measured fps among passing candidates |
| **Smallest** | `libx265` at a slow preset; ignore hardware unless it beat it on measured output size |
| **Balanced** (default) | hardware candidate with the best `outputBytes / fps` trade-off, reported alongside the `libx265` size delta so the user can see what speed costs them |

Quality normalisation without running VMAF: each profile declares a calibrated CQ/QP
value chosen so the three classes land at roughly comparable output size on the benchmark
clip. Compare *byte counts*, not QP numbers — HEVC QP scales are nominally shared but
CRF, CQ and global-quality modes are not equivalent.

Optional later refinement: VMAF scoring of the benchmark clip (`libvmaf`, ~5s extra).
Worth it only if the Balanced default proves contentious in practice.

## Failure handling

- No candidate passes → fall back to `libx265` and tell the user plainly, with the
  per-candidate diagnostics available behind a details toggle.
- Hardware passes the smoke test but fails on real media (driver quirks, 10-bit input,
  codec profiles) → demote that candidate for the rest of the session, retry the file on
  the next-best profile, and record the demotion in the run log.
- Probe must never block startup. Run async behind the onboarding screen; the app is
  usable for folder selection while it works.

## Consequences

- First launch does 1–10s of GPU work. Acceptable, and cacheable.
- We ship four profile implementations instead of one. Unavoidable for a portable app.
- Sequential processing means NVENC's concurrent-session limit is not a concern.
