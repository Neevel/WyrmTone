# IR/NAM Device Transfer – Status

Download → Validate → Local Library works today (`Tone3000DownloadService`, `NamDownloadService`,
existing hash/format/size/attribution/duplicate checks). This note is only about the next step:
copying a downloaded IR or NAM file onto the Matribox itself. That step is **not implemented**, and
this is a deliberate, evidence-based decision, not an oversight.

## Why: DOWNLOAD_READY, but DEVICE_TRANSFER_RESEARCH_REQUIRED

Searched for a belegtes IR/NAM file-upload protocol in: the manufacturer XML catalog, existing
editor artifacts, existing passive USB/MIDI captures, and `docs/MATRIBOX_OFFLINE_ANALYSIS.md` /
`docs/PROTOCOL_NOTES.md`. None of them show a file transfer: no chunking scheme, no upload
acknowledgement, no file checksum/commit exchange for IR or NAM data. What IS captured is limited to
*selecting* an existing on-device slot (e.g. the `User IR 7` model code) — a selection command, not a
file upload. Two things this repo already keeps strictly apart and that must not be conflated:

* `UserIR7`-selection evidence ≠ an IR file-upload protocol.
* The Matribox supporting NAM at all ≠ WyrmTone knowing the NAM upload protocol.

Building a sender on either assumption would mean inventing SysEx commands, chunk sizes and
checksums with no hardware evidence — explicitly excluded by this project's safety rules.

## Where this lives in code

`DeviceCapabilities` (`lib/devices/device_profile.dart`) is the single source of truth:

* `supportsPresetTransfer` — `confirmed` (User P01, see `docs/DIRECT_PRESET_TRANSFER.md`).
* `supportsIrTransfer`, `supportsNamTransfer` — `notImplemented` (DOWNLOAD_READY, device transfer is
  DEVICE_TRANSFER_RESEARCH_REQUIRED).

The IR/NAM library screens already say so in plain German ("Keine Geräteübertragung") instead of
hiding the download feature or claiming a capability that is not there.

## What would unblock it

A passive USB/MIDI capture of an official Sonicake editor actually uploading an IR or a NAM file,
analysed the same way the preset-transfer evidence was (`docs/MATRIBOX_OFFLINE_ANALYSIS.md`,
`docs/MIDI_CAPTURE.md`): the exact message framing, any chunking, and the acknowledgement/commit
step. Until that capture exists, `supportsIrTransfer`/`supportsNamTransfer` stay `notImplemented`.
