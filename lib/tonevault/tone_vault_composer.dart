/// Deterministic inheritance: Genre template -> Style -> Artist -> Era -> Album
/// -> Song -> Variant. A child overrides ONLY what it states explicitly:
/// UNSPECIFIED and INHERIT change nothing, OFF deactivates, DEFINED sets.
/// Per hierarchy level the entry's base is applied first, then that level's
/// variant (if the requested variant exists there), so a more specific level
/// always beats a more generic one.
library;

import '../models/tone_target.dart' show ToneDimension;
import 'tone_vault_model.dart';

/// The result of resolving one entry (and optionally one variant).
class ResolvedTone {
  ResolvedTone({
    required this.entryId,
    required this.variant,
    required this.chain,
    required this.dimensions,
    required this.explicitOff,
    required this.character,
    required this.kinds,
    required this.ampFamilies,
    required this.cabinet,
    required this.speaker,
    required this.microphone,
    required this.namTags,
    required this.provenance,
    required this.variantLevels,
  });

  final String entryId;
  final ToneVariantKind? variant;

  /// Entry ids from the most generic ancestor to the entry itself.
  final List<String> chain;
  final Map<ToneDimension, int> dimensions;

  /// Dimensions that were EXPLICITLY switched off (value 0).
  final Set<ToneDimension> explicitOff;
  final Map<CharacterAxis, int> character;

  /// A null value means the kind hint is explicitly OFF.
  final Map<ToneKindSlot, String?> kinds;
  final List<String>? ampFamilies;
  final String? cabinet, speaker, microphone;
  final List<String>? namTags;

  /// field key ("dimension:gain", "kind:delay", ...) -> id of the entry that set the final value.
  final Map<String, String> provenance;

  /// Entry ids whose [variant] layer contributed.
  final List<String> variantLevels;

  bool get variantMatched => variant == null || variantLevels.isNotEmpty;
}

class ToneVaultGraph {
  ToneVaultGraph(Iterable<ToneVaultEntry> entries) : byId = {for (final e in entries) e.id: e};

  final Map<String, ToneVaultEntry> byId;

  /// Ancestors of [id], most generic first, without [id]. Parents are visited in
  /// their listed order, each after its own ancestors; the first occurrence wins.
  /// Throws [StateError] on a missing parent or a cycle (the validator reports both first).
  List<String> ancestors(String id) {
    final out = <String>[];
    final visiting = <String>{};
    void visit(String x) {
      final e = byId[x] ?? (throw StateError('Fehlender Parent $x'));
      if (!visiting.add(x)) throw StateError('Vererbungszyklus bei $x');
      for (final p in e.parents) {
        visit(p);
      }
      visiting.remove(x);
      if (x != id && !out.contains(x)) out.add(x);
    }

    visit(id);
    return out;
  }
}

class ToneComposer {
  ToneComposer(this.graph);
  final ToneVaultGraph graph;

  /// [includeSelf] = false resolves only what the entry INHERITS (used to find redundant overrides).
  ResolvedTone resolve(String entryId, {ToneVariantKind? variant, bool includeSelf = true}) {
    final chain = [...graph.ancestors(entryId), if (includeSelf) entryId];
    final dims = <ToneDimension, int>{};
    final off = <ToneDimension>{};
    final axes = <CharacterAxis, int>{};
    final kinds = <ToneKindSlot, String?>{};
    List<String>? amps, nam;
    String? cab, spk, mic;
    final provenance = <String, String>{};
    final variantLevels = <String>[];

    void apply(ToneSpec spec, String by) {
      spec.dimensions.forEach((d, f) {
        if (f.mode == FieldMode.defined) {
          dims[d] = f.value!;
          off.remove(d);
          provenance['dimension:${d.name}'] = by;
        } else if (f.mode == FieldMode.off) {
          dims[d] = 0;
          off.add(d);
          provenance['dimension:${d.name}'] = by;
        }
      });
      spec.character.forEach((a, f) {
        if (f.mode == FieldMode.defined) {
          axes[a] = f.value!;
          provenance['character:${a.name}'] = by;
        } else if (f.mode == FieldMode.off) {
          axes.remove(a);
          provenance['character:${a.name}'] = by;
        }
      });
      spec.kinds.forEach((s, f) {
        if (f.mode == FieldMode.defined) {
          kinds[s] = f.value;
          provenance['kind:${s.name}'] = by;
        } else if (f.mode == FieldMode.off) {
          kinds[s] = null;
          provenance['kind:${s.name}'] = by;
        }
      });
      void text(ToneField<String> f, String key, void Function(String?) set) {
        if (f.mode == FieldMode.defined) {
          set(f.value);
          provenance[key] = by;
        } else if (f.mode == FieldMode.off) {
          set(null);
          provenance[key] = by;
        }
      }

      text(spec.cabinet, 'cabinet', (v) => cab = v);
      text(spec.speaker, 'speaker', (v) => spk = v);
      text(spec.microphone, 'microphone', (v) => mic = v);
      if (spec.ampFamilies.mode == FieldMode.defined) {
        amps = spec.ampFamilies.value;
        provenance['ampFamilies'] = by;
      }
      if (spec.namTags.mode == FieldMode.defined) {
        nam = spec.namTags.value;
        provenance['namTags'] = by;
      }
    }

    for (final id in chain) {
      final entry = graph.byId[id]!;
      apply(entry.tone, id);
      final v = variant == null ? null : entry.variant(variant);
      if (v != null) {
        apply(v.tone, id);
        variantLevels.add(id);
      }
    }
    return ResolvedTone(
      entryId: entryId,
      variant: variant,
      chain: List.unmodifiable(chain),
      dimensions: Map.unmodifiable(dims),
      explicitOff: Set.unmodifiable(off),
      character: Map.unmodifiable(axes),
      kinds: Map.unmodifiable(kinds),
      ampFamilies: amps,
      cabinet: cab,
      speaker: spk,
      microphone: mic,
      namTags: nam,
      provenance: Map.unmodifiable(provenance),
      variantLevels: List.unmodifiable(variantLevels),
    );
  }
}
