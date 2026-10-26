# Scripted release 1.0.2

Compatibility fix for the encoded videos. No other behaviour changed.

## Videos now play on Apple devices

ffmpeg tags HEVC in MP4 as `hev1` by default. Apple's decoders — QuickTime, Safari,
iOS — only accept `hvc1`, so previously encoded videos generally refused to play on an
iPhone, iPad or Mac, while playing fine in VLC.

The encoder now passes `-tag:v hvc1`. This is not just a relabel: ffmpeg moves the
VPS/SPS/PPS parameter sets out of the stream into the `hvcC` box, which is what the
`hvc1` sample entry is defined to mean, so the output is spec-conformant.

Android accepts both tags, as do Windows, Edge and the usual desktop players, so there
is no regression anywhere.

## What this does not fix

- **Android and HEVC in general.** Android has no software HEVC decoder, so playback
  still depends on the device having a hardware decoder (Android 5.0+ normally does;
  4.4 and older never will). The tag does not change that.
- **HDR footage.** 10-bit HDR is still flattened to 8-bit without tone mapping, so very
  bright or saturated HDR clips may look washed out.
- **Photos.** Unchanged, and already iOS-compatible: `cjpegli` writes a standard
  progressive JPEG. Orientation and colour profile still depend on ExifTool being
  installed.

## Upgrading

Re-encode anything you intend to watch on an Apple device. Files produced by 1.0.1 and
earlier keep the `hev1` tag and will not play there.
