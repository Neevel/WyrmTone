import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static safety of the native Matribox surface (architecture boundaries that are hard to test
/// dynamically; the dynamic zero-send and slot tests live in the Kotlin/Dart unit tests):
/// exactly two compile-gated senders (the read-only reader and the productive P11..P99 transfer),
/// each with ONE send call site and no raw-byte input, two debug-only gates that are false in
/// release, a closed platform-channel surface, no Store/metadata/retry, no raw USB transfer.
const _base = 'android/app/src/main/kotlin/de/neevel/wyrmtone/';

class _Sender {
  const _Sender({required this.port, required this.gate, required this.validations});
  final String port;
  final String gate;
  final List<String> validations;
}

const _senders = [
  _Sender(
    port: 'MatriboxPresetReaderPort.kt',
    gate: 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP',
    // both confirmed references, User/Slot 0 at the positions the slot byte replaces
    validations: ['MatriboxUserSlotReadReference.validate()'],
  ),
  _Sender(
    port: 'MatriboxToneTransferWriterPort.kt',
    gate: 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER',
    validations: [
      'MatriboxToneTransferCatalog.isConfirmed(operation)',
      'MatriboxFullLiveCodec.validate(message)',
      'MatriboxSlotPolicy.isProductWritable(target.presetNumber)',
      'MatriboxPresetSelectReference.validate(it, target)',
    ],
  ),
];

/// Source without `//` comments and KDoc lines (prose may name forbidden words).
String _code(String path) => File(path)
    .readAsStringSync()
    .split(RegExp(r'\r?\n'))
    .map((line) => line.split('//').first)
    .where((line) => !line.trimLeft().startsWith('*') && !line.trimLeft().startsWith('/*'))
    .join('\n');

Iterable<File> _kotlinFiles() =>
    Directory('android/app/src/main/kotlin').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.kt'));

void main() {
  test('only the two gated senders hold an input port and send; each has ONE send call site and validates first', () {
    for (final file in _kotlinFiles()) {
      final source = _code(file.path);
      final sender = _senders.where((s) => file.path.endsWith(s.port)).firstOrNull;
      if (sender == null) {
        expect(source, isNot(contains('MidiInputPort')), reason: file.path);
        expect(source, isNot(matches(RegExp(r'\.(send|flush|connectPorts)\s*\('))), reason: file.path);
      } else {
        expect(RegExp(r'\.send\s*\(').allMatches(source).length, 1, reason: file.path);
        expect(source, isNot(matches(RegExp(r'\.(flush|connectPorts)\s*\('))), reason: file.path);
        expect(source, contains(sender.gate), reason: file.path);
        for (final v in sender.validations) {
          expect(source, contains(v), reason: '${file.path}: $v');
        }
        // no raw byte input: nothing but typed, validated values reaches the port
        expect(source, isNot(matches(RegExp(r'override fun \w+\([^)]*ByteArray'))), reason: file.path);
      }
      expect(source, isNot(matches(RegExp(r'\.(bulkTransfer|controlTransfer)\s*\(|UsbRequest\s*\('))), reason: file.path);
      expect(source, isNot(matches(RegExp(r'forceClaim\s*=\s*true|claimInterface\([^\n]*,\s*true'))), reason: file.path);
    }
    // the manager opens exactly the two senders' input ports, each behind its gate
    final manager = _code('${_base}MidiDiagnosticsManager.kt');
    expect(RegExp(r'openInputPort\s*\(').allMatches(manager).length, _senders.length);
    for (final s in _senders) {
      expect(manager, contains(s.gate));
    }
    // Dart never reaches a MIDI input port
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(file.readAsStringSync(), isNot(matches(RegExp(r'openInputPort\s*\(|MidiInputPort|receiver\s*\.\s*(send|flush)\s*\('))),
          reason: file.path);
    }
  });

  test('exactly two debug-only compile gates exist, both false in release; no stale gate is referenced', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final fields = RegExp(r'buildConfigField\("boolean", "(ENABLE_[A-Z0-9_]+)", ([^)]+)\)').allMatches(gradle).toList();
    final debug = gradle.substring(gradle.indexOf('debug {'), gradle.indexOf('release {'));
    final release = gradle.substring(gradle.indexOf('release {'));
    expect({for (final m in fields) m.group(1)}, {'ENABLE_MATRIBOX_P01_RAW_BACKUP', 'ENABLE_MATRIBOX_TONE_TRANSFER'});
    expect(release, contains('buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", "false")'));
    expect(release, contains('buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", "false")'));
    expect(debug, contains('"ENABLE_MATRIBOX_TONE_TRANSFER", enableToneTransfer.toString()'));
    expect(gradle, contains('val enableToneTransfer = requestedToneTransfer'));
    // every BuildConfig flag used natively is one of the two gates
    final used = <String>{
      for (final f in _kotlinFiles()) ...RegExp(r'BuildConfig\.(ENABLE_[A-Z0-9_]+)').allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
    };
    expect(used, {'ENABLE_MATRIBOX_P01_RAW_BACKUP', 'ENABLE_MATRIBOX_TONE_TRANSFER'});
    // the Dart side gates the transfer at compile time too, default false
    final clients = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
    expect(clients, contains("kDebugMode && bool.fromEnvironment('ENABLE_MATRIBOX_TONE_TRANSFER', defaultValue: false)"));
  });

  test('the platform channel exposes exactly the productive methods; the write and reads take closed arguments only', () {
    final channels = File('${_base}UsbPlatformChannels.kt').readAsStringSync();
    final methods = {for (final m in RegExp(r'^\s+"([A-Za-z0-9]+)" ->', multiLine: true).allMatches(channels)) m.group(1)};
    expect(methods, {
      'listUsbDevices', 'requestUsbPermission', 'openDevice', 'closeDevice', 'getConnectionStatus',
      'listMidiDevices', 'openMidiDevice', 'closeMidiDevice', 'getMidiConnectionStatus',
      'startMidiCapture', 'stopMidiCapture',
      'getMatriboxPresetReaderStatus', 'readMatriboxUserP01', 'readMatriboxUserSlot',
      'getToneTransferStatus', 'executeToneTransfer',
    });
    String block(String method) {
      final start = channels.indexOf('"$method" ->');
      final next = RegExp(r'^\s+"[A-Za-z0-9]+" ->|^\s+else ->', multiLine: true).firstMatch(channels.substring(start + 1))!;
      return channels.substring(start, start + 1 + next.start).split('\n').map((l) => l.split('//').first).join('\n');
    }
    expect(block('readMatriboxUserP01'), contains('READER_ARGUMENTS_FORBIDDEN'));
    expect(block('readMatriboxUserSlot'), contains('arguments.keys != setOf("targetBank", "targetSlot")'));
    expect(block('readMatriboxUserSlot'), contains('MatriboxWritableUserPreset.contractProblem('));
    final execute = block('executeToneTransfer');
    expect(execute, contains('midiManager.executeToneTransfer(request)'));
    for (final forbidden in ['bytearray', 'sysex', 'algorithm', 'parameterindex']) {
      expect(execute.toLowerCase(), isNot(contains(forbidden)), reason: forbidden);
    }
    // the Dart clients call nothing else
    final clients = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
    final invoked = RegExp(r"invokeMapMethod<[^>]*>\(\s*'([A-Za-z0-9]+)'").allMatches(clients).map((m) => m.group(1)).toSet();
    expect(invoked, {'readMatriboxUserP01', 'readMatriboxUserSlot', 'executeToneTransfer', 'getToneTransferStatus'});
  });

  test('the native product path has no Store, metadata, restore, retry or raw byte contract', () {
    for (final f in [
      'MatriboxToneTransferCatalog.kt',
      'MatriboxToneTransferPlanValidator.kt',
      'MatriboxToneTransferSession.kt',
      'MatriboxToneTransferWriterPort.kt',
      'MatriboxSlotPolicy.kt',
    ]) {
      final source = _code('$_base$f');
      expect(source, isNot(matches(RegExp(r'0x12,\s*0x1[12]'))), reason: f);
      expect(source, isNot(matches(RegExp(r'fun\s+\w*([Ss]tore|[Rr]estore|[Rr]etry|[Cc]ommit|[Mm]etadata)\w*\('))), reason: f);
    }
    for (final f in ['MatriboxToneTransferPlanValidator.kt', 'MatriboxToneTransferSession.kt', 'MatriboxToneTransferWriterPort.kt']) {
      expect(_code('$_base$f'), isNot(contains('ByteArray')), reason: f);
    }
    final validator = _code('${_base}MatriboxToneTransferPlanValidator.kt');
    expect(validator, contains('TOP_LEVEL_KEYS = setOf("planId", "targetBank", "targetSlot", "backupHash", "operations")'));
    expect(validator, contains('MatriboxWritableUserPreset.contractProblem(map["targetBank"], map["targetSlot"])'));
    // the closed codec still refuses 12 11 / 12 12
    expect(_code('${_base}MatriboxFullLiveCodec.kt'), contains('Nachrichtenfamilie nicht freigegeben'));
  });

  test('the productive reader derives every message from the confirmed references; the slot is a validated type', () {
    final reader = _code('${_base}MatriboxPresetReader.kt');
    expect(reader, isNot(contains('while')));
    expect(reader, isNot(matches(RegExp(r'\b(retry|repeat)\s*\('))));
    expect(reader, isNot(matches(RegExp(r'\b(bank|segment)\s*[:=]'))));
    expect(RegExp(r'\bslot\s*[:=]\s*(\w+)').allMatches(reader).map((m) => m.group(1)).toSet(), {'MatriboxUserPreset'});
    expect(RegExp(r'byteArrayOf\s*\(').allMatches(reader).length, 0);
    expect(reader, contains('MatriboxUserSlotReadReference.isValidResponse(it, slot, partIndex)'));
    expect(reader, contains('MatriboxUserSlotReadReference.isValidAck(it, slot)'));
    for (final outcome in ['SUCCESS', 'PHASE_D_TIMEOUT', 'PHASE_D_INVALID', 'PART_TIMEOUT', 'PART_INVALID', 'INCOMPLETE', 'TRANSPORT_ERROR']) {
      expect(reader, contains(outcome));
    }
    final policy = _code('${_base}MatriboxSlotPolicy.kt');
    expect(RegExp(r'byteArrayOf\s*\(').allMatches(policy).length, 0);
    expect(policy, contains('const val SLOT_OFFSET = 14'));
    expect(policy, contains('reference.copyOf().also { it[SLOT_OFFSET] = slot.deviceIndex.toByte() }'));
    expect(policy, contains('bytes[SLOT_OFFSET] == slot.deviceIndex.toByte()'));
    // close/detach always cancel both senders
    final manager = _code('${_base}MidiDiagnosticsManager.kt');
    final close = manager.substring(manager.indexOf('fun closeDevice()'), manager.indexOf('fun startCapture()'));
    expect(close, contains('presetReader.cancel()'));
    expect(close, contains('toneTransferSession.cancel()'));
    expect(close.indexOf('stopCapture()'), lessThan(close.indexOf('session.close()')));
    expect(manager, contains('toneTransferSession.detached(deviceName)'));
    expect(RegExp(r'presetReader\.cancel\(\)').allMatches(manager).length, 2);
  });
}
