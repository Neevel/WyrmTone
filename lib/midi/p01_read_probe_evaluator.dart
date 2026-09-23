import '../presets/p01_readback_decoder.dart';
import '../presets/preset_selection_codec.dart';
import 'midi_parser.dart';

/// Result states for the one-shot P01 read probe. Pure/offline evaluation:
/// this file never opens a MIDI port or sends anything, it only classifies
/// bytes the native side already received.
enum P01ReadProbeOutcome {
  /// A complete cycle named [expectedPresetName] was decoded and all six
  /// AMP markers exactly match the values confirmed in
  /// docs/MATRIBOX_OFFLINE_ANALYSIS.md.
  confirmed,

  /// A complete cycle named [expectedPresetName] was decoded, but at least
  /// one AMP marker differs from the confirmed reference values. This does
  /// NOT mean the request is wrong -- P01 may simply have been changed
  /// since. The actually decoded values are reported, never suppressed.
  receivedButMismatch,

  /// Some device bytes were received, but no complete, name-matching
  /// 10-part cycle could be reconstructed (e.g. only part 0 arrived).
  incomplete,

  /// No device bytes were received at all within the listening window.
  timeout,

  /// Bytes were received but the MIDI/SysEx framing itself was malformed
  /// (truncated or interrupted SysEx, unexpected running-status bytes).
  parseError,
}

const expectedPresetName = 'CKY 96 STUD';

/// The exact marker values confirmed in
/// docs/MATRIBOX_OFFLINE_ANALYSIS.md ("Vollständiger Device→Host-Readback
/// und Persistenzbeweis") for the Sol-100-OD AMP block of User-P01.
const expectedMarkers = <String, double>{
  'gain': 17,
  'presence': 73,
  'volume': 47,
  'bass': 23,
  'middle': 67,
  'treble': 31,
};

class P01ReadProbeVerdict {
  const P01ReadProbeVerdict({
    required this.outcome,
    this.decoded,
    this.observationCount = 0,
  });

  final P01ReadProbeOutcome outcome;
  final DecodedPresetReadback? decoded;
  final int observationCount;

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'observationCount': observationCount,
    'decoded': decoded?.toJson(),
  };
}

/// Evaluates the raw device->host byte chunks collected by the native
/// one-shot read probe. [nativeSuccess] is false when the native side could
/// not even send the request or hit an internal error (treated the same as
/// a timeout: no interpretable device data exists). [chunks] are raw MIDI
/// byte fragments in arrival order, exactly as received from the device's
/// output port -- USB-MIDI/SysEx framing is handled here via the existing
/// [MidiParser], the same reassembly used by the passive MIDI monitor.
P01ReadProbeVerdict evaluateP01ReadProbeResponse({
  required bool nativeSuccess,
  required List<List<int>> chunks,
  String expectedName = expectedPresetName,
  Map<String, double> expected = expectedMarkers,
}) {
  if (!nativeSuccess) {
    return const P01ReadProbeVerdict(outcome: P01ReadProbeOutcome.timeout);
  }
  final totalBytes = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  if (totalBytes == 0) {
    return const P01ReadProbeVerdict(outcome: P01ReadProbeOutcome.timeout);
  }

  final parser = MidiParser();
  final observations = <TimedMidiObservation>[];
  var malformed = false;
  for (final chunk in chunks) {
    for (final parsed in parser.feed(chunk, 0)) {
      if (parsed.type != 'SysEx') continue;
      if (parsed.status == 'vollständig') {
        observations.add(
          TimedMidiObservation(
            bytes: parsed.bytes,
            direction: PresetSelectionDirection.deviceToHost,
          ),
        );
      } else {
        malformed = true;
      }
    }
  }
  for (final parsed in parser.finish()) {
    if (parsed.type == 'SysEx') malformed = true;
  }

  if (observations.isEmpty) {
    return P01ReadProbeVerdict(
      outcome: malformed
          ? P01ReadProbeOutcome.parseError
          : P01ReadProbeOutcome.incomplete,
    );
  }

  final matches = decodeMatchingPresets(observations, expectedName: expectedName);
  if (matches.isEmpty) {
    return P01ReadProbeVerdict(
      outcome: P01ReadProbeOutcome.incomplete,
      observationCount: observations.length,
    );
  }

  final decoded = matches.first;
  final actual = <String, double>{
    'gain': decoded.gain,
    'presence': decoded.presence,
    'volume': decoded.volume,
    'bass': decoded.bass,
    'middle': decoded.middle,
    'treble': decoded.treble,
  };
  final allMatch = expected.entries.every(
    (entry) => actual[entry.key] == entry.value,
  );
  return P01ReadProbeVerdict(
    outcome: allMatch
        ? P01ReadProbeOutcome.confirmed
        : P01ReadProbeOutcome.receivedButMismatch,
    decoded: decoded,
    observationCount: observations.length,
  );
}
