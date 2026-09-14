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
    required this.limitations,
  });
  final String id, description;
  final EvidenceLevel level;
  final List<String> sources, limitations;
  final bool write, productionApproved, hardwareTestRequired;
  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'evidenceLevel': level.name,
    'sources': sources,
    'access': write ? 'write' : 'read',
    'productionApproved': productionApproved,
    'hardwareTestRequired': hardwareTestRequired,
    'limitations': limitations,
  };
}

class CapabilityDecision {
  const CapabilityDecision(this.allowed, this.capability, this.reason);
  final bool allowed;
  final ProtocolCapability? capability;
  final String reason;
}

abstract final class ProtocolEvidenceRegistry {
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
      limitations: ['No automatic open or port sending.'],
    ),
    ProtocolCapability(
      id: 'message.lengths',
      description: 'Observed 18, 22, 34-byte messages',
      level: EvidenceLevel.observed,
      sources: _analysis,
      write: false,
      limitations: ['18/22-byte semantics remain unknown.'],
    ),
    ProtocolCapability(
      id: 'qme2.header',
      description: 'QME2 at offsets 4–7',
      level: EvidenceLevel.observed,
      sources: _analysis,
      write: false,
      limitations: ['No interpretation of constants 8–12.'],
    ),
    ProtocolCapability(
      id: 'parameter.algorithm',
      description: 'Nibble-paired LE algorithm code at 13–20',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      limitations: ['Confirmed comparison is Sol 100 OD Gain only.'],
    ),
    ProtocolCapability(
      id: 'parameter.index',
      description: 'Nibble-paired LE uint16 index at 21–24',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      limitations: ['Offset 22 alone is not the complete index.'],
    ),
    ProtocolCapability(
      id: 'parameter.float',
      description: 'Nibble-paired LE float32 at 25–32',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
      limitations: ['No generalized parameter semantics.'],
    ),
    ProtocolCapability(
      id: 'algorithm.solOd',
      description: 'Sol 100 OD 07000047',
      level: EvidenceLevel.confirmed,
      sources: _analysis,
      write: false,
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
      limitations: [
        'Compile-gated developer test only; saved starting preset required; no production approval.',
      ],
    ),
    for (final id in [
      'preset.list',
      'preset.read',
      'preset.select',
      'preset.name',
      'preset.save',
      'preset.transfer',
      'preset.verify',
      'preset.restore',
      'algorithm.write',
      'parameter.write',
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
