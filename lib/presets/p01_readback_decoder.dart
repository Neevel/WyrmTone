import 'dart:typed_data';

import 'preset_selection_codec.dart'
    show MidiObservationState, PresetSelectionDirection, TimedMidiObservation;

/// Offline/shared decoder for the Matribox connect/sync preset-readback
/// stream.
///
/// This file only classifies and decodes already-received or already
/// captured bytes; it never opens a MIDI port, sends anything or touches a
/// USB device. It is used both by the offline CLI tool
/// (`tool/matribox_p01_readback_decoder.dart`, reading PCAP/PCAPNG files)
/// and by the productive raw preset snapshot (reading live-received MIDI
/// bytes). Every field decoded here is the exact field mapping
/// confirmed in docs/MATRIBOX_OFFLINE_ANALYSIS.md ("Vollständiger
/// Device→Host-Readback und Persistenzbeweis"); everything else in the
/// 768-byte preset payload stays unclassified on purpose and is never
/// guessed at.

/// One reconstructed 10-part preset-readback cycle for a single bank slot
/// (parts 0-7 = 210-Byte payload segments, part 8 = 46-Byte segment, part 9
/// = 18-Byte end-of-cycle marker without payload). [parts] holds the
/// nibble-paired (not yet decoded) payload bytes for parts 0-7 only, keyed
/// by part index.
class PresetReadbackCycle {
  PresetReadbackCycle({required this.slot, required this.parts});

  final int slot;
  final Map<int, List<int>> parts;

  bool get hasAllPayloadParts =>
      List.generate(8, (index) => index).every(parts.containsKey);
}

/// Only the six confirmed Sol-100-OD AMP-block knob values plus the preset
/// name are exposed. Nothing else in the cycle is decoded; unknown bytes
/// are never labelled or guessed.
class DecodedPresetReadback {
  const DecodedPresetReadback({
    required this.slot,
    required this.name,
    required this.gain,
    required this.presence,
    required this.volume,
    required this.bass,
    required this.middle,
    required this.treble,
  });

  final int slot;
  final String name;
  final double gain;
  final double presence;
  final double volume;
  final double bass;
  final double middle;
  final double treble;

  Map<String, Object?> toJson() => {
    'slot': slot,
    'name': name,
    'amp': {
      'gain': gain,
      'presence': presence,
      'volume': volume,
      'bass': bass,
      'middle': middle,
      'treble': treble,
    },
    'evidenceLevel': 'confirmedSingleSessionCorrelation',
    'note':
        'Only the fields confirmed in '
        'docs/MATRIBOX_OFFLINE_ANALYSIS.md are decoded here; every other '
        'byte of the preset payload remains unclassified.',
    'deviceWriteApproved': false,
  };
}

List<int> nibbleDecode(List<int> bytes) {
  final out = <int>[];
  for (var index = 0; index + 1 < bytes.length; index += 2) {
    out.add((bytes[index] << 4) | bytes[index + 1]);
  }
  return out;
}

/// Recognises the confirmed device->host preset-readback header (offsets
/// 8/9 = QME2 class 0x12/0x13, offset 11 = 0x00, offset 12 = 0x03 for parts
/// 0-8 or 0x05 for the payload-less part-9 end marker) and extracts slot
/// (offset 14), part (offset 16) and the remaining nibble-paired payload.
/// Offset 10 is 0x01 for the two bulk bank-enumeration passes observed
/// during connect/sync and 0x02 for the single "currently active slot"
/// re-read seen once at the end of both reference captures (see
/// docs/MATRIBOX_OFFLINE_ANALYSIS.md); both are accepted here, everything
/// else is rejected.
({int slot, int part, List<int> payload})? readbackHeader(List<int> bytes) {
  if (bytes.length < 18 || bytes.last != 0xf7) return null;
  if (bytes[8] != 0x12 || bytes[9] != 0x13) return null;
  if ((bytes[10] != 0x01 && bytes[10] != 0x02) || bytes[11] != 0x00) {
    return null;
  }
  if (bytes[12] != 0x03 && bytes[12] != 0x05) return null;
  return (
    slot: bytes[14],
    part: bytes[16],
    payload: bytes.sublist(17, bytes.length - 1),
  );
}

/// Reconstructs preset-readback cycles from a chronological, already
/// deframed MIDI observation stream. Host->device traffic and any other
/// MIDI is ignored. A part-0 message starts a new cycle for its slot;
/// messages that do not match the current slot are ignored rather than
/// silently merged into the wrong cycle. Only cycles that observed parts
/// 0-7 are returned; part 8/9 are intentionally not required here because
/// no confirmed field currently depends on them.
List<PresetReadbackCycle> reconstructReadbackCycles(
  List<TimedMidiObservation> observations,
) {
  final cycles = <PresetReadbackCycle>[];
  Map<int, List<int>>? current;
  int? currentSlot;
  for (final observation in observations) {
    if (observation.direction != PresetSelectionDirection.deviceToHost) {
      continue;
    }
    if (observation.state != MidiObservationState.completeSysEx) continue;
    final header = readbackHeader(observation.bytes);
    if (header == null) continue;
    if (header.part == 0) {
      if (current != null && currentSlot != null) {
        cycles.add(PresetReadbackCycle(slot: currentSlot, parts: current));
      }
      current = {};
      currentSlot = header.slot;
    }
    if (current == null || currentSlot != header.slot) continue;
    if (header.part <= 7) current[header.part] = header.payload;
  }
  if (current != null && currentSlot != null) {
    cycles.add(PresetReadbackCycle(slot: currentSlot, parts: current));
  }
  return List.unmodifiable(cycles);
}

double floatLEAt(List<int> bytes, int offset) {
  final data = ByteData(4);
  for (var index = 0; index < 4; index++) {
    data.setUint8(index, bytes[offset + index]);
  }
  return data.getFloat32(0, Endian.little);
}

String? presetNameFromDecodedPart0(List<int> decodedPart0) {
  const nameOffset = 2, maxNameLength = 16;
  if (decodedPart0.length < nameOffset + 1) return null;
  final end = (nameOffset + maxNameLength).clamp(0, decodedPart0.length);
  final window = decodedPart0.sublist(nameOffset, end);
  final terminator = window.indexOf(0);
  final nameBytes = terminator == -1
      ? window
      : window.sublist(0, terminator);
  if (nameBytes.isEmpty) return null;
  return String.fromCharCodes(nameBytes).trimRight();
}

/// Decodes only the confirmed fields for one cycle, or returns null if the
/// cycle is incomplete or its preset name does not match [expectedName].
/// Field offsets (188/192/196/200/204/208 into the concatenated,
/// nibble-decoded parts 0-7) are the ones confirmed for Sol-100-OD /
/// "CKY 96 STUD" in docs/MATRIBOX_OFFLINE_ANALYSIS.md; a differently
/// configured AMP block or a different algorithm is not guaranteed to use
/// the same offsets, so a name mismatch is treated as "not this preset"
/// rather than decoded speculatively.
DecodedPresetReadback? decodeConfirmedFields(
  PresetReadbackCycle cycle, {
  required String expectedName,
}) {
  if (!cycle.hasAllPayloadParts) return null;
  final decodedParts = <int, List<int>>{
    for (final entry in cycle.parts.entries)
      entry.key: nibbleDecode(entry.value),
  };
  final name = presetNameFromDecodedPart0(decodedParts[0]!);
  if (name != expectedName) return null;
  final buffer = <int>[
    for (var part = 0; part <= 7; part++) ...decodedParts[part]!,
  ];
  if (buffer.length < 212) return null;
  return DecodedPresetReadback(
    slot: cycle.slot,
    name: name!,
    gain: floatLEAt(buffer, 188),
    presence: floatLEAt(buffer, 192),
    volume: floatLEAt(buffer, 196),
    bass: floatLEAt(buffer, 200),
    middle: floatLEAt(buffer, 204),
    treble: floatLEAt(buffer, 208),
  );
}

/// Reconstructs cycles from raw observations and decodes every cycle whose
/// name matches [expectedName].
List<DecodedPresetReadback> decodeMatchingPresets(
  List<TimedMidiObservation> observations, {
  required String expectedName,
}) {
  final decoded = <DecodedPresetReadback>[];
  for (final cycle in reconstructReadbackCycles(observations)) {
    final result = decodeConfirmedFields(cycle, expectedName: expectedName);
    if (result != null) decoded.add(result);
  }
  return List.unmodifiable(decoded);
}
