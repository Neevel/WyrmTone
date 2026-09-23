import 'matribox_user_slot.dart';

enum PresetSelectionDirection { hostToDevice, deviceToHost }

enum MidiObservationState { completeSysEx, incompleteSysEx, otherMidi }

enum KnownMatriboxPresetSelectionTarget {
  p01(deviceIndex: 0, presetNumber: 1),
  p10(deviceIndex: 9, presetNumber: 10),
  p11(deviceIndex: 10, presetNumber: 11);

  const KnownMatriboxPresetSelectionTarget({
    required this.deviceIndex,
    required this.presetNumber,
  });

  final int deviceIndex;
  final int presetNumber;

  String get label => 'P${presetNumber.toString().padLeft(2, '0')}';

  static KnownMatriboxPresetSelectionTarget? fromDeviceIndex(int deviceIndex) =>
      switch (deviceIndex) {
        0 => p01,
        9 => p10,
        10 => p11,
        _ => null,
      };
}

class PresetSelectionReferenceEvidence {
  const PresetSelectionReferenceEvidence({
    required this.target,
    required this.capture,
    required this.observedRepeatIntervalMs,
  });

  final KnownMatriboxPresetSelectionTarget target;
  final String capture;
  final double observedRepeatIntervalMs;
  int get deviceIndex => target.deviceIndex;
  String get presetLabel => target.label;
  bool get editorToMatriboxCapturePresent => true;
  bool get targetIndexConfirmed => true;
  bool get twoIdenticalTransmissionsObserved => true;
  bool get displayChangeConfirmed => true;
  bool get deviceWriteApproved => false;

  Map<String, Object?> toJson() => {
    'preset': presetLabel,
    'deviceIndex': deviceIndex,
    'capture': capture,
    'editorToMatriboxCapturePresent': editorToMatriboxCapturePresent,
    'targetIndexConfirmed': targetIndexConfirmed,
    'twoIdenticalTransmissionsObserved': twoIdenticalTransmissionsObserved,
    'observedRepeatIntervalMs': observedRepeatIntervalMs,
    'displayChangeConfirmed': displayChangeConfirmed,
    'deviceWriteApproved': deviceWriteApproved,
  };
}

class OfflinePresetSelectionMessage {
  const OfflinePresetSelectionMessage(this.target);

  final KnownMatriboxPresetSelectionTarget target;
  MatriboxUserSlot get slot => MatriboxUserSlot.fromDeviceIndex(target.deviceIndex);
  int get targetIndex => target.deviceIndex;
  int get targetPreset => target.presetNumber;
  String get presetLabel => target.label;
  bool get deviceWriteApproved => false;
}

class PresetCandidateRejection {
  const PresetCandidateRejection({
    required this.reason,
    required this.offset,
    required this.observedValue,
  });

  final String reason;
  final int offset;
  final int observedValue;
}

abstract final class ConfirmedPresetSelectionCodec {
  static final knownDeviceIndices = Set<int>.unmodifiable(
    KnownMatriboxPresetSelectionTarget.values.map(
      (target) => target.deviceIndex,
    ),
  );
  static const references =
      <KnownMatriboxPresetSelectionTarget, PresetSelectionReferenceEvidence>{
        KnownMatriboxPresetSelectionTarget.p01:
            PresetSelectionReferenceEvidence(
              target: KnownMatriboxPresetSelectionTarget.p01,
              capture: '07_matribox_editor_select_P11_to_P01.pcapng',
              observedRepeatIntervalMs: 2.881,
            ),
        KnownMatriboxPresetSelectionTarget.p10:
            PresetSelectionReferenceEvidence(
              target: KnownMatriboxPresetSelectionTarget.p10,
              capture: '06_matribox_editor_select_test_B_to_test_A.pcapng',
              observedRepeatIntervalMs: 2.417,
            ),
        KnownMatriboxPresetSelectionTarget.p11:
            PresetSelectionReferenceEvidence(
              target: KnownMatriboxPresetSelectionTarget.p11,
              capture: '05_matribox_editor_select_test_A_to_test_B.pcapng',
              observedRepeatIntervalMs: 1.867,
            ),
      };
  static const _p01 = <int>[
    0xf0,
    0x21,
    0x25,
    0x7f,
    0x51,
    0x4d,
    0x45,
    0x32,
    0x12,
    0x00,
    0x02,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xf7,
  ];

  static OfflinePresetSelectionMessage decode(List<int> bytes) {
    final rejection = rejectionFor(bytes);
    if (rejection != null) {
      throw FormatException(
        '${rejection.reason} at offset ${rejection.offset}: '
        '0x${rejection.observedValue.toRadixString(16).padLeft(2, '0')}',
      );
    }
    return OfflinePresetSelectionMessage(
      KnownMatriboxPresetSelectionTarget.fromDeviceIndex(bytes[18])!,
    );
  }

  static PresetCandidateRejection? rejectionFor(List<int> bytes) {
    if (bytes.length != 22) {
      return PresetCandidateRejection(
        reason: 'unexpectedLength',
        offset: bytes.length,
        observedValue: bytes.length,
      );
    }
    for (var index = 0; index < _p01.length; index++) {
      if (index == 18) continue;
      if (bytes[index] != _p01[index]) {
        return PresetCandidateRejection(
          reason: index == 8 ? 'invalidFamily' : 'invalidConstant',
          offset: index,
          observedValue: bytes[index],
        );
      }
    }
    if (KnownMatriboxPresetSelectionTarget.fromDeviceIndex(bytes[18]) == null) {
      return PresetCandidateRejection(
        reason: 'unconfirmedTargetIndex',
        offset: 18,
        observedValue: bytes[18],
      );
    }
    return null;
  }

  static bool looksLikeCandidate(List<int> bytes) {
    if (bytes.length != 22) return false;
    final qme2 =
        bytes[4] == 0x51 &&
        bytes[5] == 0x4d &&
        bytes[6] == 0x45 &&
        bytes[7] == 0x32;
    final envelope =
        bytes[0] == 0xf0 &&
        bytes[1] == 0x21 &&
        bytes[2] == 0x25 &&
        bytes[3] == 0x7f &&
        bytes[21] == 0xf7;
    return qme2 || envelope;
  }

  /// Only byte-confirmed golden references can be reconstructed offline.
  static List<int> encodeReference(KnownMatriboxPresetSelectionTarget target) {
    final result = List<int>.of(_p01)..[18] = target.deviceIndex;
    return List<int>.unmodifiable(result);
  }
}

class TimedMidiObservation {
  const TimedMidiObservation({
    required this.bytes,
    required this.direction,
    this.timestampMs,
    this.state = MidiObservationState.completeSysEx,
  });

  final List<int> bytes;
  final PresetSelectionDirection direction;
  final double? timestampMs;
  final MidiObservationState state;
}

abstract class PresetSelectionFinding {
  const PresetSelectionFinding();
  Map<String, Object?> toJson();
}

class PresetSelectionAnalysis extends PresetSelectionFinding {
  const PresetSelectionAnalysis({
    required this.message,
    required this.direction,
    required this.repeatCount,
    required this.identicalRepeats,
    required this.repeatIntervalsMs,
    required this.possibleDeviceResponses,
  });

  final OfflinePresetSelectionMessage message;
  final PresetSelectionDirection direction;
  final int repeatCount;
  final bool identicalRepeats;
  final List<double> repeatIntervalsMs;
  final int possibleDeviceResponses;

  @override
  Map<String, Object?> toJson() {
    final evidence = ConfirmedPresetSelectionCodec.references[message.target]!;
    return {
      'family': 'presetSelection',
      'targetIndex': message.targetIndex,
      'targetPreset': message.presetLabel,
      'direction': direction.name,
      'repeatCount': repeatCount,
      'identicalRepeats': identicalRepeats,
      'repeatIntervalMs': repeatIntervalsMs.length == 1
          ? repeatIntervalsMs.single
          : repeatIntervalsMs,
      'possibleDeviceResponses': possibleDeviceResponses,
      'confirmedMidiResponse': false,
      'referenceEvidence': evidence.toJson(),
      'evidenceLevel': 'confirmedControlledCapture',
      'deviceWriteApproved': false,
    };
  }
}

class RejectedPresetSelectionCandidate extends PresetSelectionFinding {
  const RejectedPresetSelectionCandidate(this.observation, this.rejection);
  final TimedMidiObservation observation;
  final PresetCandidateRejection rejection;

  @override
  Map<String, Object?> toJson() => {
    'family': 'rejectedPresetSelectionCandidate',
    'direction': observation.direction.name,
    'length': observation.bytes.length,
    'rejectionReason': rejection.reason,
    'invalidOffset': rejection.offset,
    'observedValue': rejection.observedValue,
    'deviceWriteApproved': false,
  };
}

class UnclassifiedDeviceTraffic extends PresetSelectionFinding {
  const UnclassifiedDeviceTraffic(this.count);
  final int count;

  @override
  Map<String, Object?> toJson() => {
    'family': 'unclassifiedDeviceTraffic',
    'direction': PresetSelectionDirection.deviceToHost.name,
    'count': count,
    'possiblePresetResponse': false,
    'deviceWriteApproved': false,
  };
}

class IncompleteSysExFinding extends PresetSelectionFinding {
  const IncompleteSysExFinding(this.observation);
  final TimedMidiObservation observation;

  @override
  Map<String, Object?> toJson() => {
    'family': 'incompleteSysEx',
    'direction': observation.direction.name,
    'length': observation.bytes.length,
    'complete': false,
    'deviceWriteApproved': false,
  };
}

List<PresetSelectionFinding> analyzePresetSelections(
  List<TimedMidiObservation> observations,
) {
  final findings = <PresetSelectionFinding>[];
  final host = <TimedMidiObservation>[];
  final device = <TimedMidiObservation>[];
  for (final observation in observations) {
    if (observation.bytes.isEmpty) continue;
    if (observation.state == MidiObservationState.incompleteSysEx) {
      findings.add(IncompleteSysExFinding(observation));
      if (observation.direction == PresetSelectionDirection.deviceToHost) {
        device.add(observation);
      }
      continue;
    }
    if (observation.direction == PresetSelectionDirection.deviceToHost) {
      device.add(observation);
      continue;
    }
    if (!ConfirmedPresetSelectionCodec.looksLikeCandidate(observation.bytes)) {
      continue;
    }
    final rejection = ConfirmedPresetSelectionCodec.rejectionFor(
      observation.bytes,
    );
    if (rejection != null) {
      findings.add(RejectedPresetSelectionCandidate(observation, rejection));
    } else {
      host.add(observation);
    }
  }

  final matchedDevice = <TimedMidiObservation>{};
  var cursor = 0;
  while (cursor < host.length) {
    final first = host[cursor];
    var end = cursor + 1;
    while (end < host.length && _sameBytes(first.bytes, host[end].bytes)) {
      end++;
    }
    final repeats = host.sublist(cursor, end);
    final intervals = <double>[];
    for (var i = 1; i < repeats.length; i++) {
      final before = repeats[i - 1].timestampMs;
      final after = repeats[i].timestampMs;
      if (before != null && after != null) intervals.add(after - before);
    }
    final decoded = ConfirmedPresetSelectionCodec.decode(first.bytes);
    final lastHostTime = repeats.last.timestampMs;
    final possible = device.where((candidate) {
      if (candidate.state != MidiObservationState.completeSysEx ||
          lastHostTime == null ||
          candidate.timestampMs == null ||
          candidate.timestampMs! < lastHostTime ||
          candidate.timestampMs! - lastHostTime > 100) {
        return false;
      }
      try {
        return ConfirmedPresetSelectionCodec.decode(candidate.bytes)
                .targetIndex ==
            decoded.targetIndex;
      } on FormatException {
        return false;
      }
    }).toList();
    matchedDevice.addAll(possible);
    findings.add(
      PresetSelectionAnalysis(
        message: decoded,
        direction: first.direction,
        repeatCount: repeats.length,
        identicalRepeats: repeats.every(
          (entry) => _sameBytes(first.bytes, entry.bytes),
        ),
        repeatIntervalsMs: List.unmodifiable(intervals),
        possibleDeviceResponses: possible.length,
      ),
    );
    cursor = end;
  }
  final unclassified = device
      .where((entry) => !matchedDevice.contains(entry))
      .length;
  if (unclassified > 0) findings.add(UnclassifiedDeviceTraffic(unclassified));
  return List.unmodifiable(findings);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
