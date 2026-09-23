import 'dart:convert';
import 'dart:io';

import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/device_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_pipeline.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_session.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';
import 'package:wyrmtone/services/offline_sound_profiles.dart';

import 'matribox_big_capture_snapshots.dart';
import 'matribox_full_live_helpers.dart';
import 'matribox_p01_readback_fixtures.dart';

final toneCatalog = DevicePresetCatalog(
  objectMap(jsonDecode(File('assets/catalog/matribox_preset_catalog.json').readAsStringSync())),
);

final angelsProfile = OfflineSoundProfiles.decode(
  File('assets/catalog/sound_profiles.json').readAsStringSync(),
).firstWhere((p) => p.id == 'cob-angels-dont-kill');

const hbFusion4 = GuitarProfile(
  id: 'hb-fusion-4',
  name: 'HB Fusion 4',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.passiveHumbucker,
  outputLevel: OutputLevel.medium,
  toneCharacter: ToneCharacter.neutral,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

ToneTransferRecommendation angelsRecommendation() => MatriboxToneTransferPipeline.recommend(
  profile: angelsProfile,
  guitar: hbFusion4,
  tuning: GuitarTuning.dropC,
  role: SoundRole.rhythm,
  catalog: toneCatalog,
  createdAt: DateTime.utc(2026),
);

final baselineLedger = MatriboxHardwareLedger.baseline();

RawPresetSnapshot beforeSnapshot() => RawPresetSnapshot.capture(
  deviceLabel: 'Sonicake Matribox 1 84EF:0054',
  rawParts: hexParts(bigBeforeRawPartsHex),
  phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
);

MatriboxPresetLayoutModel beforeLayout() => MatriboxPresetLayout.decode(beforeSnapshot());

/// Decodes an arbitrary raw device state (e.g. what an earlier transfer left behind) the same way
/// [beforeLayout] decodes the initial BEFORE snapshot.
MatriboxPresetLayoutModel layoutFrom(List<List<int>> rawParts) => MatriboxPresetLayout.decode(
  RawPresetSnapshot.capture(
    deviceLabel: 'Sonicake Matribox 1 84EF:0054',
    rawParts: rawParts,
    phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
  ),
);

/// Simulates the device applying the given plan operations to the real
/// BEFORE state (a model change resets that block's parameters).
List<List<int>> deviceAfter(List<ToneTransferEntry> operations, {List<List<int>>? from}) {
  final parts = from ?? hexParts(bigBeforeRawPartsHex);
  for (final e in operations) {
    switch (e.intended) {
      case ToneOperationKind.selectModel:
        setDecoded(parts, MatriboxPresetLayout.codeOffset(e.slot), u32(e.model!.code));
        setDecoded(parts, MatriboxPresetLayout.parametersBase(e.slot), List.filled(60, 0));
        if (e.slot == MatriboxChainSlot.fx1) {
          setDecoded(parts, MatriboxPresetLayout.fx1CodeCopyOffset, u32(e.model!.code));
        }
      case ToneOperationKind.setParameter:
        setDecoded(
          parts,
          MatriboxPresetLayout.parametersBase(e.slot) + 4 * e.parameter!.wireIndex,
          f32(e.value!),
        );
      case ToneOperationKind.enableBlock || ToneOperationKind.disableBlock:
        setDecoded(parts, MatriboxPresetLayout.stateOffset(e.slot), u16(e.enable! ? 1 : 0));
      default:
        break;
    }
  }
  for (var i = 37; i < 45; i++) {
    parts[8][i] = (parts[8][i] + 1) & 15;
  }
  return parts;
}

/// Rewrites the confirmed Slot byte (offset 14) of every part / the Phase-D ack, like the device
/// answers a read of another User slot. Offset 13 (Bank) stays User.
List<List<int>> retargetParts(List<List<int>> parts, int deviceIndex) => [
  for (final part in parts) [...part]..[14] = deviceIndex,
];

/// Fake of the native reader. The historical P01 read answers [parts] as captured (slot 0); a slot
/// read answers the same content addressed at the REQUESTED slot, unless [answerSlot] forces the
/// "device" to answer with another slot (to prove a wrong slot is never accepted).
class ToneReadChannel implements MatriboxUserSlotReadChannel {
  ToneReadChannel(this.parts);
  List<List<int>> parts;
  bool fail = false;
  var reads = 0;

  /// Every preset number a slot read was addressed at, in order.
  final slotReads = <int>[];

  /// When set, a slot read answers as this preset number instead of the requested one.
  int? answerSlot;

  /// Optional per-slot device content (preset number -> raw parts), e.g. after a simulated save.
  final bySlot = <int, List<List<int>>>{};

  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async {
    reads++;
    if (fail) throw StateError('USB getrennt.');
    return {
      'outcome': 'SUCCESS',
      'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
      'parts': parts,
      'error': null,
    };
  }

  @override
  Future<Map<Object?, Object?>> readMatriboxUserSlot(int presetNumber) async {
    reads++;
    slotReads.add(presetNumber);
    if (fail) throw StateError('USB getrennt.');
    final answered = answerSlot ?? presetNumber;
    return {
      'outcome': 'SUCCESS',
      'phaseDResponse': [...matriboxHex(matriboxPhaseDAcknowledgement)]..[14] = answered - 1,
      'parts': retargetParts(bySlot[presetNumber] ?? parts, answered - 1),
      'error': null,
    };
  }
}

/// Fake of the productive transport: records the whole request and the
/// operations that were actually attempted (SENT or FAILED).
class RecordingTransfer implements MatriboxToneTransferChannel {
  RecordingTransfer({this.failAt, this.isAvailable = true, this.token = 'gen-1', this.reportedSlot});
  final int? failAt;
  final bool isAvailable;

  /// When set, the fake "native side" reports this slot as written instead of the requested one.
  final int? reportedSlot;
  String? token;
  final executions = <Map<String, Object?>>[];

  /// Operations that reached the "device" (sent or failed), in order.
  final requests = <Map<String, Object?>>[];

  @override
  bool get available => isAvailable;

  @override
  Future<String?> connectionToken() async => token;

  @override
  Future<ToneTransferExecuteResult> execute(Map<String, Object?> request) async {
    executions.add(request);
    final ops = (request['operations'] as List).cast<Map<String, Object?>>();
    final statuses = List<String>.filled(ops.length, 'NOT_SENT');
    var failed = false;
    for (var i = 0; i < ops.length; i++) {
      requests.add(ops[i]);
      if (failAt == i) {
        statuses[i] = 'FAILED';
        failed = true;
        break;
      }
      statuses[i] = 'SENT';
    }
    return ToneTransferExecuteResult(
      outcome: failed ? 'SEND_FAILED' : 'SUCCESS',
      error: failed ? 'Transportfehler.' : null,
      completed: statuses.where((x) => x == 'SENT').length,
      failedIndex: failAt,
      statuses: statuses,
      sessionToken: token,
      targetSlot: reportedSlot ?? request['targetSlot'] as int?,
      presetSelect: 'SENT',
    );
  }
}

/// The real BEFORE state with a different AMP model code.
MatriboxPresetLayoutModel beforeLayoutWithAmp(int code) {
  final parts = hexParts(bigBeforeRawPartsHex);
  setDecoded(parts, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.amp), u32(code));
  return MatriboxPresetLayout.decode(
    RawPresetSnapshot.capture(
      deviceLabel: 'Sonicake Matribox 1 84EF:0054',
      rawParts: parts,
      phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
    ),
  );
}

/// A hand-built target from capture-confirmed pieces only (Skreamer, Sol 100
/// OD parameters, BritGN 4x12), eligible under the productive ledger. Used to
/// test the transfer mechanics independently of what the recommendation
/// currently produces.
MatriboxTargetPreset readyTarget() {
  TargetValue<double> v(double x) => TargetValue(x, ToneOrigin.songProfile, 'test');
  return MatriboxTargetPreset(
    blocks: {
      MatriboxChainSlot.fx2: MatriboxTargetBlock(
        slot: MatriboxChainSlot.fx2,
        enabled: TargetValue(true, ToneOrigin.songProfile, 'test'),
        model: TargetValue(MatriboxTransferCatalog.byName('Skreamer')!, ToneOrigin.deviceTranslation, 'test'),
      ),
      MatriboxChainSlot.amp: MatriboxTargetBlock(
        slot: MatriboxChainSlot.amp,
        enabled: TargetValue(true, ToneOrigin.songProfile, 'test'),
        model: TargetValue(MatriboxTransferCatalog.byName('Sol 100 OD')!, ToneOrigin.deviceTranslation, 'test'),
        parameters: {
          'gain': v(67),
          'presence': v(59),
          'bass': v(41),
          'middle': v(59),
          'treble': v(61),
        },
      ),
      MatriboxChainSlot.cab: MatriboxTargetBlock(
        slot: MatriboxChainSlot.cab,
        enabled: TargetValue(true, ToneOrigin.guitarCorrection, 'test'),
        model: TargetValue(MatriboxTransferCatalog.byName('BritGN 4x12')!, ToneOrigin.deviceTranslation, 'test'),
      ),
    },
  );
}

