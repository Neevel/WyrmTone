import 'canonical_preset.dart';
import 'protocol_evidence.dart';

enum PresetChangeType {
  name,
  enabled,
  algorithm,
  parameter,
  blockAdded,
  blockRemoved,
  ir,
  nam,
  metadata,
  unchanged,
}

class PresetChange {
  const PresetChange(
    this.type,
    this.path,
    this.before,
    this.after, {
    this.unit,
    this.evidence = EvidenceLevel.unknown,
  });
  final PresetChangeType type;
  final String path;
  final Object? before, after;
  final String? unit;
  final EvidenceLevel evidence;
  bool get transferable => false;
  String get warning =>
      'Protokollseitig nicht für allgemeine Übertragung bestätigt.';
  Map<String, Object?> toJson() => {
    'type': type.name,
    'path': path,
    'before': before,
    'after': after,
    'unit': unit,
    'evidenceLevel': evidence.name,
    'transferable': false,
    'warning': warning,
  };
}

class PresetDiffEngine {
  const PresetDiffEngine();
  List<PresetChange> compare(CanonicalPreset before, CanonicalPreset after) {
    final changes = <PresetChange>[];
    void add(
      PresetChangeType type,
      String path,
      Object? old,
      Object? value, {
      String? unit,
      EvidenceLevel evidence = EvidenceLevel.unknown,
    }) {
      if (canonicalJson(old) != canonicalJson(value)) {
        changes.add(
          PresetChange(type, path, old, value, unit: unit, evidence: evidence),
        );
      }
    }

    add(PresetChangeType.name, 'name', before.name, after.name);
    final oldBlocks = {for (final block in before.blocks) block.id: block};
    final newBlocks = {for (final block in after.blocks) block.id: block};
    final ids = {...oldBlocks.keys, ...newBlocks.keys}.toList()..sort();
    for (final id in ids) {
      final old = oldBlocks[id], next = newBlocks[id];
      if (old == null || next == null) {
        changes.add(
          PresetChange(
            old == null
                ? PresetChangeType.blockAdded
                : PresetChangeType.blockRemoved,
            'blocks/$id',
            old?.toJson(),
            next?.toJson(),
          ),
        );
        continue;
      }
      add(
        PresetChangeType.enabled,
        'blocks/$id/enabled',
        old.enabled,
        next.enabled,
      );
      add(
        PresetChangeType.algorithm,
        'blocks/$id/model',
        {'name': old.model, 'code': old.algorithmCode},
        {'name': next.model, 'code': next.algorithmCode},
        evidence: next.evidence,
      );
      final oldParams = {for (final p in old.parameters) p.id: p};
      final newParams = {for (final p in next.parameters) p.id: p};
      final parameters = {...oldParams.keys, ...newParams.keys}.toList()
        ..sort();
      for (final parameter in parameters) {
        final a = oldParams[parameter], b = newParams[parameter];
        add(
          PresetChangeType.parameter,
          'blocks/$id/parameters/$parameter',
          a?.value,
          b?.value,
          unit: b?.unit ?? a?.unit,
          evidence: b?.evidence ?? EvidenceLevel.unknown,
        );
      }
      add(PresetChangeType.metadata, 'blocks/$id/order', old.order, next.order);
    }
    add(PresetChangeType.ir, 'ir', before.ir?.toJson(), after.ir?.toJson());
    add(PresetChangeType.nam, 'nam', before.nam?.toJson(), after.nam?.toJson());
    final oldMeta = before.toJson()
      ..remove('blocks')
      ..remove('name')
      ..remove('ir')
      ..remove('nam')
      ..remove('modifiedAt');
    final newMeta = after.toJson()
      ..remove('blocks')
      ..remove('name')
      ..remove('ir')
      ..remove('nam')
      ..remove('modifiedAt');
    add(PresetChangeType.metadata, 'metadata', oldMeta, newMeta);
    changes.sort((a, b) => a.path.compareTo(b.path));
    if (changes.isEmpty) {
      changes.add(
        const PresetChange(PresetChangeType.unchanged, 'preset', null, null),
      );
    }
    return List.unmodifiable(changes);
  }
}
