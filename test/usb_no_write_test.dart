import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native USB implementation contains no transfer calls', () async {
    final source = await File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/UsbConnectionManager.kt',
    ).readAsString();

    expect(
      source,
      isNot(matches(RegExp(r'\.(bulkTransfer|controlTransfer)\s*\('))),
    );
    expect(source, isNot(matches(RegExp(r'UsbRequest\s*\('))));
  });

  test('entire productive native tree has no input port or MIDI send', () async {
    final files = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>();
    for (final file in files.where((f) => f.path.endsWith('.kt'))) {
      final source = await file.readAsString();
      expect(
        source,
        isNot(matches(RegExp(r'openInputPort\s*\('))),
        reason: file.path,
      );
      expect(source, isNot(contains('MidiInputPort')), reason: file.path);
      expect(
        source,
        isNot(
          matches(
            RegExp(r'forceClaim\s*=\s*true|claimInterface\([^\n]*,\s*true'),
          ),
        ),
        reason: file.path,
      );
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'\.(send|flush|connectPorts|bulkTransfer|controlTransfer)\s*\(',
            ),
          ),
        ),
        reason: file.path,
      );
      expect(
        source,
        isNot(matches(RegExp(r'UsbRequest\s*\('))),
        reason: file.path,
      );
    }
    final native = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/MidiDiagnosticsManager.kt',
    ).readAsStringSync();
    expect(native, contains('openOutputPort(number)'));
    final close = native.substring(
      native.indexOf('fun closeDevice()'),
      native.indexOf('fun startCapture()'),
    );
    expect(
      close.indexOf('stopCapture()'),
      lessThan(close.indexOf('session.close()')),
    );
    final domain = File('lib/midi/midi_capture_controller.dart')
        .readAsStringSync();
    expect(domain, isNot(contains('UsbService')));
    expect(domain, isNot(matches(RegExp(r'\.send\s*\('))));
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'openInputPort\s*\(|MidiInputPort|receiver\s*\.\s*(send|flush)\s*\(',
            ),
          ),
        ),
        reason: file.path,
      );
    }
  });

  test('no supported Raw USB profile enables forceClaim', () async {
    final source = await File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/SupportedUsbDeviceProfiles.kt',
    ).readAsString();
    expect(source, isNot(contains('forceClaim = true')));
  });
}
