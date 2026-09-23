import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../presets/matribox_family_expansion_certification.dart';
import '../presets/matribox_full_live_session.dart';
import '../presets/matribox_raw_backup_service.dart';
import '../presets/matribox_tone_transfer_session.dart';
import '../presets/matribox_transfer_slots.dart';

const _usbChannel = MethodChannel('de.neevel.wyrmtone/usb_methods');

/// Debug/experimental gate of the PRODUCTIVE Tone Transfer transport. Must be
/// enabled at compile time on both sides (dart-define here, BuildConfig in
/// Kotlin); exclusive with every certification sender. Default false.
const matriboxToneTransferEnabled =
    kDebugMode && bool.fromEnvironment('ENABLE_MATRIBOX_TONE_TRANSFER', defaultValue: false);

/// Fresh reads through the existing native production reader: the historical User P01 read, and
/// the productive transfer's read of one product-writable slot (P11..P99; refused here and again
/// natively for anything else, without sending).
class MethodChannelPresetReadChannel implements MatriboxUserSlotReadChannel {
  const MethodChannelPresetReadChannel();
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async =>
      await _usbChannel.invokeMapMethod<Object?, Object?>('readMatriboxUserP01') ?? {};

  @override
  Future<Map<Object?, Object?>> readMatriboxUserSlot(int presetNumber) async {
    final rejection = MatriboxSlotPolicy.writeRejection(presetNumber);
    if (rejection != null) throw StateError(rejection);
    return await _usbChannel.invokeMapMethod<Object?, Object?>(
          'readMatriboxUserSlot',
          {'targetBank': 'USER', 'targetSlot': presetNumber},
        ) ??
        {};
  }
}

/// The closed certification transport: only a plan id leaves Dart; the
/// operation lists are native constants.
class MethodChannelFullLiveChannel implements MatriboxFullLiveChannel {
  const MethodChannelFullLiveChannel();
  @override
  Future<Map<Object?, Object?>> runFullLiveP01Certification(String planId) async =>
      await _usbChannel.invokeMapMethod<Object?, Object?>(
        'runFullLiveP01Certification',
        {'planId': planId},
      ) ??
      {};
}

/// The closed FAMILY_EXPANSION_P01_V1 certification call: plan id, User P01 and
/// the verified backup hash. The operation list is a native constant; no
/// bytes, wire id, index or operation list ever leaves Dart.
class MethodChannelFamilyExpansionChannel implements MatriboxFamilyExpansionChannel {
  const MethodChannelFamilyExpansionChannel();
  @override
  Future<Map<Object?, Object?>> runFamilyExpansionP01Certification({
    required String planId,
    required String backupSha256,
  }) async =>
      await _usbChannel.invokeMapMethod<Object?, Object?>(
        'runFamilyExpansionP01Certification',
        {'planId': planId, 'targetBank': 'USER', 'targetSlot': 1, 'backupHash': backupSha256},
      ) ??
      {};
}

/// The productive transport: ONE call with the closed contract map of a
/// validated plan. The native side validates the whole plan before sending.
class MethodChannelToneTransferChannel implements MatriboxToneTransferChannel {
  const MethodChannelToneTransferChannel();

  @override
  bool get available => matriboxToneTransferEnabled;

  @override
  Future<ToneTransferExecuteResult> execute(Map<String, Object?> request) async =>
      ToneTransferExecuteResult.fromNative(
        await _usbChannel.invokeMapMethod<Object?, Object?>('executeToneTransfer', request) ?? {},
      );

  @override
  Future<String?> connectionToken() async {
    final status = await _usbChannel.invokeMapMethod<Object?, Object?>('getToneTransferStatus');
    return status?['sessionToken']?.toString();
  }
}
