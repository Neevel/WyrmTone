import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static safety of the productive Tone Transfer transport: own debug gate,
/// exclusive with every certification sender, exactly one productive native
/// send call site, closed contract, no store / metadata / raw SysEx entry.
void main() {
  const base = 'android/app/src/main/kotlin/de/neevel/wyrmtone/';

  String code(String path) => File(path)
      .readAsStringSync()
      .split(RegExp(r'\r?\n'))
      .map((line) => line.split('//').first)
      .where((line) => !line.trimLeft().startsWith('*') && !line.trimLeft().startsWith('/*'))
      .join('\n');

  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  String line(String prefix) {
    final start = gradle.indexOf(prefix);
    expect(start, greaterThan(-1), reason: prefix);
    return gradle.substring(start, gradle.indexOf('\n', start));
  }

  test('the gate is default-false in release and exclusive with every other hardware sender', () {
    final gate = line('val enableToneTransfer =');
    for (final other in [
      'requestedGain41Probe',
      'requestedPresetP01Probe',
      'requestedP01ReadProbe',
      'requestedP01FullReadProbe',
      'requestedP01FullReadProbeV3A',
      'requestedP01GainWrite',
      'requestedSol100OdCertification',
      'requestedFullLive',
      'requestedAngelsProduct',
    ]) {
      expect(gate, contains('!$other'), reason: other);
    }
    for (final flag in [
      'enableWriteProbe',
      'enablePresetP01Probe',
      'enableP01ReadProbe',
      'enableP01FullReadProbe',
      'enableP01FullReadProbeV3A',
      'enableP01GainWrite',
      'enableSol100OdCertification',
      'enableFullLive',
      'enableAngelsProduct',
    ]) {
      expect(line('val $flag ='), contains('!requestedToneTransfer'), reason: flag);
    }
    expect(gradle, contains('"ENABLE_MATRIBOX_TONE_TRANSFER", enableToneTransfer.toString()'));
    expect(
      gradle.substring(gradle.indexOf('release {')),
      contains('buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", "false")'),
    );
    final dart = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
    expect(dart, contains("bool.fromEnvironment('ENABLE_MATRIBOX_TONE_TRANSFER', defaultValue: false)"));
    expect(dart, contains('kDebugMode &&'));
  });

  test('exactly ONE productive native send call site, gated, re-checking the native evidence table', () {
    final port = code('${base}MatriboxToneTransferWriterPort.kt');
    expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);
    expect(port, contains('BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER'));
    expect(port, contains('MatriboxToneTransferCatalog.isConfirmed(operation)'));
    expect(port, contains('MatriboxFullLiveCodec.validate(message)'));
    for (final f in [
      'MatriboxToneTransferCatalog.kt',
      'MatriboxToneTransferPlanValidator.kt',
      'MatriboxToneTransferSession.kt',
    ]) {
      expect(code('$base$f'), isNot(matches(RegExp(r'\.send\s*\('))), reason: f);
    }
  });

  test('no store, restore, retry, metadata, name/BPM/VOL or raw byte input in the native product path', () {
    for (final f in [
      'MatriboxToneTransferCatalog.kt',
      'MatriboxToneTransferPlanValidator.kt',
      'MatriboxToneTransferSession.kt',
      'MatriboxToneTransferWriterPort.kt',
    ]) {
      final source = code('$base$f');
      expect(source, isNot(matches(RegExp(r'0x12,\s*0x1[12]'))), reason: f);
      expect(source, isNot(matches(RegExp(r'fun\s+\w*([Ss]tore|[Rr]estore|[Rr]etry|[Cc]ommit|[Mm]etadata)\w*\('))), reason: f);
      expect(source, isNot(matches(RegExp(r'ByteArray'))), reason: f);
    }
    final validator = code('${base}MatriboxToneTransferPlanValidator.kt');
    expect(validator, contains('TOP_LEVEL_KEYS = setOf("planId", "targetBank", "targetSlot", "backupHash", "operations")'));
    expect(validator, contains('"SELECT_MODEL"'));
    expect(validator, contains('"SET_PARAMETER"'));
    expect(validator, contains('"ENABLE_BLOCK", "DISABLE_BLOCK"'));
    // the closed codec still refuses 12 11 / 12 12
    expect(code('${base}MatriboxFullLiveCodec.kt'), contains('Nachrichtenfamilie nicht freigegeben'));
  });

  test('the platform channel accepts the closed contract only and offers no raw entry', () {
    final channels = File('${base}UsbPlatformChannels.kt').readAsStringSync();
    final start = channels.indexOf('"executeToneTransfer" ->');
    expect(start, greaterThan(-1));
    final end = channels.indexOf('"getVerifiedMatriboxProbeStatus" ->', start);
    final block = channels.substring(start, end).split('\n').map((l) => l.split('//').first).join('\n');
    expect(block, contains('midiManager.executeToneTransfer(request)'));
    for (final forbidden in ['ByteArray', 'sysex', 'algorithm', 'parameterIndex']) {
      expect(block.toLowerCase(), isNot(contains(forbidden.toLowerCase())), reason: forbidden);
    }
    expect(channels, isNot(matches(RegExp(r'"(sendMidi|sendSysEx|writeUsb|sendCommand|storePreset|savePreset)"'))));
    // native close/detach hooks
    final manager = File('${base}MidiDiagnosticsManager.kt').readAsStringSync();
    expect(manager, contains('toneTransferSession.cancel()'));
    expect(manager, contains('toneTransferSession.detached(deviceName)'));
  });

  test('certification senders and the productive transport are never active together', () {
    // the certification port keeps its own gates and never opens for the product flag
    final cert = code('${base}MatriboxFullLiveWriterPort.kt');
    expect(cert, isNot(contains('ENABLE_MATRIBOX_TONE_TRANSFER')));
    final product = code('${base}MatriboxToneTransferWriterPort.kt');
    expect(product, isNot(contains('ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION')));
    expect(product, isNot(contains('ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION')));
  });
}
