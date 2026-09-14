import 'preset_selection_codec.dart';

enum EvidenceLevel { observed, correlated, confirmed, unknown }

class ProtocolCapability {
  const ProtocolCapability({
    required this.id,
    required this.description,
    required this.level,
    required this.sources,
    required this.write,
    this.productionApproved = false,
    this.hardwareTestRequired = true,
    this.sourceTarget = 'matriboxOne',
    this.messageFamily = 'unknown',
    this.knownLengths = const [],
    this.relevantOffsets = const {},
    this.direction = 'unknown',
    this.matriboxOneTested = false,
    this.matriboxIiProTested = false,
    this.hardwareTestPossible = false,
    this.nextEvidenceStep = 'controlled capture required',
    required this.limitations,
  });
  final String id, description;
  final EvidenceLevel level;
  final List<String> sources, limitations;
  final bool write, productionApproved, hardwareTestRequired;
  final String sourceTarget, messageFamily, direction, nextEvidenceStep;
  final List<int> knownLengths;
  final Map<String, String> relevantOffsets;
  final bool matriboxOneTested, matriboxIiProTested, hardwareTestPossible;
  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'evidenceLevel': level.name,
    'sources': sources,
    'access': write ? 'write' : 'read',
    'productionApproved': productionApproved,
    'hardwareTestRequired': hardwareTestRequired,
    'sourceTarget': sourceTarget,
    'messageFamily': messageFamily,
    'knownLengths': knownLengths,
    'relevantOffsets': relevantOffsets,
    'direction': direction,
    'matriboxOneTested': matriboxOneTested,
    'matriboxIiProTested': matriboxIiProTested,
    'hardwareTestPossible': hardwareTestPossible,
    'nextEvidenceStep': nextEvidenceStep,
    'limitations': limitations,
  };
}

class CapabilityDecision {
  const CapabilityDecision(this.allowed, this.capability, this.reason);
  final bool allowed;
  final ProtocolCapability? capability;
  final String reason;
}

class PcEditorPresetSelectionEvidence {
  const PcEditorPresetSelectionEvidence({
    required this.capture,
    required this.observedRepeatIntervalMs,
  });

  final String capture;
  final double observedRepeatIntervalMs;
  final bool editorToMatriboxCapturePresent = true;
  final bool targetIndexConfirmed = true;
  final bool twoIdenticalTransmissionsObserved = true;
  final bool displayChangeConfirmed = true;
  final bool deviceResponseConfirmed = false;
}

class WyrmTonePresetSelectionHardwareEvidence {
  const WyrmTonePresetSelectionHardwareEvidence({
    required this.testedOn,
    required this.androidDevice,
    required this.observedRepeatIntervalMs,
  });

  final String testedOn;
  final String androidDevice;
  final double observedRepeatIntervalMs;
  final String transport = 'Android MIDI';
  final int transmittedMessageCount = 2;
  final bool identicalKnownMessages = true;
  final bool androidSendCallsSuccessful = true;
  final bool displayChangeConfirmed = true;
  final bool saveOrStorePerformed = false;
  final bool deviceResponseConfirmed = false;
}

class ControlledPresetSelectionEvidence {
  const ControlledPresetSelectionEvidence({
    required this.target,
    required this.pcEditor,
    this.wyrmToneHardware,
  });

  final KnownMatriboxPresetSelectionTarget target;
  final PcEditorPresetSelectionEvidence pcEditor;
  final WyrmTonePresetSelectionHardwareEvidence? wyrmToneHardware;

  String get preset => target.label;
  int get deviceIndex => target.deviceIndex;
  bool get hasWyrmToneHardwareEvidence => wyrmToneHardware != null;
  bool get deviceWriteApproved => false;
}

abstract final class ProtocolEvidenceRegistry {
  static const controlledPresetSelections = <ControlledPresetSelectionEvidence>[
    ControlledPresetSelectionEvidence(
      target: KnownMatriboxPresetSelectionTarget.p01,
      pcEditor: PcEditorPresetSelectionEvidence(
        capture: '07_matribox_editor_select_P11_to_P01.pcapng',
        observedRepeatIntervalMs: 2.881,
      ),
      wyrmToneHardware: WyrmTonePresetSelectionHardwareEvidence(
        testedOn: '2026-09-14',
        androidDevice: 'Samsung SM_F946B',
        observedRepeatIntervalMs: 3.0,
      ),
    ),
    ControlledPresetSelectionEvidence(
      target: KnownMatriboxPresetSelectionTarget.p10,
      pcEditor: PcEditorPresetSelectionEvidence(
        capture: '06_matribox_editor_select_test_B_to_test_A.pcapng',
        observedRepeatIntervalMs: 2.417,
      ),
    ),
    ControlledPresetSelectionEvidence(
      target: KnownMatriboxPresetSelectionTarget.p11,
      pcEditor: PcEditorPresetSelectionEvidence(
        capture: '05_matribox_editor_select_test_A_to_test_B.pcapng',
        observedRepeatIntervalMs: 1.867,
      ),
    ),
  ];
  static const _analysis = ['docs/MATRIBOX_OFFLINE_ANALYSIS.md'];
  static const _hardware = ['docs/MATRIBOX_ONE.md'];
  static final capabilities = List<ProtocolCapability>.unmodifiable(<
    ProtocolCapability
  >[
    ProtocolCapability(
      id: 'usb.identity',
      description: 'Matribox 1 84EF:0054',
      level: EvidenceLevel.confirmed,
      sources: _hardware,
      write: false,
      productionApproved: true,
      hardwareTestRequired: false,
      matriboxOneTested: true,
      messageFamily: 'USB descriptor / Android MIDI association',
      direction: 'read',
      limitations: ['Identity does not authorize writes.'],
    ),
    ProtocolCapability(
      id: 'midi.device.open',
      description: 'Android MIDI association and explicit open/close',
      level: EvidenceLevel.confirmed,
      sources: _hardware,
      write: false,
      productionApproved: true,
      hardwareTestRequired: false,
      matriboxOneTested: true,
      messageFamily: 'Android MidiManager lifecycle',
      direction: 'bidirectional ports; no automatic send',
      limitations: ['No automatic open or port sending.'],
    ),
    ProtocolCapability(
      id: 'midi.port.direction',
      description: 'Android input sends to device; output receives from device',
      level: EvidenceLevel.confirmed,
      sources: _hardware,
      write: false,
      productionApproved: true,
      hardwareTestRequired: false,
      sourceTarget: 'matriboxOne',
      messageFamily: 'Android MidiManager ports',
      direction: 'input=appToDevice; output=deviceToApp',
      matriboxOneTested: true,
      nextEvidenceStep: 'none for port direction',
      limitations: ['Input remains closed except compile-gated probes.'],
    ),
    ProtocolCapability(
      id: 'message.lengths',
      description: 'Observed 18, 22, 34-byte messages',
      level: EvidenceLevel.observed,
      sources: _analysis,
      write: false,
      matriboxOneTested: true,
      knownLengths: [18, 22, 34],
      limitations: [
        '18-byte semantics and other 22-byte variants remain unknown; controlled preset selections are separate evidence.',
      ],
    ),
    ProtocolCapability(
      id: 'qme2.header',
      description: 'QME2 at offsets 4–7',
      level: EvidenceLevel.observed,
      sources: _analysis,
      write: false,
      matriboxOneTested: true,
      relevantOffsets: {'4-7': 'QME2'},
      limitations: ['No interpretation of constants 8–12.'],
    ),
    ProtocolCapability(
      id: 'parameter.algorithm',
      description: 'Nibble-paired LE algorithm code at 13–20',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      matriboxOneTested: true,
      messageFamily: 'QME2 parameter',
      knownLengths: [34],
      relevantOffsets: {'13-20': 'nibble-paired UInt32 LE'},
      direction: 'hostToDevice and deviceToHost observed',
      limitations: ['Confirmed comparison is Sol 100 OD Gain only.'],
    ),
    ProtocolCapability(
      id: 'parameter.index',
      description: 'Nibble-paired LE uint16 index at 21–24',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      matriboxOneTested: true,
      messageFamily: 'QME2 parameter',
      knownLengths: [34],
      relevantOffsets: {'21-24': 'nibble-paired UInt16 LE'},
      limitations: ['Offset 22 alone is not the complete index.'],
    ),
    ProtocolCapability(
      id: 'parameter.float',
      description: 'Nibble-paired LE float32 at 25–32',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      matriboxOneTested: true,
      messageFamily: 'QME2 parameter',
      knownLengths: [34],
      relevantOffsets: {'25-32': 'nibble-paired Float32 LE'},
      limitations: ['No generalized parameter semantics.'],
    ),
    ProtocolCapability(
      id: 'algorithm.solOd',
      description: 'Sol 100 OD 07000047',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      matriboxOneTested: true,
      limitations: ['Hardware confirmation limited to Gain 40→41.'],
    ),
    ProtocolCapability(
      id: 'algorithm.solLd',
      description: 'Sol 100 LD 07000059',
      level: EvidenceLevel.correlated,
      sources: _analysis,
      write: false,
      limitations: [
        'Local XML/passive capture correlation; no host-write approval.',
      ],
    ),
    ProtocolCapability(
      id: 'algorithm.califCl',
      description: 'Calif Star CL 07000019',
      level: EvidenceLevel.correlated,
      sources: _analysis,
      write: false,
      limitations: [
        'Local XML/passive capture correlation; no host-write approval.',
      ],
    ),
    ProtocolCapability(
      id: 'index.gain',
      description: 'Sol 100 OD Gain index 0',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      limitations: ['Do not apply confirmation to other algorithms.'],
    ),
    ProtocolCapability(
      id: 'index.bass',
      description: 'Sol 100 LD Bass index 3',
      level: EvidenceLevel.correlated,
      sources: _analysis,
      write: false,
      limitations: ['Passive controlled capture, not host-write confirmation.'],
    ),
    ProtocolCapability(
      id: 'index.middle',
      description: 'Sol 100 LD Middle index 4',
      level: EvidenceLevel.correlated,
      sources: _analysis,
      write: false,
      limitations: ['Passive controlled capture, not host-write confirmation.'],
    ),
    ProtocolCapability(
      id: 'gain40.bidirectional',
      description: 'Byte-equal editor OUT and device IN Gain 40',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      limitations: ['Equality does not establish an acknowledgement.'],
    ),
    ProtocolCapability(
      id: 'probe.gain41',
      description: 'Successful Android Sol 100 OD Gain 40→41 one-shot',
      level: EvidenceLevel.confirmed,
      sources: _hardware,
      write: true,
      matriboxOneTested: true,
      hardwareTestPossible: true,
      limitations: [
        'Compile-gated developer test only; saved starting preset required; no production approval.',
      ],
    ),
    ProtocolCapability(
      id: 'preset.select',
      description: 'Observed preset-selection family; confirmed targets are listed separately',
      level: EvidenceLevel.correlated,
      sources: _analysis,
      sourceTarget: 'matriboxOne',
      write: true,
      messageFamily: 'QME2 presetSelection',
      knownLengths: [22],
      relevantOffsets: {'8': 'family 0x12', '18': 'zero-based target index'},
      direction: 'hostToDevice',
      matriboxOneTested: true,
      hardwareTestPossible: true,
      nextEvidenceStep:
          'separate explicit compile-time approval before any P10 or P11 probe',
      limitations: [
        'P01 has a visible WyrmTone-to-Matribox 1 hardware confirmation over Android MIDI; P10 and P11 have PC-editor evidence only.',
        'Only P01, P10 and P11 target indices are confirmed; other preset slots are not inferred.',
        'Repeat necessity, a protocol-required delay and device acknowledgement remain unknown.',
        'No save/store behavior and no production write approval.',
      ],
    ),
    ProtocolCapability(
      id: 'expression',
      description: 'Expression pedal movement',
      level: EvidenceLevel.observed,
      sources: [
        ..._analysis,
        'https://github.com/hurricaneabel/Matribox_II_Pro_MidiCon',
      ],
      sourceTarget: 'matriboxOne and matriboxIiPro',
      write: false,
      messageFamily: 'Matribox 1 QME2 34-byte receive; II Pro CC11',
      knownLengths: [34],
      relevantOffsets: {'25-32': 'correlated Float32 movement value'},
      direction: 'deviceToHost observed on Matribox 1',
      matriboxOneTested: true,
      matriboxIiProTested: true,
      nextEvidenceStep: 'capture assigned pedal with visible endpoints',
      limitations: [
        'Matribox 1 parameter identity and scale are not confirmed.',
        'II Pro CC11 must not be used on Matribox 1.',
      ],
    ),
    ProtocolCapability(
      id: 'quickAccess',
      description: 'Quick-access controls',
      level: EvidenceLevel.observed,
      sources: [
        ..._analysis,
        'https://github.com/hurricaneabel/Matribox_II_Pro_MidiCon',
      ],
      sourceTarget: 'matriboxOne and matriboxIiPro',
      write: false,
      messageFamily: 'Matribox 1 QME2 18-byte observations; II Pro CC16-21',
      knownLengths: [18],
      direction: 'deviceToHost observed on Matribox 1',
      matriboxOneTested: true,
      matriboxIiProTested: true,
      nextEvidenceStep: 'one marked Matribox 1 control/value capture',
      limitations: ['No Matribox 1 control ID or write command confirmed.'],
    ),
    ProtocolCapability(
      id: 'drum',
      description: 'Drum machine',
      level: EvidenceLevel.observed,
      sources: [
        ..._analysis,
        'https://github.com/hurricaneabel/Matribox_II_Pro_MidiCon',
      ],
      sourceTarget: 'matriboxOne and matriboxIiPro',
      write: false,
      messageFamily: 'Matribox 1 QME2 18-byte observation; II Pro CC92-95',
      knownLengths: [18],
      direction: 'deviceToHost observed on Matribox 1',
      matriboxOneTested: true,
      matriboxIiProTested: true,
      nextEvidenceStep: 'separate play/stop/rhythm captures on Matribox 1',
      limitations: ['Single Matribox 1 observation has unknown semantics.'],
    ),
    for (final entry in <(String, String, bool)>[
      ('bank.navigation', 'Bank navigation', true),
      ('preset.status.read', 'Receive preset status', false),
      ('preset.name.read', 'Receive preset name', false),
      ('preset.name.write', 'Send preset name', false),
      ('preset.save', 'Persist preset', false),
      ('preset.read', 'Receive complete preset state', false),
      ('preset.transfer', 'Send complete preset state', false),
      ('effect.block.toggle', 'Toggle effect block', true),
      ('effect.model.select', 'Select effect model', false),
      ('parameter.write', 'Change parameter value', false),
      ('amp.select', 'Select amp model', false),
      ('cab.select', 'Select cab model', false),
      ('ir.slot.select', 'Select IR slot', false),
      ('nam.slot.select', 'Select NAM/Clone slot', false),
      ('mode.stompPreset', 'Stomp/Preset mode', true),
      ('bpm', 'Direct BPM', true),
      ('tapTempo', 'Tap tempo', true),
      ('tuner', 'Tuner', true),
      ('looper', 'Looper', true),
    ])
      ProtocolCapability(
        id: entry.$1,
        description: entry.$2,
        level: EvidenceLevel.unknown,
        sources: const [
          'https://github.com/hurricaneabel/Matribox_II_Pro_MidiCon',
        ],
        sourceTarget: 'matriboxIiPro',
        write: !entry.$1.endsWith('.read'),
        messageFamily: switch (entry.$1) {
          'preset.status.read' => 'II Pro receive SysEx; minimum length 40',
          'effect.model.select' ||
          'amp.select' ||
          'cab.select' ||
          'ir.slot.select' ||
          'nam.slot.select' =>
            'II Pro receive model SysEx; no write command established',
          _ => entry.$3 ? 'MIDI CC/PC documented for II Pro' : 'unknown',
        },
        knownLengths: switch (entry.$1) {
          'effect.model.select' => const [108, 128],
          'amp.select' ||
          'cab.select' ||
          'ir.slot.select' ||
          'nam.slot.select' => const [128],
          _ => const [],
        },
        relevantOffsets: switch (entry.$1) {
          'preset.status.read' => const {'38-39': 'II Pro bank/slot decoder'},
          'effect.model.select' => const {
            '58-59 or 60-61': 'II Pro model tuple',
          },
          'amp.select' ||
          'cab.select' ||
          'ir.slot.select' ||
          'nam.slot.select' => const {
            '60-61': 'II Pro model tuple',
            '49': 'II Pro category',
          },
          _ => const {},
        },
        direction: switch (entry.$1) {
          'preset.status.read' ||
          'effect.model.select' ||
          'amp.select' ||
          'cab.select' ||
          'ir.slot.select' ||
          'nam.slot.select' => 'deviceToHost decoder in II Pro source',
          _ => entry.$3 ? 'hostToDevice on II Pro' : 'unknown',
        },
        matriboxIiProTested: entry.$3,
        hardwareTestPossible: false,
        nextEvidenceStep: 'separate Matribox 1 controlled capture',
        limitations: const [
          'Public source concerns Matribox II Pro only.',
          'II Pro tested flags represent public author claims, not tests performed by WyrmTone.',
          'No Matribox 1 compatibility or WyrmTone write approval.',
        ],
      ),
    for (final id in [
      'preset.list',
      'preset.name',
      'preset.verify',
      'preset.restore',
      'algorithm.write',
      'ir.transfer',
      'nam.transfer',
    ])
      ProtocolCapability(
        id: id,
        description: 'Not confirmed: $id',
        level: EvidenceLevel.unknown,
        sources: _analysis,
        write: true,
        limitations: ['Full preset transmission is not protocol-confirmed.'],
      ),
  ]);
  static CapabilityDecision decide(String id) {
    final capability = capabilities.where((c) => c.id == id).firstOrNull;
    final allowed =
        capability != null &&
        capability.level == EvidenceLevel.confirmed &&
        capability.productionApproved;
    return CapabilityDecision(
      allowed,
      capability,
      allowed
          ? 'Explicitly approved'
          : 'Noch nicht für Geräteübertragung freigegeben',
    );
  }
}
