import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static safety of the Angels product certification: own debug gate,
/// exclusive with every other sender, the SAME closed transport (one send
/// call site, no new input port), fixed plan only, no store/metadata/name.
void main() {
  const base = 'android/app/src/main/kotlin/de/neevel/wyrmtone/';

  String code(String file) => File('$base$file')
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

  test('the compile gate is exclusive with every other hardware sender and false in release', () {
    final angels = line('val enableAngelsProduct =');
    for (final other in [
      'requestedGain41Probe',
      'requestedPresetP01Probe',
      'requestedP01ReadProbe',
      'requestedP01FullReadProbe',
      'requestedP01FullReadProbeV3A',
      'requestedP01GainWrite',
      'requestedSol100OdCertification',
      'requestedFullLive',
      'requestedToneTransfer',
    ]) {
      expect(angels, contains('!$other'), reason: other);
    }
    for (final flag in [
      'enableFullLive',
      'enableWriteProbe',
      'enablePresetP01Probe',
      'enableP01ReadProbe',
      'enableP01FullReadProbe',
      'enableP01FullReadProbeV3A',
      'enableP01GainWrite',
      'enableSol100OdCertification',
      'enableAngelsProduct',
    ]) {
      if (flag == 'enableAngelsProduct') {
        expect(line('val $flag ='), contains('!requestedToneTransfer'), reason: flag);
        continue;
      }
      expect(line('val $flag ='), contains('!requestedAngelsProduct'), reason: flag);
    }
    expect(gradle, contains('"ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION", enableAngelsProduct.toString()'));
    expect(
      gradle.substring(gradle.indexOf('release {')),
      contains('buildConfigField("boolean", "ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION", "false")'),
    );
  });

  test('the transport is the existing closed Full Live transport: one send call site, plan-gated', () {
    final port = code('MatriboxFullLiveWriterPort.kt');
    expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);
    expect(port, contains('MatriboxCertificationPlans.permitted(fullLive, angels, familyExpansion)'));
    expect(port, contains('BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION'));
    final manager = File('${base}MidiDiagnosticsManager.kt').readAsStringSync();
    expect(manager, contains('MatriboxCertificationPlans.operations('));
    expect(RegExp(r'openInputPort\s*\(').allMatches(manager).length, 10); // certification senders + the ONE productive sender
    final channels = File('${base}UsbPlatformChannels.kt').readAsStringSync();
    expect(channels, isNot(contains('runAngels')));
  });

  test('the fixed native plan has no store, metadata, name, NR/MOD/DLY/RVB write or send call', () {
    final plan = code('MatriboxAngelsPlan.kt');
    expect(plan, isNot(matches(RegExp(r'0x12,\s*0x1[12]'))));
    expect(plan, isNot(matches(RegExp(r'\.send\s*\('))));
    expect(plan, isNot(matches(RegExp(r'ChainSlot\.(NR|MOD|DLY|RVB)'))));
    expect(plan, isNot(matches(RegExp(r'fun\s+\w*([Ss]tore|[Rr]estore|[Rr]etry|[Cc]ommit)\w*\('))));
    expect(plan, contains('const val PLAN_ID = "ANGELS_DONT_KILL_P01_V1"'));
    // only the closed codec can build messages; it still refuses 12 11 / 12 12
    expect(code('MatriboxFullLiveCodec.kt'), contains('Nachrichtenfamilie nicht freigegeben'));
  });

  test('the Dart panel only reads via the production reader and runs the plan by id', () {
    final source = File('lib/screens/matribox_angels_certification_panel.dart').readAsStringSync();
    expect(source, isNot(contains('invokeMethod')));
    expect(source, contains('MethodChannelFullLiveChannel'));
    final clients = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
    final invoked = RegExp(r"invokeMapMethod<[^>]*>\(\s*'([A-Za-z0-9]+)'").allMatches(clients).map((m) => m.group(1)).toSet();
    expect(invoked, {'readMatriboxUserP01', 'readMatriboxUserSlot', 'runFullLiveP01Certification', 'runFamilyExpansionP01Certification', 'executeToneTransfer', 'getToneTransferStatus'});
  });
}
