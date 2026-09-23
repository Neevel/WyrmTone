import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One compile-gated, fixed-message probe. [portAdapterFile] is the sole
/// file allowed to call Android's `.send(` / hold a `MidiInputPort`;
/// [validateCall] and [buildConfigFlag] are the exact source strings that
/// file (and, for [buildConfigFlag], `MidiDiagnosticsManager.kt`) must
/// contain.
class _ProbeDescriptor {
  const _ProbeDescriptor({
    required this.portAdapterFile,
    required this.validateCall,
    required this.buildConfigFlag,
  });
  final String portAdapterFile;
  final String validateCall;
  final String buildConfigFlag;
}

const _probes = [
  _ProbeDescriptor(
    portAdapterFile: 'VerifiedMatriboxProbePort.kt',
    validateCall: 'VerifiedGain41Reference.validate(reference)',
    buildConfigFlag:
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'VerifiedPresetP01ProbePort.kt',
    validateCall: 'VerifiedPresetP01Reference.validate(reference)',
    buildConfigFlag:
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_PRESET_P01_PROBE',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'VerifiedPresetP01ReadProbePort.kt',
    validateCall: 'VerifiedPresetP01ReadRequestReference.validate(reference)',
    buildConfigFlag:
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_READ_PROBE',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'VerifiedPresetP01FullReadProbePort.kt',
    validateCall: 'VerifiedPresetP01FullReadReference.validate()',
    buildConfigFlag:
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'VerifiedPresetP01FullReadProbeV3APort.kt',
    validateCall: 'VerifiedPresetP01PhaseDReference.validateAnnounce()',
    buildConfigFlag: 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'MatriboxPresetReaderPort.kt',
    // validates both confirmed references AND that they are User/Slot 0 where the slot byte is replaced
    validateCall: 'MatriboxUserSlotReadReference.validate()',
    buildConfigFlag: 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'MatriboxConfirmedGainWriterPort.kt',
    validateCall: 'MatriboxConfirmedGainWriter.validate(message)',
    buildConfigFlag: 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_GAIN_WRITE',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'MatriboxSol100OdAmpWriterPort.kt',
    validateCall: 'MatriboxSol100OdAmpWriter.validate(field, message)',
    buildConfigFlag:
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'MatriboxToneTransferWriterPort.kt',
    validateCall: 'MatriboxFullLiveCodec.validate(message)',
    buildConfigFlag: 'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER',
  ),
  _ProbeDescriptor(
    portAdapterFile: 'MatriboxFullLiveWriterPort.kt',
    validateCall: 'MatriboxFullLiveCodec.validate(message)',
    buildConfigFlag:
        'BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION',
  ),
];

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

  test('only the ten compile-gated fixed probes/readers/writers may open input or send', () async {
    final files = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>();
    for (final file in files.where((file) => file.path.endsWith('.kt'))) {
      final source = await file.readAsString();
      final matchingProbe = _probes
          .where((probe) => file.path.endsWith(probe.portAdapterFile))
          .toList();
      final probeAdapter = matchingProbe.isNotEmpty;
      final manager = file.path.endsWith('MidiDiagnosticsManager.kt');
      if (!manager) {
        expect(
          source,
          isNot(matches(RegExp(r'openInputPort\s*\('))),
          reason: file.path,
        );
      } else {
        expect(
          RegExp(r'openInputPort\s*\(').allMatches(source).length,
          _probes.length,
        );
        expect(source, contains('probeEligibility().check()'));
        for (final probe in _probes) {
          expect(source, contains(probe.buildConfigFlag));
        }
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
        final probe = matchingProbe.single;
        expect(RegExp(r'\.send\s*\(').allMatches(source).length, 1);
        expect(source, contains(probe.validateCall));
        expect(source, contains(probe.buildConfigFlag));
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
    expect(native, contains('openOutputPort('));
    final close = native.substring(
      native.indexOf('fun closeDevice()'),
      native.indexOf('fun startCapture()'),
    );
    expect(
      close.indexOf('stopCapture()'),
      lessThan(close.indexOf('session.close()')),
    );
    expect(close, contains('presetP01Probe.cancel()'));
    expect(close, contains('p01ReadProbe.cancel()'));
    expect(close, contains('p01FullReadProbe.cancel()'));
    expect(close, contains('p01FullReadProbeV3A.cancel()'));
    expect(close, contains('presetReader.cancel()'));
    expect(close, contains('gainWriteSession.cancel()'));
    expect(close, contains('certificationSession.cancel()'));
    expect(native, contains('presetP01Probe.detached(deviceName)'));
    expect(native, contains('p01ReadProbe.detached(deviceName)'));
    expect(native, contains('p01FullReadProbe.detached(deviceName)'));
    expect(native, contains('p01FullReadProbeV3A.detached(deviceName)'));
    expect(native, contains('gainWriteSession.detached(deviceName)'));
    expect(native, contains('certificationSession.detached(deviceName)'));
    expect(close, contains('fullLiveSession.cancel()'));
    expect(native, contains('fullLiveSession.detached(deviceName)'));
    expect(close, contains('toneTransferSession.cancel()'));
    expect(native, contains('toneTransferSession.detached(deviceName)'));
    // MatriboxPresetReader is not one-shot-per-connection (see class doc
    // comment): a detach only needs to abort any in-flight read via
    // cancel(), called from both closeDevice() and onUsbDetached().
    expect(
      RegExp(r'presetReader\.cancel\(\)').allMatches(native).length,
      2,
    );
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

  test(
    'the read probe never accepts a target slot/bank and never retries',
    () async {
      final source = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01ReadProbe.kt',
      ).readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'\b(retry|repeat|for|while)\s*\('))),
      );
      // No bank/slot parameter or variable declaration anywhere (prose in
      // doc comments explaining the restriction is fine and expected).
      expect(source, isNot(matches(RegExp(r'\b(bank|slot)\s*[:=]'))));
      final nativeFunctions = RegExp(r'fun[ ]+([A-Za-z0-9_]+)[ ]*[(]')
          .allMatches(source)
          .map((match) => match.group(1)!);
      expect(
        nativeFunctions.where(
          (name) => name.contains('P10') || name.contains('P11'),
        ),
        isEmpty,
      );
      final port = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01ReadProbePort.kt',
      ).readAsStringSync();
      expect(port, contains('input.send(reference, 0, reference.size)'));
    },
  );

  test('the full-read probe (V2) sends exactly its ten fixed requests, '
      'never retries and never accepts a target slot/bank/segment', () async {
    final source = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01FullReadProbe.kt',
    ).readAsStringSync();
    // A bounded `for` over the fixed ten-request list is required for the
    // sequential send/wait/verify design; an unbounded `while` (the shape
    // a retry loop would take) is not.
    expect(source, isNot(contains('while')));
    expect(source, isNot(matches(RegExp(r'\b(retry|repeat)\s*\('))));
    // No bank/slot/segment parameter or variable declaration anywhere
    // (prose in doc comments explaining the restriction is fine).
    expect(source, isNot(matches(RegExp(r'\b(bank|slot|segment)\s*[:=]'))));
    final nativeFunctions = RegExp(r'fun[ ]+([A-Za-z0-9_]+)[ ]*[(]')
        .allMatches(source)
        .map((match) => match.group(1)!);
    expect(
      nativeFunctions.where(
        (name) => name.contains('P10') || name.contains('P11'),
      ),
      isEmpty,
    );
    // Exactly ten hardcoded byte arrays -- the entire universe of what V2 can send.
    expect(RegExp(r'byteArrayOf\s*\(').allMatches(source).length, 10);
    expect(source, contains('requests.size == 10'));
    final port = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01FullReadProbePort.kt',
    ).readAsStringSync();
    expect(port, contains('input.send(reference, 0, reference.size)'));
    // The port only ever selects among the fixed list by index; it never
    // receives raw bytes from its caller.
    expect(port, isNot(contains('ByteArray)')));
  });

  test('V3A sends exactly one Phase-D announce plus the ten V2 requests -- '
      'never retries, never duplicates the ten requests, never accepts a '
      'target slot/bank/segment', () async {
    final source = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01FullReadProbeV3A.kt',
    ).readAsStringSync();
    expect(source, isNot(contains('while')));
    expect(source, isNot(matches(RegExp(r'\b(retry|repeat)\s*\('))));
    expect(source, isNot(matches(RegExp(r'\b(bank|slot|segment)\s*[:=]'))));
    final nativeFunctions = RegExp(r'fun[ ]+([A-Za-z0-9_]+)[ ]*[(]')
        .allMatches(source)
        .map((match) => match.group(1)!);
    expect(
      nativeFunctions.where(
        (name) => name.contains('P10') || name.contains('P11'),
      ),
      isEmpty,
    );
    // Exactly two hardcoded byte arrays in this file -- the Phase-D
    // announce and its byte-identical captured acknowledgement reference.
    // The ten part requests are reused unchanged from
    // VerifiedPresetP01FullReadReference (V2), never redefined here.
    expect(RegExp(r'byteArrayOf\s*\(').allMatches(source).length, 2);
    expect(source, contains('bytes.contentEquals(acknowledgement)'));
    expect(source, contains('VerifiedPresetP01FullReadReference.requests'));
    expect(
      source,
      contains('VerifiedPresetP01FullReadReference.isValidResponseForPart'),
    );
    // Phase D must gate Part 0: the part loop only exists on the
    // ack-confirmed branch, and the send-port interface exposes no way
    // to send a part request without going through it first.
    expect(source, contains('phaseDConfirmed = true'));
    final port = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/VerifiedPresetP01FullReadProbeV3APort.kt',
    ).readAsStringSync();
    expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);
    expect(port, contains('input.send(reference, 0, reference.size)'));
    // The public contract (VerifiedPresetP01FullReadV3ASendPort) only
    // exposes sendPhaseDAnnounce() and sendPartRequest(partIndex: Int) --
    // neither accepts a ByteArray, so the compiler itself guarantees no
    // raw bytes ever reach this port from a caller. The private
    // sendReference(ByteArray) helper below is an internal-only detail
    // fed exclusively by the two hardcoded references above.
    expect(port, isNot(contains('override fun sendPhaseDAnnounce(reference')));
    expect(
      port,
      isNot(matches(RegExp(r'override fun sendPartRequest\([^)]*ByteArray'))),
    );
  });

  test(
    'MatriboxPresetReader (production) reuses the confirmed Phase-D and V2 '
    'references unchanged, defines no new hardcoded bytes, never retries '
    'and distinguishes all seven required outcomes',
    () async {
      final source = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/MatriboxPresetReader.kt',
      ).readAsStringSync();
      expect(source, isNot(contains('while')));
      expect(source, isNot(matches(RegExp(r'\b(retry|repeat)\s*\('))));
      // The only addressing input is a validated User preset (P01..P99), never a raw bank/slot value.
      expect(source, isNot(matches(RegExp(r'\b(bank|segment)\s*[:=]'))));
      expect(
        RegExp(r'\bslot\s*[:=]\s*(\w+)').allMatches(source).map((m) => m.group(1)).toSet(),
        {'MatriboxUserPreset'},
      );
      final nativeFunctions = RegExp(r'fun[ ]+([A-Za-z0-9_]+)[ ]*[(]')
          .allMatches(source)
          .map((match) => match.group(1)!);
      expect(
        nativeFunctions.where(
          (name) => name.contains('P10') || name.contains('P11'),
        ),
        isEmpty,
      );
      // No hardcoded byte array anywhere in this file -- every byte it can
      // ever send comes from the already-confirmed V2/V3A references.
      expect(RegExp(r'byteArrayOf\s*\(').allMatches(source).length, 0);
      expect(source, contains('VerifiedPresetP01PhaseDReference'));
      expect(source, contains('VerifiedPresetP01FullReadReference.requests'));
      expect(source, contains('MatriboxUserSlotReadReference.validate()'));
      expect(source, contains('MatriboxUserSlotReadReference.isValidResponse(it, slot, partIndex)'));
      expect(source, contains('MatriboxUserSlotReadReference.isValidAck(it, slot)'));
      // The slot addressing derives every message from the confirmed references: no new bytes,
      // only the confirmed slot byte (offset 14) is replaced; responses must name that slot.
      final policy = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/MatriboxSlotPolicy.kt',
      ).readAsStringSync();
      expect(RegExp(r'byteArrayOf\s*\(').allMatches(policy).length, 0);
      expect(policy, contains('const val SLOT_OFFSET = 14'));
      expect(policy, contains('reference.copyOf().also { it[SLOT_OFFSET] = slot.deviceIndex.toByte() }'));
      expect(policy, contains('VerifiedPresetP01FullReadReference.isValidResponseForPart(bytes, partIndex)'));
      expect(policy, contains('bytes[SLOT_OFFSET] == slot.deviceIndex.toByte()'));
      for (final outcome in [
        'SUCCESS',
        'PHASE_D_TIMEOUT',
        'PHASE_D_INVALID',
        'PART_TIMEOUT',
        'PART_INVALID',
        'INCOMPLETE',
        'TRANSPORT_ERROR',
      ]) {
        expect(source, contains(outcome));
      }
      // Only a genuine native exception maps to TRANSPORT_ERROR; every
      // other branch assigns one of the six informational outcomes.
      expect(source, contains('catch (thrown: Exception)'));

      final port = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/MatriboxPresetReaderPort.kt',
      ).readAsStringSync();
      expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);
      expect(port, contains('input.send(reference, 0, reference.size)'));
      expect(
        port,
        isNot(contains('override fun sendPhaseDAnnounce(reference')),
      );
      expect(
        port,
        isNot(matches(RegExp(r'override fun sendPartRequest\([^)]*ByteArray'))),
      );
    },
  );

  test('probe channels are parameterless and release build is disabled', () {
    final channels = File(
      'android/app/src/main/kotlin/de/neevel/wyrmtone/UsbPlatformChannels.kt',
    ).readAsStringSync();
    for (final method in [
      'sendVerifiedSol100OdGain41Probe',
      'sendVerifiedPresetP01SelectionProbe',
      'sendVerifiedPresetP01ReadProbe',
      'sendVerifiedPresetP01FullReadProbe',
      'sendVerifiedPresetP01FullReadProbeV3A',
      'readMatriboxUserP01',
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
    expect(
      gradle,
      contains(
        'requestedP01ReadProbe && !requestedGain41Probe && !requestedPresetP01Probe',
      ),
    );
    expect(
      gradle,
      contains(
        'requestedP01FullReadProbe && !requestedGain41Probe && '
        '!requestedPresetP01Probe && !requestedP01ReadProbe',
      ),
    );
    expect(
      gradle,
      contains(
        'requestedP01FullReadProbeV3A && !requestedGain41Probe && '
        '!requestedPresetP01Probe && !requestedP01ReadProbe && '
        '!requestedP01FullReadProbe',
      ),
    );
    // Requesting only GAIN_WRITE also enables RAW_BACKUP (the Safe Write
    // Lab's prepare step reads and backs up P01 before it can write) --
    // these two are deliberately NOT mutually exclusive with each other,
    // unlike every other pair in this list.
    expect(
      gradle,
      contains(
        'val enableP01RawBackup = (requestedP01RawBackup || requestedP01GainWrite || requestedSol100OdCertification || requestedFullLive || requestedAngelsProduct || requestedToneTransfer || requestedFamilyExpansion) && '
        '!requestedGain41Probe && !requestedPresetP01Probe && '
        '!requestedP01ReadProbe && !requestedP01FullReadProbe && '
        '!requestedP01FullReadProbeV3A',
      ),
    );
    expect(
      gradle,
      contains(
        'val enableP01GainWrite = requestedP01GainWrite && !requestedGain41Probe && '
        '!requestedPresetP01Probe && !requestedP01ReadProbe && '
        '!requestedP01FullReadProbe && !requestedP01FullReadProbeV3A',
      ),
    );
    // Every pre-existing flag not involved in the RAW_BACKUP/GAIN_WRITE
    // pairing must still exclude the new gain-write flag.
    for (final earlierFlag in [
      'enableWriteProbe',
      'enablePresetP01Probe',
      'enableP01ReadProbe',
      'enableP01FullReadProbe',
      'enableP01FullReadProbeV3A',
    ]) {
      final start = gradle.indexOf('val $earlierFlag =');
      final end = gradle.indexOf('\n', start);
      expect(gradle.substring(start, end), contains('!requestedP01GainWrite'), reason: earlierFlag);
    }
    // RAW_BACKUP and GAIN_WRITE deliberately do NOT exclude each other.
    expect(
      gradle.substring(gradle.indexOf('val enableP01RawBackup ='), gradle.indexOf('\n', gradle.indexOf('val enableP01RawBackup ='))),
      isNot(contains('!requestedP01GainWrite')),
    );
    expect(
      gradle.substring(gradle.indexOf('val enableP01GainWrite ='), gradle.indexOf('\n', gradle.indexOf('val enableP01GainWrite ='))),
      isNot(contains('!requestedP01RawBackup')),
    );
    for (final flag in [
      'ENABLE_MATRIBOX_WRITE_PROBE',
      'ENABLE_MATRIBOX_PRESET_P01_PROBE',
      'ENABLE_MATRIBOX_P01_READ_PROBE',
      'ENABLE_MATRIBOX_P01_FULL_READ_PROBE',
      'ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A',
      'ENABLE_MATRIBOX_P01_RAW_BACKUP',
      'ENABLE_MATRIBOX_P01_GAIN_WRITE',
      'ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION',
      'ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION',
      'ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION',
      'ENABLE_MATRIBOX_TONE_TRANSFER',
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

  test(
    'writeConfirmedSol100OdGain takes exactly targetGain -- no algorithm, '
    'index, bank, slot or raw bytes cross the channel boundary',
    () {
      final channels = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/UsbPlatformChannels.kt',
      ).readAsStringSync();
      final start = channels.indexOf('"writeConfirmedSol100OdGain" ->');
      final end = channels.indexOf('\n            }\n', start);
      final gainWriteCase = channels.substring(start, end);
      expect(gainWriteCase, contains('arguments.keys != setOf("targetGain")'));
      expect(gainWriteCase, contains('midiManager.writeConfirmedSol100OdGain(targetGain.toDouble())'));
      // Only a Number is accepted for targetGain -- no free-form map/bytes.
      expect(gainWriteCase, contains('as? Number'));
      // Strip `//` prose comments (which legitimately name these words to
      // explain the restriction) before checking the actual code for a
      // forbidden second parameter/key.
      final gainWriteCode = gainWriteCase
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      for (final forbidden in [
        'algorithm',
        'parameterIndex',
        '"bank"',
        '"slot"',
        'ByteArray',
      ]) {
        expect(
          gainWriteCode.toLowerCase(),
          isNot(contains(forbidden.toLowerCase())),
          reason: forbidden,
        );
      }
      expect(channels, contains('"getMatriboxConfirmedGainWriteStatus" -> result.success(midiManager.gainWriteStatus())'));
    },
  );

  test(
    'Static Safety Search: no generic parameter-write surface exists anywhere',
    () async {
      // The public platform channel never exposes a free algorithm ID,
      // parameter index, bank, slot or raw-byte write -- only the one
      // fixed, named operation added in this milestone.
      final channels = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/UsbPlatformChannels.kt',
      ).readAsStringSync();
      expect(
        channels,
        isNot(
          matches(
            RegExp(
              r'"(writeParameter|sendParameter|writeConfirmedParameter|writeRaw|sendRaw)"',
            ),
          ),
        ),
      );
      expect(channels, isNot(contains('call.argument<Int>("algorithm")')));
      expect(channels, isNot(contains('call.argument<Int>("parameterIndex")')));
      expect(channels, isNot(contains('call.argument<Int>("bank")')));
      expect(channels, isNot(contains('call.argument<Int>("slot")')));

      // The native writer itself: exactly one public method that can
      // trigger a send, taking only a Double value -- no algorithm/index
      // parameter, no ByteArray parameter.
      final session = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/MatriboxConfirmedGainWriteSession.kt',
      ).readAsStringSync();
      expect(
        RegExp(r'fun writeConfirmedSol100OdGain\(targetGain: Double\)').hasMatch(session),
        isTrue,
      );
      expect(session, isNot(matches(RegExp(r'fun\s+\w*[Ww]rite\w*\([^)]*(algorithm|index|bank|slot|ByteArray)'))));

      final writer = File(
        'android/app/src/main/kotlin/de/neevel/wyrmtone/MatriboxConfirmedGainWriter.kt',
      ).readAsStringSync();
      // encode()/validate() only ever take a Float value or a fixed
      // ByteArray to re-check -- never an algorithm/index/bank/slot.
      expect(writer, isNot(matches(RegExp(r'fun\s+encode\([^)]*(algorithm|index|bank|slot)'))));
      expect(writer, contains('ALGORITHM_CODE'));
      expect(writer, contains('PARAMETER_INDEX'));

      // Confirms the complete inventory of send-capable surfaces has not
      // grown beyond: the six pre-existing experimental compile-gated
      // probes/readers, MatriboxPresetReaderPort (production read), and
      // MatriboxConfirmedGainWriterPort (this milestone's production
      // write) -- exactly matching `_probes` above.
      expect(_probes, hasLength(10));
    },
  );

  test(
    'AMP certification: only field + targetValue cross the channel, only '
    'whitelisted fields, User/P01, one write per session, no store/restore/retry',
    () {
      const base = 'android/app/src/main/kotlin/de/neevel/wyrmtone/';
      String code(String file) => File('$base$file')
          .readAsStringSync()
          .split('\n')
          .map((line) => line.split('//').first)
          .where((line) => !line.trimLeft().startsWith('*') && !line.trimLeft().startsWith('/*'))
          .join('\n');

      final channels = File('${base}UsbPlatformChannels.kt').readAsStringSync();
      final start = channels.indexOf('"writeCertificationAmpField" ->');
      final end = channels.indexOf('"getVerifiedMatriboxProbeStatus" ->', start);
      final certCase = channels
          .substring(start, end)
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      expect(certCase, contains('map.keys != setOf("field", "targetValue")'));
      expect(certCase, contains('midiManager.writeCertificationAmpField(fieldName, targetValue.toDouble())'));
      expect(certCase, contains('as? String'));
      expect(certCase, contains('as? Number'));
      for (final forbidden in ['algorithm', 'parameterIndex', 'ByteArray', '"bank"', '"slot"', 'sysex']) {
        expect(certCase.toLowerCase(), isNot(contains(forbidden.toLowerCase())), reason: forbidden);
      }

      final files = [
        'MatriboxSol100OdAmpWriter.kt',
        'MatriboxSol100OdAmpWriterPort.kt',
        'MatriboxSol100OdCertificationSession.kt',
      ];
      for (final file in files) {
        final source = code(file);
        expect(source, isNot(matches(RegExp(r'fun\s+\w*([Ss]tore|[Rr]estore|[Rr]etry)\w*\('))), reason: file);
        expect(source, isNot(matches(RegExp(r'\b(while|for)\s*\(.*send'))), reason: file);
        expect(source, isNot(matches(RegExp(r'\b(bank|slot|factory)\s*[:=]', caseSensitive: false))), reason: file);
        expect(source, isNot(matches(RegExp(r'fun\s+\w+\([^)]*(ByteArray|parameterIndex|algorithm)[^)]*\)\s*:?[^{]*{[^}]*send'))), reason: file);
      }
      final session = code('MatriboxSol100OdCertificationSession.kt');
      expect(
        RegExp(r'fun writeCertificationAmpField\(fieldName: String, targetValue: Double\)').hasMatch(session),
        isTrue,
      );
      expect(session, contains('attemptedConnections'));
      expect(session, contains('CERTIFICATION_FIELDS'));
      final writer = File('${base}MatriboxSol100OdAmpWriter.kt').readAsStringSync();
      expect(writer, contains('listOf(PRESENCE, VOLUME, BASS, MIDDLE, TREBLE)'));
      expect(writer, contains('const val ALGORITHM_CODE = 0x07000047'));
      final port = File('${base}MatriboxSol100OdAmpWriterPort.kt').readAsStringSync();
      expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);

      // Dart side: only User/P01, no arbitrary channel.
      final dartSession = File('lib/presets/matribox_amp_certification_session.dart').readAsStringSync();
      expect(dartSession, contains('snapshot.presetNumber != 1 || !snapshot.isUserBank'));
      final dartPanel = File('lib/screens/matribox_amp_certification_panel.dart').readAsStringSync();
      expect(dartPanel, contains("{'field': field, 'targetValue': targetValue}"));
      expect(dartPanel, isNot(contains('writeParameter')));
      expect(dartPanel, isNot(contains("'algorithm'")));
      expect(dartPanel, isNot(contains("'parameterIndex'")));
    },
  );

  test(
    'Full Live certification: only the plan id crosses the channel, fixed '
    'plan, closed slot set, no store/restore/retry, one send call site',
    () {
      const base = 'android/app/src/main/kotlin/de/neevel/wyrmtone/';
      String code(String file) => File('$base$file')
          .readAsStringSync()
          .split('\n')
          .map((line) => line.split('//').first)
          .where((line) => !line.trimLeft().startsWith('*') && !line.trimLeft().startsWith('/*'))
          .join('\n');

      final channels = File('${base}UsbPlatformChannels.kt').readAsStringSync();
      final start = channels.indexOf('"runFullLiveP01Certification" ->');
      expect(start, greaterThan(-1));
      final end = channels.indexOf('\n            }\n', start);
      final fullLiveCase = channels
          .substring(start, end)
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      expect(fullLiveCase, contains('keys != setOf("planId")'));
      for (final forbidden in ['algorithm', 'parameterIndex', 'ByteArray', '"bank"', '"slot"', 'sysex', 'bytes']) {
        expect(fullLiveCase.toLowerCase(), isNot(contains(forbidden.toLowerCase())), reason: forbidden);
      }

      for (final file in [
        'MatriboxFullLiveCodec.kt',
        'MatriboxFullLivePlan.kt',
        'MatriboxFullLiveWriterPort.kt',
        'MatriboxFullLiveCertificationSession.kt',
      ]) {
        final source = code(file);
        expect(source, isNot(matches(RegExp(r'fun\s+\w*([Ss]tore|[Rr]estore|[Rr]etry|[Cc]ommit)\w*\('))), reason: file);
        expect(source, isNot(matches(RegExp(r'\b(while)\s*\(.*send'))), reason: file);
      }
      final port = code('MatriboxFullLiveWriterPort.kt');
      expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);
      expect(port, contains('MatriboxCertificationPlans.permitted'));
      final codec = code('MatriboxFullLiveCodec.kt');
      expect(codec, contains('validate'));
      // 12 11 (metadata) and 12 12 (Store/commit) are refused, never encoded.
      expect(codec, isNot(matches(RegExp(r'fun\s+(encode|build)\w*\([^)]*(ByteArray|Int)\s*[,)]\s*[^)]*\)\s*:\s*ByteArray[^{]*{[^}]*0x12,\s*0x12'))));
      final session = code('MatriboxFullLiveCertificationSession.kt');
      expect(session, contains('attemptedConnections'));
      expect(session, contains('resolvedPlan == null')); // unknown plan id: rejected before anything opens

      // Dart side: closed slot enum, plan id only, no generic send API.
      final dartPanel = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
      expect(dartPanel, contains("{'planId': planId}"));
      expect(dartPanel, isNot(contains("'algorithm'")));
      expect(dartPanel, isNot(contains("'parameterIndex'")));
      final slot = File('lib/presets/matribox_chain_slot.dart').readAsStringSync();
      expect(slot, contains('enum MatriboxChainSlot'));
      final dartSession = File('lib/presets/matribox_full_live_session.dart').readAsStringSync();
      expect(dartSession, contains('isUserBank'));
    },
  );
}
