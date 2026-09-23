/// The ToneVault facade: packs -> validation -> graph/composer -> index ->
/// resolver, plus loading from the app assets (fully offline).
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'tone_definition.dart';
import 'tone_nlu.dart';
import 'tone_nlu_lexicon.dart';
import 'tone_vault_composer.dart';
import 'tone_vault_index.dart';
import '../models/tone_target.dart' show ToneDimension, ToneUserAdjustments;
import 'tone_vault_model.dart';
import 'tone_vault_query.dart';
import 'tone_vault_search.dart';
import 'tone_vault_taxonomy.dart';
import 'tone_vault_validator.dart';

class ToneVaultLoadException implements Exception {
  const ToneVaultLoadException(this.issues);
  final List<ToneVaultIssue> issues;
  @override
  String toString() => 'ToneVault-Import abgelehnt:\n${issues.where((i) => i.isError).join('\n')}';
}

class ToneVault {
  ToneVault._(this.packs, this.taxonomy, this.vocabulary, this.index, this.graph, this.warnings)
    : composer = ToneComposer(graph),
      resolver = ToneVaultResolver(index);

  final List<ToneVaultPack> packs;
  final ToneTaxonomy taxonomy;
  final ToneVocabulary vocabulary;
  final ToneVaultIndex index;
  final ToneVaultGraph graph;
  final ToneComposer composer;
  final ToneVaultResolver resolver;

  /// Non-fatal validation findings of the import.
  final List<ToneVaultIssue> warnings;

  List<ToneVaultEntry> get entries => index.entries;
  ToneVaultEntry? entry(String id) => graph.byId[id];

  /// Validates every pack TOGETHER (ids, parents and aliases are global) and builds
  /// the index. Deterministic: the result depends only on the pack contents and
  /// their order. Any error rejects the whole import.
  static ToneVault build({
    required List<ToneVaultPack> packs,
    required ToneTaxonomy taxonomy,
    required ToneVocabulary vocabulary,
    ToneNluLexicon? lexicon,
    List<ToneVaultIssue> parseIssues = const [],
  }) {
    final all = [for (final p in packs) ...p.entries];
    final issues = [...parseIssues, ...ToneVaultValidator.validate(all, taxonomy)];
    if (issues.any((i) => i.isError)) throw ToneVaultLoadException(issues);
    return ToneVault._(
      List.unmodifiable(packs),
      taxonomy,
      vocabulary,
      ToneVaultIndex(all, taxonomy, vocabulary, lexicon: lexicon),
      ToneVaultGraph(all),
      List.unmodifiable(issues),
    );
  }

  /// From raw file contents (assets, tests, future downloads).
  static ToneVault fromTexts({
    required String taxonomy,
    required String vocabulary,
    required List<String> packs,
    String? nlu,
  }) {
    final parsed = [for (final p in packs) ToneVaultPackParser.parse(p)];
    final issues = [for (final p in parsed) ...p.issues];
    final good = [for (final p in parsed) if (p.pack != null) p.pack!];
    if (parsed.any((p) => p.pack == null)) throw ToneVaultLoadException(issues);
    return build(
      packs: good,
      taxonomy: ToneTaxonomy.parse(taxonomy),
      vocabulary: ToneVocabulary.parse(vocabulary),
      lexicon: nlu == null ? null : ToneNluLexicon.parse(nlu),
      parseIssues: issues,
    );
  }

  /// The bundled assets (assets/tonevault/manifest.json lists the packs). Cached.
  static Future<ToneVault> loadAssets() => _cached ??= _load();
  static Future<ToneVault>? _cached;
  static Future<ToneVault> _load() async {
    final manifest = JsonManifest.parse(await rootBundle.loadString('assets/tonevault/manifest.json'));
    return fromTexts(
      taxonomy: await rootBundle.loadString('assets/tonevault/taxonomy.json'),
      vocabulary: await rootBundle.loadString('assets/tonevault/vocabulary.json'),
      packs: [for (final path in manifest.packs) await rootBundle.loadString('assets/tonevault/$path')],
      nlu: manifest.nlu == null ? null : await rootBundle.loadString('assets/tonevault/${manifest.nlu}'),
    );
  }

  /// Resolves one entry (and variant) through the inheritance chain and applies modifiers.
  ToneDefinition definition(String entryId, {ToneVariantKind? variant, List<ToneModifier> modifiers = const []}) {
    final e = entry(entryId) ?? (throw ArgumentError('Unbekannter Eintrag $entryId'));
    final resolved = composer.resolve(entryId, variant: variant);
    final applied = applyToneModifiers(resolved.dimensions, modifiers);
    return ToneDefinition(
      entry: e,
      resolved: resolved,
      variant: variant,
      dimensions: applied.dimensions,
      appliedModifiers: [for (final m in modifiers) m.wire],
      skippedModifierDimensions: applied.skipped,
      chainTitles: [for (final id in resolved.chain) graph.byId[id]!.title],
    );
  }

  /// Central perceptual level given to an effect the user asks for when the tone
  /// leaves that dimension at 0/unspecified (no device value: a canonical starting point).
  static const _effectDefaultLevel = {
    ToneDimension.reverb: 30,
    ToneDimension.delay: 30,
    ToneDimension.modulation: 35,
    ToneDimension.compression: 35,
    ToneDimension.gateStrength: 50,
  };

  /// Like [definition], driven by a fully parsed request: intensity-scaled modifiers
  /// (user wishes win over the vault's defaults, bounded), then explicit effect wishes
  /// ("without reverb" = OFF, "with chorus" = modulation present). Tuning and guitar
  /// corrections still happen afterwards in the existing recipe pipeline.
  ToneDefinition definitionFor(String entryId, {ToneVariantKind? variant, required ToneQuery query}) {
    final e = entry(entryId) ?? (throw ArgumentError('Unbekannter Eintrag $entryId'));
    final v = variant ?? query.role;
    final resolved = composer.resolve(entryId, variant: v);
    final intents = query.modifierIntents.isNotEmpty
        ? query.modifierIntents
        : [for (final m in query.modifiers) ToneModifierIntent(m, ToneIntensity.normal)];
    final base = resolved.dimensions;
    final kinds = <ToneKindSlot, String?>{};
    final absolute = <ToneDimension, int>{};
    final done = <ToneEffectIntent>[];
    var driveTaken = false;
    void level(ToneDimension d, bool off) {
      if (off) {
        absolute[d] = 0;
      } else if ((base[d] ?? 0) == 0) {
        absolute[d] = _effectDefaultLevel[d]!;
      }
    }

    for (final fx in query.effects) {
      final off = fx.off;
      switch (fx.kind) {
        case ToneEffectKind.boost || ToneEffectKind.overdrive || ToneEffectKind.distortion || ToneEffectKind.fuzz:
          kinds[ToneKindSlot.drive] = off ? null : fx.kind.name;
          driveTaken = true;
        case ToneEffectKind.wah || ToneEffectKind.octave:
          if (driveTaken) continue;
          kinds[ToneKindSlot.drive] = off ? null : fx.kind.name;
        case ToneEffectKind.compressor:
          level(ToneDimension.compression, off);
        case ToneEffectKind.gate:
          level(ToneDimension.gateStrength, off);
        case ToneEffectKind.chorus || ToneEffectKind.flanger || ToneEffectKind.phaser || ToneEffectKind.tremolo:
          kinds[ToneKindSlot.modulation] = off ? null : fx.kind.name;
          level(ToneDimension.modulation, off);
        case ToneEffectKind.vibrato:
          kinds[ToneKindSlot.modulation] = off ? null : 'other';
          level(ToneDimension.modulation, off);
        case ToneEffectKind.delay:
          if (off) kinds[ToneKindSlot.delay] = null;
          level(ToneDimension.delay, off);
        case ToneEffectKind.reverb:
          if (off) kinds[ToneKindSlot.reverb] = null;
          level(ToneDimension.reverb, off);
        case ToneEffectKind.eq:
          continue;
      }
      done.add(fx);
    }
    // relative wishes only touch dimensions the tone (or an explicit effect wish) defines
    final allShifts = toneModifierShifts(intents);
    final shifts = {for (final s in allShifts.entries) if (base.containsKey(s.key) || absolute.containsKey(s.key)) s.key: s.value};
    final skipped = {for (final d in allShifts.keys) if (!shifts.containsKey(d)) d};
    final adjustments = ToneUserAdjustments(shifts: shifts, absolute: absolute);
    final dims = adjustments.apply(base);
    return ToneDefinition(
      entry: e,
      resolved: resolved,
      variant: v,
      dimensions: Map.unmodifiable(dims),
      baseDimensions: base,
      adjustments: adjustments,
      appliedModifiers: [for (final i in intents) '${i.modifier.wire}/${i.intensity.wire}'],
      skippedModifierDimensions: skipped,
      chainTitles: [for (final id in resolved.chain) graph.byId[id]!.title],
      kindOverrides: Map.unmodifiable(kinds),
      effects: List.unmodifiable(query.effects),
      appliedEffects: List.unmodifiable(done),
      requestedTuning: query.tuning,
    );
  }

  ToneVaultResolution resolve(String text) => resolver.resolve(text);

  /// The offline natural-language front end over this vault (see tone_nlu.dart).
  late final ToneNlu nlu = ToneNlu(this);
}

/// The pack list of the bundle (assets/tonevault/manifest.json).
class JsonManifest {
  const JsonManifest(this.packs, {this.nlu});
  final List<String> packs;

  /// Optional Mini-NLU lexicon file (relative to assets/tonevault/).
  final String? nlu;
  static JsonManifest parse(String text) {
    final reader = JsonObjectReader(jsonDecode(text), 'manifest');
    final packs = reader.strings('packs');
    final nlu = reader.optString('nlu');
    reader.done();
    return JsonManifest(List.unmodifiable(packs), nlu: nlu);
  }
}
