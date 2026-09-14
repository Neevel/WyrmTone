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

  test('only the two compile-gated fixed probes may open input or send', () async {
    final files = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>();
    for (final file in files.where((file) => file.path.endsWith('.kt'))) {
      final source = await file.readAsString();
      final gainAdapter = file.path.endsWith('VerifiedMatriboxProbePort.kt');
      final p01Adapter = file.path.endsWith('VerifiedPresetP01ProbePort.kt');
      final probeAdapter = gainAdapter || p01Adapter;
      final manager = file.path.endsWith('MidiDiagnosticsManager.kt');
      if (!manager) {
        expect(
          source,
          isNot(matches(RegExp(r'openInputPort\s*\('))),
          reason: file.path,
        );
      } else {
        expect(RegExp(r'openInputPort\s*\(').allMatches(source).length, 2);
        expect(source, contains('probeEligibility().check()'));
        expect(
          source,
          contains(
            'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE',
          ),
        );
        expect(
          source,
          contains(
            'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_PRESET_P01_PROBE',
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
        expect(
          source,
          contains(
            gainAdapter
                ? 'VerifiedGain41Reference.validate(reference)'
                : 'VerifiedPresetP01Reference.validate(reference)',
          ),
        );
        expect(
          source,
          contains(
            gainAdapter
                ? 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE'
                : 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_PRESET_P01_PROBE',
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
    expect(close, contains('presetP01Probe.cancel()'));
    expect(native, contains('presetP01Probe.detached(deviceName)'));
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
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

  test('probe channels are parameterless and release build is disabled', () {
    final channels = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/UsbPlatformChannels.kt',
    ).readAsStringSync();
    for (final method in [
      'sendVerifiedSol100OdGain41Probe',
      'sendVerifiedPresetP01SelectionProbe',
    ]) {
      final start = channels.indexOf('"$method" ->');
      final end = channels.indexOf('\n            }', start);
      final probeCase = channels.substring(start, end);
      expect(probeCase, contains('if (call.arguments != null)'));
      expect(probeCase, contains('midiManager.$method()'));
      expect(probeCase, isNot(contains('call.argument<')));
    }
    expect(
      channels,
      isNot(matches(RegExp(r'"(sendMidi|sendSysEx|writeUsb|sendCommand)"'))),
    );
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(
      gradle,
      contains('requestedGain41Probe && !requestedPresetP01Probe'),
    );
    expect(
      gradle,
      contains('requestedPresetP01Probe && !requestedGain41Probe'),
    );
    for (final flag in [
      'ENABLE_MATRIBOX_WRITE_PROBE',
      'ENABLE_MATRIBOX_PRESET_P01_PROBE',
    ]) {
      expect(
        gradle.substring(gradle.indexOf('release {')),
        contains('buildConfigField("boolean", "$flag", "false")'),
      );
    }
    final p01 = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01Probe.kt',
    ).readAsStringSync();
    expect(
      RegExp(r'opened\.sendVerifiedPresetP01\(\)').allMatches(p01),
      hasLength(2),
    );
    expect(p01, contains('delay(3)'));
    final channelMethods = RegExp(r'"([^"]+)"[ ]*->')
        .allMatches(channels)
        .map((match) => match.group(1)!);
    expect(
      channelMethods.where(
        (method) => method.contains('P10') || method.contains('P11'),
      ),
      isEmpty,
    );
    final nativeFunctions = RegExp(r'fun[ ]+([A-Za-z0-9_]+)[ ]*[(]')
        .allMatches(p01)
        .map((match) => match.group(1)!);
    expect(
      nativeFunctions.where(
        (method) => method.contains('P10') || method.contains('P11'),
      ),
      isEmpty,
    );
    expect(p01, isNot(matches(RegExp(r'\b(retry|repeat|for|while)\s*\('))));
  });
}
