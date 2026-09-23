/// A raw, unmodified, read-only snapshot of one Matribox preset-readback
/// cycle (Phase D + parts 0-9). This is deliberately NOT a
/// [CanonicalPreset]/`PresetBackup` (see canonical_preset.dart,
/// preset_backup.dart): those model WyrmTone's own manually-curated
/// recommendation presets and their `PresetPrivacy` check explicitly
/// forbids raw byte/MIDI fields. A device dump is a different concept with
/// a different, explicitly-raw format -- see raw_preset_backup_format.dart.
///
/// This file only classifies and validates already-received bytes; it
/// never opens a MIDI port, sends anything or touches a USB device.
library;

import 'dart:convert';
import 'dart:typed_data';

// Prefixed: the class below has its own `sha256` field, which would
// otherwise shadow the top-level `sha256` hash object from this package
// inside the class body (including static methods).
import 'package:crypto/crypto.dart' as crypto;

import 'p01_readback_decoder.dart';

const rawPresetSnapshotFormatVersion = 1;

/// Bumped whenever the decoding logic in p01_readback_decoder.dart (offsets,
/// field mapping) changes, so a stored snapshot's decoded fields can be
/// distinguished from a snapshot decoded with a newer/older decoder.
const rawPresetDecoderVersion = 'p01_readback_decoder@1';

const matriboxProtocolId = 'QME2';

/// Confirmed response length per part index (0-9), mirroring
/// `VerifiedPresetP01FullReadReference.expectedResponseLengths` (Kotlin).
const rawPresetPartCount = 10;
const _expectedRawPartLengths = <int>[
  210,
  210,
  210,
  210,
  210,
  210,
  210,
  210,
  46,
  18,
];

/// Preset names for which the six AMP-block offsets (188/192/196/200/204/
/// 208 into the concatenated, nibble-decoded parts 0-7) are hardware-
/// confirmed (see docs/MATRIBOX_OFFLINE_ANALYSIS.md). A different name means
/// a different algorithm/block layout is not guaranteed to use the same
/// offsets, so its AMP fields are left unset rather than guessed.
const knownAmpFieldPresetNames = <String>{'CKY 96 STUD'};

/// Thrown by [RawPresetSnapshot.capture] for any structural, ordering or
/// consistency problem. An incomplete or inconsistent read must never
/// silently become a "valid" snapshot.
class InvalidRawPresetSnapshotException implements Exception {
  const InvalidRawPresetSnapshotException(this.message);
  final String message;
  @override
  String toString() => 'InvalidRawPresetSnapshotException: $message';
}

/// Only the six confirmed Sol-100-OD AMP-block knob values. Populated only
/// when [RawPresetSnapshot.presetName] is in [knownAmpFieldPresetNames];
/// null otherwise. Never guessed for an unrecognised preset name.
class PresetAmpFields {
  const PresetAmpFields({
    required this.gain,
    required this.presence,
    required this.volume,
    required this.bass,
    required this.middle,
    required this.treble,
  });

  final double gain, presence, volume, bass, middle, treble;

  Map<String, Object?> toJson() => {
    'gain': gain,
    'presence': presence,
    'volume': volume,
    'bass': bass,
    'middle': middle,
    'treble': treble,
  };

  factory PresetAmpFields.fromJson(Map<String, Object?> map) {
    double field(String key) {
      final value = map[key];
      if (value is! num || !value.isFinite) {
        throw InvalidRawPresetSnapshotException(
          'decodedFields.$key fehlt oder ist keine endliche Zahl.',
        );
      }
      return value.toDouble();
    }

    return PresetAmpFields(
      gain: field('gain'),
      presence: field('presence'),
      volume: field('volume'),
      bass: field('bass'),
      middle: field('middle'),
      treble: field('treble'),
    );
  }
}

/// An immutable, fully-validated raw preset-readback snapshot. Every raw
/// byte the device sent for all 10 parts (and optionally the Phase-D
/// acknowledgement) is preserved unchanged in [rawParts]/[phaseDResponse] --
/// only [presetName] and, when recognised, [ampFields] are additionally
/// exposed in decoded form. Nothing here can write to a device: there is no
/// send path, no store/restore semantics, and no method that returns
/// anything but this read-only data.
class RawPresetSnapshot {
  RawPresetSnapshot._({
    required this.deviceLabel,
    required this.bank,
    required this.slot,
    required this.presetName,
    required this.createdAt,
    required List<int>? phaseDResponse,
    required List<List<int>> rawParts,
    required this.ampFields,
    required this.sha256,
  }) : phaseDResponse = phaseDResponse == null
           ? null
           : List.unmodifiable(phaseDResponse),
       rawParts = List.unmodifiable(rawParts.map(List<int>.unmodifiable));

  /// Opaque, unparsed connection/identity string exactly as reported by the
  /// native side (e.g. "Sonicake Matribox 1 84EF:0054"). Never guessed at
  /// or restructured here.
  final String deviceLabel;

  /// Raw bank byte (offset 13 of every part header); confirmed 0x00 = User
  /// for every snapshot captured so far. Not assumed to mean anything for
  /// other values -- the Factory bank has not been read via this path.
  final int bank;

  /// Raw slot byte (offset 14 / offset 16 of the readback header via
  /// [readbackHeader]); 0 = P01.
  final int slot;

  final String presetName;

  /// Host-side capture time (the device provides no timestamp of its own).
  final DateTime createdAt;

  /// Raw framed Phase-D acknowledgement (F0..F7), if one was sent as part of
  /// this read. Optional: a future read path may not need Phase D for every
  /// slot (see docs/MATRIBOX_OFFLINE_ANALYSIS.md HYPOTHESIS section).
  final List<int>? phaseDResponse;

  /// All 10 raw framed SysEx messages (F0..F7 inclusive), in order,
  /// byte-for-byte exactly as received. Parts 0-7 carry the 210-byte
  /// payload, part 8 the 46-byte tail, part 9 the 18-byte end marker.
  final List<List<int>> rawParts;

  /// Only set when [presetName] is in [knownAmpFieldPresetNames].
  final PresetAmpFields? ampFields;

  /// SHA-256 over the canonical raw representation; see
  /// [RawPresetSnapshot.canonicalHashInput].
  final String sha256;

  int get presetNumber => slot + 1;
  bool get isUserBank => bank == 0;
  int get formatVersion => rawPresetSnapshotFormatVersion;
  String get decoderVersion => rawPresetDecoderVersion;

  /// The exact byte sequence hashed to produce [sha256]:
  /// `"QME2|bank=<b>|slot=<s>|parts=10\n"` (UTF-8), optionally followed by
  /// `"phaseD=<len>\n"` + the raw Phase-D bytes, then all 10 raw parts
  /// concatenated in order. Fixed part count and fixed per-index lengths
  /// make this concatenation unambiguous without separators between parts.
  /// Exposed so backup-format code and tests can recompute the hash
  /// independently instead of trusting a stored value.
  static List<int> canonicalHashInput({
    required int bank,
    required int slot,
    required List<int>? phaseDResponse,
    required List<List<int>> rawParts,
  }) {
    final buffer = BytesBuilder();
    buffer.add(
      utf8.encode(
        '$matriboxProtocolId|bank=$bank|slot=$slot|parts=${rawParts.length}\n',
      ),
    );
    if (phaseDResponse != null) {
      buffer.add(utf8.encode('phaseD=${phaseDResponse.length}\n'));
      buffer.add(phaseDResponse);
    }
    for (final part in rawParts) {
      buffer.add(part);
    }
    return buffer.toBytes();
  }

  static String _hash({
    required int bank,
    required int slot,
    required List<int>? phaseDResponse,
    required List<List<int>> rawParts,
  }) => crypto.sha256
      .convert(
        canonicalHashInput(
          bank: bank,
          slot: slot,
          phaseDResponse: phaseDResponse,
          rawParts: rawParts,
        ),
      )
      .toString();

  /// Validates and decodes a complete set of raw device->host bytes into a
  /// [RawPresetSnapshot]. Throws [InvalidRawPresetSnapshotException] for
  /// any incomplete or inconsistent read -- an incomplete read is never
  /// allowed to become a "valid" snapshot. [phaseDResponse], if given, must
  /// be F0..F7 framed but is otherwise not structurally validated here
  /// (only the single exact Phase-D acknowledgement for Bank=User/Slot=0 is
  /// hardware-confirmed; see VerifiedPresetP01PhaseDReference.isValidAck).
  factory RawPresetSnapshot.capture({
    required String deviceLabel,
    required List<List<int>> rawParts,
    List<int>? phaseDResponse,
    DateTime Function() clock = DateTime.now,
  }) {
    if (deviceLabel.trim().isEmpty) {
      throw const InvalidRawPresetSnapshotException(
        'deviceLabel darf nicht leer sein.',
      );
    }
    if (phaseDResponse != null) {
      if (phaseDResponse.length < 2 ||
          phaseDResponse.first != 0xf0 ||
          phaseDResponse.last != 0xf7) {
        throw const InvalidRawPresetSnapshotException(
          'phaseDResponse ist kein vollständig gerahmtes SysEx (F0..F7).',
        );
      }
    }
    if (rawParts.length != rawPresetPartCount) {
      throw InvalidRawPresetSnapshotException(
        'Es werden genau $rawPresetPartCount Parts erwartet, erhalten: '
        '${rawParts.length}.',
      );
    }

    int? bank;
    int? slot;
    final headers = <int, ({int slot, int part, List<int> payload})>{};
    for (var index = 0; index < rawPresetPartCount; index++) {
      final part = rawParts[index];
      if (part.length != _expectedRawPartLengths[index]) {
        throw InvalidRawPresetSnapshotException(
          'Part $index: erwartete Länge ${_expectedRawPartLengths[index]}, '
          'erhalten ${part.length}.',
        );
      }
      final header = readbackHeader(part);
      if (header == null) {
        throw InvalidRawPresetSnapshotException(
          'Part $index: keine gültige QME2-Readback-Struktur.',
        );
      }
      if (header.part != index) {
        throw InvalidRawPresetSnapshotException(
          'Part $index: Header nennt Part ${header.part} statt $index '
          '(falsche Reihenfolge oder Duplikat).',
        );
      }
      final partBank = part[13];
      bank ??= partBank;
      slot ??= header.slot;
      if (partBank != bank) {
        throw InvalidRawPresetSnapshotException(
          'Part $index: Bank $partBank weicht von Part 0 (Bank $bank) ab.',
        );
      }
      if (header.slot != slot) {
        throw InvalidRawPresetSnapshotException(
          'Part $index: Slot ${header.slot} weicht von Part 0 (Slot $slot) '
          'ab.',
        );
      }
      headers[index] = header;
    }

    final cycle = PresetReadbackCycle(
      slot: slot!,
      parts: {for (var i = 0; i <= 7; i++) i: headers[i]!.payload},
    );
    if (!cycle.hasAllPayloadParts) {
      // Unreachable given the per-index checks above already require parts
      // 0-7 to be present and correctly indexed; kept as a fail-closed
      // invariant guard rather than trusting the loop silently.
      throw const InvalidRawPresetSnapshotException(
        'Payload-Parts 0-7 unvollständig.',
      );
    }
    final decodedParts = {
      for (final entry in cycle.parts.entries)
        entry.key: nibbleDecode(entry.value),
    };
    final name = presetNameFromDecodedPart0(decodedParts[0]!);
    if (name == null) {
      throw const InvalidRawPresetSnapshotException(
        'Presetname konnte nicht aus Part 0 dekodiert werden.',
      );
    }

    PresetAmpFields? ampFields;
    if (knownAmpFieldPresetNames.contains(name)) {
      final buffer = <int>[
        for (var part = 0; part <= 7; part++) ...decodedParts[part]!,
      ];
      if (buffer.length >= 212) {
        ampFields = PresetAmpFields(
          gain: floatLEAt(buffer, 188),
          presence: floatLEAt(buffer, 192),
          volume: floatLEAt(buffer, 196),
          bass: floatLEAt(buffer, 200),
          middle: floatLEAt(buffer, 204),
          treble: floatLEAt(buffer, 208),
        );
      }
    }

    return RawPresetSnapshot._(
      deviceLabel: deviceLabel,
      bank: bank!,
      slot: slot,
      presetName: name,
      createdAt: clock(),
      phaseDResponse: phaseDResponse,
      rawParts: rawParts,
      ampFields: ampFields,
      sha256: _hash(
        bank: bank,
        slot: slot,
        phaseDResponse: phaseDResponse,
        rawParts: rawParts,
      ),
    );
  }
}
