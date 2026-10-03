/// V5A: offline, hard-locked transfer plan for exactly ONE NAM Clone
/// transfer to Clone 5. Builds nothing but validates everything; contains
/// no way to open a USB/MIDI device or send anything. Every assertion here
/// is a HARD guard -- failing any of them makes [V5TransferPlan.build]
/// throw, and the resulting plan (if any) is the only thing a future
/// sender (`v5_ack_state_machine.dart`) is allowed to consume.
///
/// The ONLY way this file produces outbound bytes is through
/// [NamTransferFrame.encode] (`nam_transfer_codec.dart`, unchanged,
/// already verified byte-identical against captures A/B/C) -- there is no
/// code path here that can construct a preset-selection, preset-write,
/// Store, IR, firmware, or arbitrary-SysEx message.
library;

import 'dart:typed_data';

import 'nam_transfer_codec.dart';

/// Clone 5's confirmed wire slot byte. This is the ONLY slot value this
/// module will ever build a plan for -- there is no parameter to override
/// it, by design (see V5A section E: "no generic target-slot input").
const int v5TargetCloneSlot = 0x04;

const int v5RequiredCloDataLength = 8232;
const int v5ExpectedBlockCount = 588; // 8232 / 14
const int v5ExpectedLastBlockRepeats = 3;
const int v5ExpectedFrameCount = 590; // 587 unique + 3 repeats of block 587
const int v5ExpectedAckStatusOk = 0x01;

/// One frame this plan will send, paired with the exact ACK it expects
/// back.
class V5PlannedFrame {
  const V5PlannedFrame({
    required this.ordinal,
    required this.block,
    required this.outbound,
    required this.expectedAckSlot,
    required this.expectedAckBlock,
    required this.expectedAckStatus,
  });

  /// 0-based position in the send sequence (distinct from [block]: the
  /// last block appears at 3 consecutive ordinals).
  final int ordinal;
  final int block;
  final Uint8List outbound;
  final int expectedAckSlot;
  final int expectedAckBlock;
  final int expectedAckStatus;
}

/// A fully validated, ready-to-send (but NOT sent) Clone-5 transfer plan.
/// Construct only via [V5TransferPlan.build]; the constructor itself stays
/// private so no code can hand-assemble a plan that skipped validation.
class V5TransferPlan {
  V5TransferPlan._(this.modelLabel, this.cloDataSha256Hex, this.frames);

  /// A human-readable label for logs/UI (e.g. "JVM410H Standard"), never
  /// used to build any outbound byte.
  final String modelLabel;
  final String cloDataSha256Hex;
  final List<V5PlannedFrame> frames;

  int get frameCount => frames.length;

  /// Builds and validates the plan. Throws [StateError] (never silently
  /// degrades) if ANY hard guard fails:
  /// - [cloData] is not exactly [v5RequiredCloDataLength] bytes
  /// - the encoder does not produce exactly [v5ExpectedBlockCount] blocks
  /// - the encoder does not produce exactly [v5ExpectedFrameCount] frames
  /// - any frame does not round-trip through [NamTransferFrame.parse]
  ///   (prefix, slot, block, checksum, trailer)
  /// - any frame's slot byte is not [v5TargetCloneSlot]
  /// - any frame's block number falls outside 0..[v5ExpectedBlockCount)-1
  /// - the last block is not repeated exactly [v5ExpectedLastBlockRepeats]
  ///   times, consecutively, at the end
  static V5TransferPlan build({
    required Uint8List cloData,
    required String modelLabel,
    required String cloDataSha256Hex,
  }) {
    if (cloData.length != v5RequiredCloDataLength) {
      throw StateError(
        'V5 hard guard failed: CloData length ${cloData.length} != $v5RequiredCloDataLength',
      );
    }
    if (cloData.length % namBlockPayloadBytes != 0) {
      throw StateError('V5 hard guard failed: CloData is not a whole number of blocks.');
    }
    final blocks = cloData.length ~/ namBlockPayloadBytes;
    if (blocks != v5ExpectedBlockCount) {
      throw StateError('V5 hard guard failed: block count $blocks != $v5ExpectedBlockCount');
    }

    // The ONLY call in this file that produces outbound bytes.
    final messages = encodeCloneTransfer(
      cloData,
      v5TargetCloneSlot,
      lastBlockRepeats: v5ExpectedLastBlockRepeats,
    );

    if (messages.length != v5ExpectedFrameCount) {
      throw StateError(
        'V5 hard guard failed: frame count ${messages.length} != $v5ExpectedFrameCount',
      );
    }

    final planned = <V5PlannedFrame>[];
    var expectedBlock = 0;
    var seenLastBlockRepeats = 0;
    for (var ordinal = 0; ordinal < messages.length; ordinal++) {
      final bytes = messages[ordinal];
      final frame = NamTransferFrame.parse(bytes); // throws on any malformed frame
      if (frame.slot != v5TargetCloneSlot) {
        throw StateError(
          'V5 hard guard failed: frame $ordinal targets slot 0x${frame.slot.toRadixString(16)}, not Clone 5 (0x04).',
        );
      }
      if (frame.block < 0 || frame.block >= v5ExpectedBlockCount) {
        throw StateError('V5 hard guard failed: frame $ordinal block ${frame.block} out of range.');
      }
      if (frame.block == v5ExpectedBlockCount - 1) {
        seenLastBlockRepeats++;
      } else if (frame.block != expectedBlock) {
        throw StateError(
          'V5 hard guard failed: frame $ordinal block ${frame.block} out of sequence (expected $expectedBlock).',
        );
      } else {
        expectedBlock++;
      }
      planned.add(
        V5PlannedFrame(
          ordinal: ordinal,
          block: frame.block,
          outbound: bytes,
          expectedAckSlot: v5TargetCloneSlot,
          expectedAckBlock: frame.block,
          expectedAckStatus: v5ExpectedAckStatusOk,
        ),
      );
    }
    if (seenLastBlockRepeats != v5ExpectedLastBlockRepeats) {
      throw StateError(
        'V5 hard guard failed: last block repeated $seenLastBlockRepeats times, expected $v5ExpectedLastBlockRepeats.',
      );
    }
    if (expectedBlock != v5ExpectedBlockCount - 1) {
      throw StateError('V5 hard guard failed: did not see all blocks before the final repeats.');
    }

    return V5TransferPlan._(modelLabel, cloDataSha256Hex, List.unmodifiable(planned));
  }
}
