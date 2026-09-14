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

  test('only the compile-gated fixed probe may open input or send', () async {
    final files = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>();
    for (final file in files.where((f) => f.path.endsWith('.kt'))) {
      final source = await file.readAsString();
      final probeAdapter = file.path.endsWith('VerifiedMatriboxProbePort.kt');
      final manager = file.path.endsWith('MidiDiagnosticsManager.kt');
      if (!manager) {
        expect(
          source,
          isNot(matches(RegExp(r'openInputPort\s*\('))),
          reason: file.path,
        );
      } else {
        expect(RegExp(r'openInputPort\s*\(').allMatches(source).length, 1);
        expect(source, contains('probeEligibility().check()'));
        expect(
          source,
          contains(
            'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE',
          ),
        );
      }
      if (!probeAdapter) {
        expect(source, isNot(contains('MidiInputPort')), reason: file.path);
      }
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
              probeAdapter
                  ? r'\.(flush|connectPorts|bulkTransfer|controlTransfer)\s*\('
                  : r'\.(send|flush|connectPorts|bulkTransfer|controlTransfer)\s*\(',
            ),
          ),
        ),
        reason: file.path,
      );
      if (probeAdapter) {
        expect(RegExp(r'\.send\s*\(').allMatches(source).length, 1);
        expect(source, contains('VerifiedGain41Reference.validate(reference)'));
        expect(
          source,
          contains(
            'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE',
          ),
        );
      }
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

  test(
    'probe channel is parameterless and release build is always disabled',
    () {
      final channels = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/UsbPlatformChannels.kt',
      ).readAsStringSync();
      final probeCase = channels.substring(
        channels.indexOf('"sendVerifiedSol100OdGain41Probe" ->'),
        channels.indexOf('else -> result.notImplemented()'),
      );
      expect(probeCase, contains('if (call.arguments != null)'));
      expect(
        probeCase,
        contains('midiManager.sendVerifiedSol100OdGain41Probe()'),
      );
      expect(probeCase, isNot(contains('call.argument<')));
      expect(
        channels,
        isNot(matches(RegExp(r'"(sendMidi|sendSysEx|writeUsb|sendCommand)"'))),
      );
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(
        gradle,
        contains('probeDefines == listOf("ENABLE_MATRIBOX_WRITE_PROBE=true")'),
      );
      expect(
        gradle.substring(gradle.indexOf('release {')),
        contains(
          'buildConfigField("boolean", "ENABLE_MATRIBOX_WRITE_PROBE", "false")',
        ),
      );
    },
  );
}
