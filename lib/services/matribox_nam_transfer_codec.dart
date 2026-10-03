import 'dart:typed_data';

/// Offline codec for the Clone (NAM) transfer as observed in official-editor
/// captures A/B/C. Pure functions over bytes; it builds messages in memory for
/// comparison with captures and has no way to send anything.
///
/// Lives in `lib/` (not `tool/`) so product UI/service code can use the same
/// [MatriboxCloneSlot]/[CloneSlotEvidence] types the offline analysis tooling
/// does -- `tool/matribox_nam_analysis/nam_transfer_codec.dart` re-exports
/// this file rather than duplicating it.

/// `F0 21 25 7F 'QME2' 12 12 00 10 13`: observed constant prefix of every block
/// and ACK (13 bytes). Slot, block number and payload follow.
const namTransferPrefix = <int>[
  0xf0,
  0x21,
  0x25,
  0x7f,
  0x51,
  0x4d,
  0x45,
  0x32,
  0x12,
  0x12,
  0x00,
  0x10,
  0x13,
];

/// Decoded payload bytes per block (28 nibble bytes on the wire).
const namBlockPayloadBytes = 14;
const namBlockMessageLength = 47;
const namAckMessageLength = 18;

/// Filler of the last, short block (observed 0xFF).
const namBlockFill = 0xff;

/// High nibble first: each payload byte becomes two wire bytes 0x0H, 0x0L.
List<int> encodeTransferPayload(List<int> payload) {
  if (payload.length != namBlockPayloadBytes) {
    throw FormatException('Payload must be $namBlockPayloadBytes bytes.');
  }
  return [
    for (final b in payload) ...[
      if (b < 0 || b > 255) throw const FormatException('Not a byte.'),
      b >> 4,
      b & 0x0f,
    ],
  ];
}

List<int> decodeTransferPayload(List<int> nibbles) {
  if (nibbles.length != namBlockPayloadBytes * 2) {
    throw FormatException('Expected ${namBlockPayloadBytes * 2} nibbles.');
  }
  if (nibbles.any((n) => n < 0 || n > 0x0f)) {
    throw const FormatException('Payload byte above 0x0F (not a nibble).');
  }
  return [
    for (var i = 0; i < nibbles.length; i += 2)
      (nibbles[i] << 4) | nibbles[i + 1],
  ];
}

/// Per-block check value: sum of the 28 payload wire bytes modulo 256 (sent as
/// two nibbles, high first). Holds for all 1,770 blocks of captures A/B/C.
int transferChecksum(List<int> nibbles) =>
    nibbles.fold<int>(0, (s, n) => s + n) & 0xff;

void _requireRanges(int slot, int block) {
  if (slot < 0 || slot > 0x7f) {
    throw const FormatException('Slot must be 0..127.');
  }
  if (block < 0 || block > 0x3fff) {
    throw const FormatException('Block must be 0..16383.');
  }
}

/// Two 7-bit bytes, most significant first.
List<int> _blockBytes(int block) => [block >> 7, block & 0x7f];

class NamTransferFrame {
  NamTransferFrame({
    required this.slot,
    required this.block,
    required List<int> payload,
  }) : payload = List.unmodifiable(payload) {
    _requireRanges(slot, block);
    if (payload.length != namBlockPayloadBytes) {
      throw FormatException('Payload must be $namBlockPayloadBytes bytes.');
    }
  }

  /// Wire value of the clone slot: Clone 1 = 0, Clone 5 = 4 (confirmed for
  /// those two; Clone 2..4 are inferred, no capture).
  final int slot;
  final int block;
  final List<int> payload;

  List<int> encode() {
    final nibbles = encodeTransferPayload(payload);
    final sum = transferChecksum(nibbles);
    return [
      ...namTransferPrefix,
      slot,
      ..._blockBytes(block),
      ...nibbles,
      sum >> 4,
      sum & 0x0f,
      0xf7,
    ];
  }

  /// Throws [FormatException] for anything that is not a well-formed block.
  static NamTransferFrame parse(List<int> message) {
    if (message.length != namBlockMessageLength) {
      throw FormatException('Block must be $namBlockMessageLength bytes.');
    }
    _requirePrefix(message);
    if (message.last != 0xf7) throw const FormatException('Missing F7.');
    if (message.skip(13).take(33).any((b) => b > 0x7f)) {
      throw const FormatException('Data byte above 0x7F.');
    }
    final nibbles = message.sublist(16, 44);
    final expected = transferChecksum(nibbles);
    if (((message[44] << 4) | message[45]) != expected) {
      throw const FormatException('Block checksum mismatch.');
    }
    return NamTransferFrame(
      slot: message[13],
      block: (message[14] << 7) | message[15],
      payload: decodeTransferPayload(nibbles),
    );
  }
}

/// Device reply to one block: same prefix, slot, block number, then status.
class NamTransferAck {
  NamTransferAck({
    required this.slot,
    required this.block,
    required this.status,
  }) {
    _requireRanges(slot, block);
  }

  final int slot;
  final int block;

  /// Only 0x01 was observed (590 of 590 ACKs in A/B/C); other values UNKNOWN.
  final int status;
  bool get isObservedOk => status == 0x01;

  List<int> encode() => [
    ...namTransferPrefix,
    slot,
    ..._blockBytes(block),
    status,
    0xf7,
  ];

  static NamTransferAck parse(List<int> message) {
    if (message.length != namAckMessageLength) {
      throw FormatException('ACK must be $namAckMessageLength bytes.');
    }
    _requirePrefix(message);
    if (message.last != 0xf7) throw const FormatException('Missing F7.');
    return NamTransferAck(
      slot: message[13],
      block: (message[14] << 7) | message[15],
      status: message[16],
    );
  }
}

void _requirePrefix(List<int> message) {
  for (var i = 0; i < namTransferPrefix.length; i++) {
    if (message[i] != namTransferPrefix[i]) {
      throw const FormatException('Not a Clone transfer message.');
    }
  }
}

/// The transported buffer: 8,224 real bytes + 0xFF filler up to whole blocks.
/// 588 blocks x 14 bytes = 8,232.
int get namBlockCountFor8232 => 8232 ~/ namBlockPayloadBytes;

/// Offline simulator: logical SysEx messages the official editor produced for
/// [cloData] and [slot] (block order, then the observed repeat of the last
/// block). [lastBlockRepeats] is the observed total number of transmissions
/// of the last block (3), not a protocol requirement.
List<Uint8List> encodeCloneTransfer(
  Uint8List cloData,
  int slot, {
  int lastBlockRepeats = 3,
}) {
  if (cloData.isEmpty || cloData.length % namBlockPayloadBytes != 0) {
    throw const FormatException(
      'CloData must be a whole number of 14-byte blocks.',
    );
  }
  final blocks = cloData.length ~/ namBlockPayloadBytes;
  final messages = <Uint8List>[];
  for (var block = 0; block < blocks; block++) {
    final frame = NamTransferFrame(
      slot: slot,
      block: block,
      payload: cloData.sublist(
        block * namBlockPayloadBytes,
        (block + 1) * namBlockPayloadBytes,
      ),
    );
    final bytes = Uint8List.fromList(frame.encode());
    final repeats = block == blocks - 1 ? lastBlockRepeats : 1;
    for (var i = 0; i < repeats; i++) {
      messages.add(bytes);
    }
  }
  return messages;
}

class CloneTransferReconstruction {
  const CloneTransferReconstruction({
    required this.cloData,
    required this.blockCount,
    required this.missingBlocks,
    required this.duplicateBlocks,
    required this.conflictingBlocks,
    required this.slots,
    required this.checksumFailures,
    required this.malformed,
  });

  /// Null unless blocks 0..max are all present and consistent.
  final Uint8List? cloData;
  final int blockCount;
  final List<int> missingBlocks;

  /// block -> number of extra transmissions (identical repeats).
  final Map<int, int> duplicateBlocks;
  final List<int> conflictingBlocks;
  final Set<int> slots;
  final int checksumFailures;
  final int malformed;
  bool get isComplete => cloData != null;
}

/// Rebuilds CloData from logical host->device SysEx messages (any USB framing
/// has already been normalised away by the caller).
CloneTransferReconstruction reconstructCloneTransfer(
  Iterable<List<int>> hostMessages,
) {
  final byBlock = <int, List<int>>{};
  final repeats = <int, int>{};
  final conflicts = <int>{};
  final slots = <int>{};
  var checksumFailures = 0, malformed = 0;
  for (final message in hostMessages) {
    if (message.length != namBlockMessageLength) continue;
    NamTransferFrame frame;
    try {
      frame = NamTransferFrame.parse(message);
    } on FormatException catch (error) {
      error.message.contains('checksum') ? checksumFailures++ : malformed++;
      continue;
    }
    slots.add(frame.slot);
    final known = byBlock[frame.block];
    if (known == null) {
      byBlock[frame.block] = frame.payload;
    } else if (_same(known, frame.payload)) {
      repeats[frame.block] = (repeats[frame.block] ?? 0) + 1;
    } else {
      conflicts.add(frame.block);
    }
  }
  final maxBlock = byBlock.isEmpty
      ? -1
      : byBlock.keys.reduce((a, b) => a > b ? a : b);
  final missing = [
    for (var i = 0; i <= maxBlock; i++)
      if (!byBlock.containsKey(i)) i,
  ];
  Uint8List? data;
  if (maxBlock >= 0 && missing.isEmpty && conflicts.isEmpty) {
    data = Uint8List.fromList([
      for (var i = 0; i <= maxBlock; i++) ...byBlock[i]!,
    ]);
  }
  return CloneTransferReconstruction(
    cloData: data,
    blockCount: byBlock.length,
    missingBlocks: missing,
    duplicateBlocks: repeats,
    conflictingBlocks: conflicts.toList()..sort(),
    slots: slots,
    checksumFailures: checksumFailures,
    malformed: malformed,
  );
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum CloneSlotEvidence { confirmed, stronglyInferred }

/// Clone n (1..5) -> wire slot byte n-1. Only Clone 1 (=0, captures A/C) and
/// Clone 5 (=4, capture B) are observed; Clone 2..4 follow the same pattern and
/// the five `Clone` models in algorithm.xml, but no capture shows them.
class MatriboxCloneSlot {
  MatriboxCloneSlot(this.cloneNumber) {
    if (cloneNumber < 1 || cloneNumber > 5) {
      throw const FormatException('Clone slot must be 1..5.');
    }
  }
  final int cloneNumber;
  int get wireValue => cloneNumber - 1;
  CloneSlotEvidence get evidence => cloneNumber == 1 || cloneNumber == 5
      ? CloneSlotEvidence.confirmed
      : CloneSlotEvidence.stronglyInferred;
}
