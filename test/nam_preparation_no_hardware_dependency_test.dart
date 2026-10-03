import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android NAM Inference V1, final on-device CloData gate, section 13: the
/// NAM preparation pipeline (inference + CloData estimation) must never be
/// able to reach a Matribox device or MIDI -- a static, textual check
/// (same pattern as `test/tool/matribox_nam_analysis_test.dart`'s "tool
/// sources cannot reach a device"), not a runtime assertion, so it catches
/// even an accidental import that is never actually exercised by a test.
void main() {
  test('NAM preparation service files never import MIDI/Matribox/device code', () {
    const banned = [
      'MethodChannel',
      'usb_service',
      'usb_platform_service',
      'MidiDiagnosticsManager',
      'MatriboxNamTransferSession',
      'MatriboxNamCloneSendPort',
      'nam_transfer_codec',
      'v5_nam_transfer_controller',
      'v5_android_transport',
    ];
    final files = [
      'lib/services/nam_preparation_service.dart',
      'lib/services/nam_inference_engine.dart',
      'lib/services/nam_native_bindings.dart',
      'lib/services/matribox_nam_payload.dart',
      'lib/services/wyrmtone_reference_signal_v4.dart',
      ...Directory('lib/services/matribox_nam_clodata').listSync(recursive: true).whereType<File>().map(
        (f) => f.path.replaceAll('\\', '/'),
      ),
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final word in banned) {
        expect(source.contains(word), isFalse, reason: '$path uses $word');
      }
    }
    // The CloData/estimator engine is pure Dart math over bytes already in
    // memory -- it must never itself do file/network/platform I/O either.
    for (final path in files.where((p) => p.contains('matribox_nam_clodata'))) {
      expect(File(path).readAsStringSync().contains('dart:io'), isFalse, reason: '$path imports dart:io');
    }
  });
}
