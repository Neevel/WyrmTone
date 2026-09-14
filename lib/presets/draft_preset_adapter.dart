import '../models/recommendation.dart';
import '../nam/local_nam_capture.dart';
import 'canonical_preset.dart';
import 'device_catalog.dart';
import 'protocol_evidence.dart';

class DraftPresetAdapter {
  const DraftPresetAdapter(this.catalog);
  final DevicePresetCatalog catalog;
  CanonicalPreset convert(
    PresetDraft draft, {
    required DateTime createdAt,
    DateTime? modifiedAt,
    List<LocalNamCapture> nams = const [],
  }) {
    PresetAssetReference? nam;
    if (draft.selectedNamId != null) {
      final matches = nams
          .where((n) => n.localId == draft.selectedNamId)
          .toList();
      if (matches.length == 1) {
        final item = matches.single;
        nam = PresetAssetReference(
          fileName: item.captureName.endsWith('.nam')
              ? item.captureName
              : '${item.captureName}.nam',
          format: 'NAM',
          sha256: item.sha256,
          creator: item.creatorName,
          license: item.license,
          locallyAvailable: true,
          architecture: item.architecture.name,
          cabinetContent: item.cabinetContent.name,
        );
      }
    }
    final blocks = <CanonicalPresetBlock>[];
    for (var order = 0; order < draft.blocks.length; order++) {
      final block = draft.blocks[order];
      final type = switch (block.slot) {
        'Gate' => PresetBlockType.gate,
        'Boost' => PresetBlockType.drive,
        'AMP' =>
          draft.selectedNamId == null
              ? PresetBlockType.amp
              : PresetBlockType.nam,
        'CAB' => PresetBlockType.cab,
        'EQ' => PresetBlockType.eq,
        'DLY' => PresetBlockType.delay,
        'RVB' => PresetBlockType.reverb,
        _ => throw FormatException('Unsupported draft block: ${block.slot}'),
      };
      final algorithm = draft.device.name == 'matriboxOne'
          ? catalog.find(block.model)
          : null;
      blocks.add(
        CanonicalPresetBlock(
          id: block.slot.toLowerCase(),
          type: type,
          enabled: block.enabled,
          order: order,
          model: block.model,
          algorithmCode: algorithm?.code,
          source: block.note,
          evidence: algorithm == null
              ? EvidenceLevel.unknown
              : EvidenceLevel.observed,
          compatibility: algorithm == null
              ? 'manualOrUnclear'
              : 'localEditorReference',
          warnings: [
            if (algorithm == null) 'Keine eindeutige Gerätezuordnung.',
          ],
          parameters: [
            for (final entry in block.parameters.entries)
              PresetParameter(
                id: entry.key.toLowerCase().replaceAll(
                  RegExp('[^a-z0-9]+'),
                  '-',
                ),
                name: entry.key,
                value: entry.value,
                deviceIndex: algorithm?.parameter(entry.key)?.index,
                minimum: algorithm?.parameter(entry.key)?.minimum,
                maximum: algorithm?.parameter(entry.key)?.maximum,
                step: algorithm?.parameter(entry.key)?.step,
                source: block.provenance[entry.key] ?? block.note,
                evidence:
                    algorithm == null || algorithm.parameter(entry.key) == null
                    ? EvidenceLevel.unknown
                    : catalog.indexEvidence(
                        algorithm,
                        algorithm.parameter(entry.key)!,
                      ),
              ),
          ],
        ),
      );
    }
    return CanonicalPreset(
      id: 'draft-${draft.profile.id}-${draft.guitar.id}-${draft.role.name}',
      name: '${draft.profile.song} · ${draft.role.name}',
      artist: draft.profile.artist,
      song: draft.profile.song,
      genre: draft.profile.style,
      role: draft.role.name,
      tuning: draft.tuning.name,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? createdAt,
      origin: draft.profile.profileKind.name == 'genre'
          ? PresetOrigin.genreFallback
          : PresetOrigin.exactProfile,
      targetDevice: draft.device.name,
      guitarId: draft.guitar.id,
      guitarName: draft.guitar.name,
      blocks: blocks,
      nam: nam,
      warnings: draft.warnings,
      notes: [...draft.reasons, ...draft.searchRequirements],
    );
  }
}
