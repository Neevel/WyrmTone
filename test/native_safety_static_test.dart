import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static safety of the native Matribox surface (architecture boundaries that are hard to test
/// dynamically; the dynamic zero-send and slot tests live in the Kotlin/Dart unit tests):
/// exactly three compile-gated senders (the read-only reader, the productive P11..P99 transfer,
/// and V5B.1's NAM Clone-5 transfer), each with ONE send call site and no raw-byte override (the
/// NAM Clone sender's opaque, only-constructible-when-valid [NamCloneTransferFrame] gives it the
/// same "no raw bytes reach the port" property the other two get from typed domain objects), three
/// debug-only gates that are false in release, a closed platform-channel surface, no
/// Store/metadata/retry, no raw USB transfer.
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
  _Sender(
    port: 'MatriboxNamCloneSendPort.kt',
    // Release hardening V1: this gate alone (not AND'd with BuildConfig.DEBUG) is release-
    // hardcoded true -- see the dedicated REAL_MATRIBOX_WRITE test below for the full model.
    gate: 'BuildConfig.REAL_MATRIBOX_WRITE',
    validations: ['MatriboxNamCloneTransferReference.parseValidated(frame.bytes)'],
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
  test('only the three gated senders hold an input port and send; each has ONE send call site and validates first', () {
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

  test(
    'exactly three compile gates exist; P01-backup/tone-transfer stay debug-only-false, '
    'REAL_MATRIBOX_WRITE is release-true (hardware-confirmed product feature); no stale gate is referenced',
    () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final fields = RegExp(r'buildConfigField\("boolean", "(ENABLE_[A-Z0-9_]+|REAL_MATRIBOX_WRITE)", ([^)]+)\)').allMatches(gradle).toList();
    final debug = gradle.substring(gradle.indexOf('debug {'), gradle.indexOf('release {'));
    final release = gradle.substring(gradle.indexOf('release {'));
    expect({for (final m in fields) m.group(1)}, {
      'ENABLE_MATRIBOX_P01_RAW_BACKUP', 'ENABLE_MATRIBOX_TONE_TRANSFER', 'REAL_MATRIBOX_WRITE',
    });
    expect(release, contains('buildConfigField("boolean", "ENABLE_MATRIBOX_P01_RAW_BACKUP", "false")'));
    expect(release, contains('buildConfigField("boolean", "ENABLE_MATRIBOX_TONE_TRANSFER", "false")'));
    // Release hardening V1: REAL_MATRIBOX_WRITE is the one gate release hardcodes TRUE -- the
    // NAM Clone-transfer write path is the shipped, hardware-confirmed product feature; the
    // real safety boundary is the UI's own explicit per-transfer confirmation flow, not this
    // build-time flag. The other two gates (preset reader/tone-transfer) remain diagnostics-only
    // and stay false in release.
    expect(release, contains('buildConfigField("boolean", "REAL_MATRIBOX_WRITE", "true")'));
    expect(debug, contains('"ENABLE_MATRIBOX_TONE_TRANSFER", enableToneTransfer.toString()'));
    expect(debug, contains('"REAL_MATRIBOX_WRITE", enableRealMatriboxWrite.toString()'));
    expect(gradle, contains('val enableToneTransfer = requestedToneTransfer'));
    // debug still defaults REAL_MATRIBOX_WRITE false unless a build explicitly passes
    // --dart-define=REAL_MATRIBOX_WRITE=true -- a developer build never writes by accident.
    expect(gradle, contains('val enableRealMatriboxWrite = requestedDefine("REAL_MATRIBOX_WRITE")'));
    // every BuildConfig flag used natively is one of the three gates
    final used = <String>{
      for (final f in _kotlinFiles())
        ...RegExp(r'BuildConfig\.(ENABLE_[A-Z0-9_]+|REAL_MATRIBOX_WRITE)').allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
    };
    expect(used, {'ENABLE_MATRIBOX_P01_RAW_BACKUP', 'ENABLE_MATRIBOX_TONE_TRANSFER', 'REAL_MATRIBOX_WRITE'});
    // every native use of REAL_MATRIBOX_WRITE is the bare flag, never AND'd with BuildConfig.DEBUG
    // (that AND would make release's hardcoded "true" above meaningless, since AGP's own
    // BuildConfig.DEBUG is always false for a release build type).
    for (final f in _kotlinFiles()) {
      final source = f.readAsStringSync();
      if (source.contains('BuildConfig.REAL_MATRIBOX_WRITE')) {
        expect(source, isNot(contains('BuildConfig.DEBUG && BuildConfig.REAL_MATRIBOX_WRITE')), reason: f.path);
      }
    }
    // the Dart side gates the transfer at compile time too, default false
    final clients = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
    expect(clients, contains("kDebugMode && bool.fromEnvironment('ENABLE_MATRIBOX_TONE_TRANSFER', defaultValue: false)"));
    // Product NAM transfer V1: the old V5B2b experimental, debug-dart-define-gated FAB/screen
    // was retired from normal navigation (its real successor is the unconditional NAM library ->
    // NamDetailPage -> "Auf Matribox übertragen" product flow) -- app.dart must reference neither
    // the retired screen nor a dart-define gate for it; the real safety boundary for the NAM
    // Clone-transfer write is now the product UI's own explicit confirmation flow plus the
    // native BuildConfig.REAL_MATRIBOX_WRITE field itself (release-true, debug-false-by-default,
    // both verified above) -- the product UI is unconditionally reachable by design.
    final app = File('lib/app.dart').readAsStringSync();
    expect(app, isNot(contains('v5b2b')));
    expect(app, isNot(contains('V5b2bExperimentalTransferScreen')));
    expect(app, isNot(contains('REAL_MATRIBOX_WRITE')));
    // The product transfer service itself must never hardcode/bypass the native gate either.
    final transferService = File('lib/services/matribox_nam_transfer_service.dart').readAsStringSync();
    expect(transferService, isNot(contains('REAL_MATRIBOX_WRITE')));
    expect(transferService, isNot(contains('sendNamCloneTransferFrame')), reason: 'must only use the session path, never the single-frame sender');
  });

  group('release safety matrix (Release hardening V1)', () {
    test('release: NAM Clone write open; tone transfer and P01 raw backup closed. debug: every gate comes only from an explicit dart-define', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final release = gradle.substring(gradle.indexOf('release {'));
      final debug = gradle.substring(gradle.indexOf('debug {'), gradle.indexOf('release {'));
      Map<String, String> fields(String block) => {
        for (final m in RegExp(r'buildConfigField\("boolean", "([A-Z0-9_]+)", ("[a-z]+"|[A-Za-z.]+)').allMatches(block))
          m.group(1)!: m.group(2)!,
      };
      expect(fields(release), {
        'ENABLE_MATRIBOX_P01_RAW_BACKUP': '"false"',
        'ENABLE_MATRIBOX_TONE_TRANSFER': '"false"',
        'REAL_MATRIBOX_WRITE': '"true"',
      });
      // debug: no literal true anywhere -- every gate needs its own explicit dart-define, and
      // requestedDefine() demands exactly one exact "<NAME>=true" entry.
      expect(fields(debug).values.any((v) => v == '"true"'), isFalse);
      expect(gradle, contains('decodedDartDefines.count { it.startsWith("\$name=") } == 1'));
      expect(gradle, contains('== "\$name=true"'));
    });

    test('the three gates are isolated: no sender reads another sender\'s gate, so no global write bypass exists', () {
      const preset = 'MatriboxPresetReaderPort.kt';
      const tone = 'MatriboxToneTransferWriterPort.kt';
      const nam = 'MatriboxNamCloneSendPort.kt';
      const ownFlag = {
        preset: 'ENABLE_MATRIBOX_P01_RAW_BACKUP',
        tone: 'ENABLE_MATRIBOX_TONE_TRANSFER',
        nam: 'REAL_MATRIBOX_WRITE',
      };
      const allFlags = {'ENABLE_MATRIBOX_P01_RAW_BACKUP', 'ENABLE_MATRIBOX_TONE_TRANSFER', 'REAL_MATRIBOX_WRITE'};
      for (final entry in ownFlag.entries) {
        final used = RegExp(r'BuildConfig\.([A-Z0-9_]+)').allMatches(_code('$_base${entry.key}')).map((m) => m.group(1)!).toSet();
        expect(used.intersection(allFlags), {entry.value}, reason: '${entry.key} must read exactly its own gate');
      }
      // Only these files may read a gate at all (comments excluded).
      final readers = <String, Set<String>>{};
      for (final f in _kotlinFiles()) {
        final used = RegExp(r'BuildConfig\.(ENABLE_[A-Z0-9_]+|REAL_MATRIBOX_WRITE)').allMatches(_code(f.path)).map((m) => m.group(1)!).toSet();
        if (used.isNotEmpty) readers[f.uri.pathSegments.last] = used;
      }
      expect(readers, {
        preset: {'ENABLE_MATRIBOX_P01_RAW_BACKUP'},
        tone: {'ENABLE_MATRIBOX_TONE_TRANSFER'},
        nam: {'REAL_MATRIBOX_WRITE'},
        'MidiDiagnosticsManager.kt': allFlags,
      });
      // Inside the manager every eligibility check names exactly one gate; the NAM one is the
      // bare flag, the other two stay AND-ed with BuildConfig.DEBUG (closed in every release).
      final manager = _code('${_base}MidiDiagnosticsManager.kt');
      final args = {
        for (final m in RegExp(r'probeEligibility\(([^()]*)\)').allMatches(manager))
          if (m.group(1)!.startsWith('BuildConfig')) m.group(1)!,
      };
      expect(args, {
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP',
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER',
        'BuildConfig.REAL_MATRIBOX_WRITE',
      });
    });

    test('the NAM Clone transfer needs the explicit user confirmation and is never started, resumed or retried by itself', () {
      final page = File('lib/screens/nam_detail_page.dart')
          .readAsStringSync()
          .split(RegExp(r'\r?\n'))
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      String segment(String from, String to) => page.substring(page.indexOf(from), page.indexOf(to));
      // Preparation never transfers.
      final prepare = segment('Future<void> _startTransfer()', 'Future<void> _cancelPreparation()');
      expect(prepare, isNot(contains('MatriboxNamTransferService')));
      expect(prepare, isNot(contains('widget.transfer')));
      expect(prepare, isNot(contains('_continueAfterPreparation')));
      // The transfer step is reachable only through the connect card's "Weiter" button...
      expect(RegExp('_continueAfterPreparation').allMatches(page).length, 2, reason: 'definition + the "Weiter" onContinue only');
      // ...and inside it the runner is called only after slot choice AND the overwrite confirmation.
      final cont = segment('Future<void> _continueAfterPreparation()', 'Future<bool?> _confirmOverwrite(');
      expect(cont.indexOf('CloneSlotPicker.pick('), lessThan(cont.indexOf('_confirmOverwrite(slot)')));
      expect(cont, contains('if (confirmed != true || !mounted) return;'));
      expect(cont.indexOf('if (confirmed != true || !mounted) return;'), lessThan(cont.indexOf('await runner(')));
      expect(RegExp(r'await runner\(').allMatches(cont).length, 1, reason: 'one attempt per confirmation, no loop');
      // "Erneut versuchen" only goes back to idle -- it never starts a transfer.
      final reset = segment('void _reset()', 'Widget build(BuildContext context)');
      expect(reset, isNot(contains('runner')));
      expect(reset, isNot(contains('transfer(')));
      // The session is started from exactly one place in lib/, once, with no retry vocabulary.
      final service = File('lib/services/matribox_nam_transfer_service.dart').readAsStringSync();
      expect(RegExp(r'executeNamCloneTransferSession\(frames\)').allMatches(service).length, 1);
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final path = file.path.replaceAll('\\', '/');
        final source = file.readAsStringSync();
        if (source.contains('MatriboxNamTransferService(')) {
          expect(path, anyOf(endsWith('lib/screens/nam_detail_page.dart'), endsWith('lib/services/matribox_nam_transfer_service.dart')));
        }
        if (source.contains('executeNamCloneTransferSession(')) {
          expect(
            path,
            anyOf(endsWith('lib/services/usb_service.dart'), endsWith('lib/services/usb_platform_service.dart'), endsWith('lib/services/matribox_nam_transfer_service.dart')),
          );
        }
      }
      final code = service.split(RegExp(r'\r?\n')).where((l) => !l.trimLeft().startsWith('//')).join('\n').toLowerCase();
      expect(code, isNot(contains('retry')));
      expect(code, isNot(contains('attempt')));
    });
  });

  test('NAM transfer progress reaches the Flutter EventSink only through the main thread', () {
    // Progress is produced on the transfer's worker thread; a real-device measurement showed that
    // sending it from there delivered no event at all, so the UI never advanced.
    final channels = _code('${_base}UsbPlatformChannels.kt');
    expect(channels, contains('emitNamTransferProgress = { event -> mainHandler.post { namTransferProgressSink?.success(event) } }'));
    expect(channels, isNot(contains('emitNamTransferProgress = { event -> namTransferProgressSink?.success(event) }')));
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
      'sendNamCloneTransferFrame', 'executeNamCloneTransferSession', 'cancelNamCloneTransferSession',
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
    // V5B.1: the NAM Clone-transfer method-channel case takes only "bytes" -- no slot, no clone
    // number, no NAM path -- and delegates to the one native call site that validates first.
    final namClone = block('sendNamCloneTransferFrame');
    expect(namClone, contains('call.argument<ByteArray>("bytes")'));
    expect(namClone, contains('midiManager.sendNamCloneTransferFrame(bytes)'));
    for (final forbidden in ['slot', 'clone5', 'store', 'preset', 'sysex']) {
      expect(namClone.toLowerCase(), isNot(contains(forbidden)), reason: forbidden);
    }
    // V5B.2a: the real session's method-channel case takes only "frames" -- a list of already-
    // built frame byte arrays -- no slot, no clone number, no NAM path.
    final namSession = block('executeNamCloneTransferSession');
    expect(namSession, contains('call.argument<List<*>>("frames")'));
    expect(namSession, contains('midiManager.executeNamCloneTransferSession('));
    for (final forbidden in ['slot', 'clone5', 'store', 'preset', 'sysex']) {
      expect(namSession.toLowerCase(), isNot(contains(forbidden)), reason: forbidden);
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

  test(
    'V5B.2a: passive monitor and the NAM transfer session refuse to run at the same time, in '
    'both directions, and the session cancels on every device-lifecycle teardown',
    () {
      final manager = _code('${_base}MidiDiagnosticsManager.kt');
      // Direction 1 (monitor -> session): every NAM transfer session run goes through
      // ProbeEligibility.check(), which already requires `!monitoring` -- proven dynamically in
      // MatriboxNamTransferSessionTest.kt ("not eligible (monitoring active) refuses...").
      expect(manager, contains('probeEligibility(BuildConfig.REAL_MATRIBOX_WRITE)'));
      // Direction 2 (session -> monitor): startCapture() must refuse while a session is active,
      // before it ever touches the monitor or the batch buffer.
      final startCapture = manager.substring(
        manager.indexOf('fun startCapture()'),
        manager.indexOf('fun blocksRawUsb('),
      );
      expect(startCapture, contains('currentNamTransferSession?.isActive != true'));
      expect(
        startCapture.indexOf('currentNamTransferSession'),
        lessThan(startCapture.indexOf('monitor.start(')),
      );
      // Session cleanup: cancelled on both device-lifecycle teardown paths, same as the other two
      // senders.
      final close = manager.substring(manager.indexOf('fun closeDevice()'), manager.indexOf('fun startCapture()'));
      expect(close, contains('currentNamTransferSession?.cancel()'));
      final detach = manager.substring(manager.indexOf('fun onUsbDetached('), manager.indexOf('fun resume()'));
      expect(detach, contains('currentNamTransferSession?.cancel()'));
    },
  );

  test(
    'product NAM transfer V1.1: no process-lifetime write budget exists; the per-attempt guard '
    'refuses only a SECOND session while one is still active, checked before any frame is validated',
    () {
      final manager = _code('${_base}MidiDiagnosticsManager.kt');
      // The certification-only "one real write per app process, ever" rail
      // (V5B.2d) is intentionally gone -- the finished product supports
      // repeated sequential transfers without an app restart. Guard against
      // it silently coming back.
      expect(manager, isNot(contains('namTransferAttempted')));
      expect(manager, isNot(contains('bereits versucht; kein zweiter Versuch')));
      final execute = manager.substring(
        manager.indexOf('fun executeNamCloneTransferSession('),
        manager.indexOf('fun startCapture()'),
      );
      // The real, narrower guard: refuses only while a PREVIOUS session is
      // still actually running (mutual exclusion, not a one-shot budget).
      expect(execute, contains('requireNoActiveNamTransferSession()'));
      expect(
        execute.indexOf('requireNoActiveNamTransferSession()'),
        lessThan(execute.indexOf('MatriboxNamCloneTransferReference.parseValidated')),
      );
      final guard = manager.substring(
        manager.indexOf('fun requireNoActiveNamTransferSession('),
        manager.indexOf('fun executeNamCloneTransferSession('),
      );
      expect(guard, contains('currentNamTransferSession?.isActive != true'));
      // Each session is still one-shot on its OWN instance (never reused):
      // MatriboxNamTransferSession's own `used` flag, unchanged by this file.
      final session = _code('${_base}MatriboxNamTransferSession.kt');
      expect(session, contains('private val used = AtomicBoolean(false)'));
      expect(session, contains('ALREADY_USED'));
    },
  );
}
