/// Matribox device translator (V2): [CanonicalToneRecipe] + model library ->
/// [MatriboxTargetPreset].
///
/// For every DEFINED block a concrete model is chosen by explicit, offline
/// scoring/tag rules (matribox_model_matcher.dart); semantic parameters go
/// through explicit mapping rules: semantic value -> normalized to the
/// catalog range/type -> catalog parameter (the wire index stays inside the
/// chain catalog). An intent without an explicit rule is NOT translated but
/// listed as "not represented": abstract reverb amount is not Mix, gate
/// strength is not THRE, tightness is not Bass.
///
/// The current device state never enters this file. A block that should be ON
/// but cannot be given a model becomes INCOMPLETE; OFF needs no model;
/// UNCHANGED is only taken over when the recipe says so explicitly.
library;

import 'canonical_tone_recipe.dart';
import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';
import 'matribox_model_library.dart';
import 'matribox_model_matcher.dart';
import 'matribox_target_preset.dart';
import 'matribox_transfer_catalog.dart';
import 'tone_intent.dart';

const _roleSlot = <ToneBlockRole, MatriboxChainSlot>{
  ToneBlockRole.fx1: MatriboxChainSlot.fx1,
  ToneBlockRole.fx2: MatriboxChainSlot.fx2,
  ToneBlockRole.gate: MatriboxChainSlot.nr,
  ToneBlockRole.amp: MatriboxChainSlot.amp,
  ToneBlockRole.cab: MatriboxChainSlot.cab,
  ToneBlockRole.eq: MatriboxChainSlot.eq,
  ToneBlockRole.modulation: MatriboxChainSlot.mod,
  ToneBlockRole.delay: MatriboxChainSlot.dly,
  ToneBlockRole.reverb: MatriboxChainSlot.rvb,
};

/// How a semantic value is normalized onto a catalog parameter.
enum MappingScale {
  /// perceptual 0..100 -> catalog min..max (rounded per parameter kind)
  linear,

  /// signed shaping -100..+100 -> catalog -max..+max
  signed,

  /// 0/1 switch
  flag,

  /// a millisecond target that is clamped to the catalog range
  milliseconds,

  /// HEURISTIC / DEVICE_APPROXIMATION: perceptual 0..100 -> a SAFE SUB-RANGE
  /// of the catalog range ([MappingRule.safeMin]..[MappingRule.safeMax]).
  /// Not a protocol fact: the parameter is writable, the musical choice of
  /// the sub-range is a deterministic product decision.
  safeRange,
}

class MappingRule {
  const MappingRule(
    this.catalogName,
    this.scale, {
    this.alternative,
    this.safeMin,
    this.safeMax,
    this.onlyModels,
  });
  final String catalogName;
  final MappingScale scale;

  /// Sub-range for [MappingScale.safeRange].
  final double? safeMin;
  final double? safeMax;

  /// Rule applies only to these catalog model names (null: every model).
  final Set<String>? onlyModels;

  /// True if the value is a musical product decision, not a protocol mapping.
  bool get heuristic => scale == MappingScale.safeRange;

  /// Second catalog spelling of the same control (`Time Sync` vs `Sync`).
  final String? alternative;
}

/// The explicit mapping rules. Anything not listed here is not translated.
const matriboxMappingRules = <ToneBlockRole, Map<String, MappingRule>>{
  ToneBlockRole.amp: {
    'gain': MappingRule('Gain', MappingScale.linear),
    'presence': MappingRule('PRES', MappingScale.linear),
    'bass': MappingRule('Bass', MappingScale.linear),
    'mids': MappingRule('Middle', MappingScale.linear),
    'treble': MappingRule('Treble', MappingScale.linear),
  },
  ToneBlockRole.fx1: {
    'intensity': MappingRule('Gain', MappingScale.linear),
    'tone': MappingRule('Tone', MappingScale.linear),
    'level': MappingRule('VOL', MappingScale.linear),
  },
  ToneBlockRole.fx2: {
    'intensity': MappingRule('Gain', MappingScale.linear),
    'tone': MappingRule('Tone', MappingScale.linear),
    'level': MappingRule('VOL', MappingScale.linear),
  },
  ToneBlockRole.eq: {
    'low': MappingRule('125Hz', MappingScale.signed),
    'lowMid': MappingRule('400Hz', MappingScale.signed),
    'mid': MappingRule('800Hz', MappingScale.signed),
    'upperMid': MappingRule('1.6kHz', MappingScale.signed),
    'high': MappingRule('4kHz', MappingScale.signed),
    'level': MappingRule('VOL', MappingScale.linear),
  },
  ToneBlockRole.modulation: {
    'depth': MappingRule('Depth', MappingScale.linear),
    'rate': MappingRule('Rate', MappingScale.linear),
  },
  ToneBlockRole.delay: {
    'mix': MappingRule('Mix', MappingScale.linear),
    'feedback': MappingRule('FdBk', MappingScale.linear),
    'time': MappingRule('Time', MappingScale.milliseconds),
    'sync': MappingRule('Time Sync', MappingScale.flag, alternative: 'Sync'),
    'trail': MappingRule('Trail', MappingScale.flag),
  },
  ToneBlockRole.gate: {
    // HEURISTIC: THRE 0..99, catalog default 20; the editor itself drove
    // Gate 2 THRE up to 59. Safe range = default .. 60. Direction (higher =
    // stronger gating) is the threshold convention, not a device fact.
    'strength': MappingRule(
      'THRE',
      MappingScale.safeRange,
      safeMin: 20,
      safeMax: 60,
      onlyModels: {'Gate 2'},
    ),
  },
  ToneBlockRole.reverb: {
    // HEURISTIC: an abstract reverb amount is NOT a Mix percentage. Amount
    // 0..100 spans only Mix 0..50 (a full-wet guitar reverb is never a
    // "100 % amount"). Decay/Pre Delay are not derivable from the amount.
    'amount': MappingRule(
      'Mix',
      MappingScale.safeRange,
      safeMin: 0,
      safeMax: 50,
    ),
    'mix': MappingRule('Mix', MappingScale.linear),
    'decay': MappingRule('Decay', MappingScale.linear),
    'predelay': MappingRule('Pre Delay', MappingScale.linear),
    'trail': MappingRule('Trail', MappingScale.flag),
  },
};

/// Intents that feed the model choice or are secondary shaping: not listing
/// them as "not represented" keeps the approximation quality meaningful.
const _consumedByMatching = {
  ToneBlockRole.amp: {'tightness'},
};

/// User choice of a specific device model per block; it sits above every
/// scoring rule.
class DeviceModelOverrides {
  const DeviceModelOverrides([this.names = const {}]);
  final Map<ToneBlockRole, String> names;
}

abstract final class MatriboxToneTranslator {
  static MatriboxTargetPreset translate({
    required CanonicalToneRecipe recipe,
    required MatriboxModelLibrary library,
    DeviceModelOverrides modelOverrides = const DeviceModelOverrides(),

    /// Apply HEURISTIC / DEVICE_APPROXIMATION rules (gate strength -> THRE,
    /// reverb amount -> Mix). OFF by default: the product pipeline must not
    /// grow operations that no evidence family releases yet.
    bool heuristics = false,
  }) {
    final blocks = <MatriboxChainSlot, MatriboxTargetBlock>{};
    String? ampName;
    // amp first: the cabinet choice pairs with it
    for (final role in [
      ToneBlockRole.amp,
      ...ToneBlockRole.values.where((r) => r != ToneBlockRole.amp),
    ]) {
      final slot = _roleSlot[role]!;
      final block = recipe[role];
      final translated = _block(
        role,
        slot,
        block,
        library,
        modelOverrides.names[role],
        ampName,
        heuristics,
      );
      blocks[slot] = translated;
      if (role == ToneBlockRole.amp && translated.model.specified) {
        ampName = translated.model.value!.name;
      }
    }
    return MatriboxTargetPreset(
      blocks: blocks,
      name: _deviceName(recipe),
      provenance: [
        for (final b in blocks.values)
          for (final gap in b.report?.notRepresented ?? const <String>[])
            '${b.slot.label}: $gap',
      ],
    );
  }

  static MatriboxTargetBlock _block(
    ToneBlockRole role,
    MatriboxChainSlot slot,
    RecipeBlock block,
    MatriboxModelLibrary library,
    String? modelOverride,
    String? ampName,
    bool heuristics,
  ) {
    switch (block.state) {
      case RecipeBlockState.off:
        return MatriboxTargetBlock(
          slot: slot,
          state: RecipeBlockState.off,
          enabled: TargetValue(false, block.stateOrigin, block.stateReason),
          report: BlockTranslationReport(
            slot: slot,
            requested: 'OFF',
            quality: ApproximationQuality.direct,
            why: [block.stateReason],
          ),
        );
      case RecipeBlockState.unchanged:
        return MatriboxTargetBlock(
          slot: slot,
          state: RecipeBlockState.unchanged,
          report: BlockTranslationReport(
            slot: slot,
            requested: 'UNCHANGED',
            quality: ApproximationQuality.direct,
            why: [
              'Ausdrücklich nicht Teil des Tone-Ziels: ${block.stateReason}',
            ],
          ),
        );
      case RecipeBlockState.incomplete:
        return _incomplete(
          slot,
          block,
          block.incompleteReason ?? block.stateReason,
        );
      case RecipeBlockState.defined:
        break;
    }

    // -- model ------------------------------------------------------------
    ModelMatch? match;
    MatriboxTransferModel? model;
    var byUser = false;
    final why = <String>[];
    if (modelOverride != null) {
      model = library.byName(slot, modelOverride);
      byUser = model != null;
      if (model == null) {
        return _incomplete(
          slot,
          block,
          'Override-Modell "$modelOverride" existiert für ${slot.label} nicht.',
        );
      }
      why.add('Nutzerwahl "$modelOverride".');
    } else {
      match = _match(role, block, library, ampName);
      model = match?.selected?.model;
      if (model == null) {
        return _incomplete(
          slot,
          block,
          'Kein passendes ${slot.label}-Modell für ${block.kind?.value.name ?? 'diese Art'} '
          '(nicht getaggt oder nicht im Katalog).',
        );
      }
      why.addAll(match!.selected!.reasons);
    }

    // -- parameters ---------------------------------------------------------
    final parameters = <String, TargetValue<double>>{};
    final mapped = <String>[];
    final gaps = <String>[];
    final rules = matriboxMappingRules[role] ?? const {};
    final consumed = _consumedByMatching[role] ?? const <String>{};
    var primaryGaps = 0;
    for (final entry in block.params.entries) {
      final rule = rules[entry.key];
      final applicable =
          rule != null &&
          (heuristics || !rule.heuristic) &&
          (rule.onlyModels?.contains(model.name) ?? true);
      final parameter = !applicable
          ? null
          : model.algorithm.parameters
                .where(
                  (p) =>
                      p.name == rule.catalogName || p.name == rule.alternative,
                )
                .firstOrNull;
      if (rule == null || parameter == null) {
        if (consumed.contains(entry.key)) {
          why.add(
            '${entry.key} ${entry.value.value.round()}/100 fließt in die Modellwahl ein.',
          );
        } else {
          primaryGaps++;
          gaps.add(
            '${entry.key} ${entry.value.value.round()}/100: '
            '${!applicable ? 'keine belegte Abbildungsregel' : '${model.name} hat keinen Parameter "${rule.catalogName}"'}.',
          );
        }
        continue;
      }
      if (rule.heuristic &&
          block.params.keys.any((k) {
            final other = rules[k];
            return k != entry.key &&
                other != null &&
                !other.heuristic &&
                other.catalogName == rule.catalogName;
          })) {
        primaryGaps++;
        gaps.add(
          '${entry.key} ${entry.value.value.round()}/100: durch den ausdrücklichen Gerätewert für '
          '${rule.catalogName} ersetzt (Heuristik weicht).',
        );
        continue;
      }
      final converted = _convert(
        parameter,
        entry.value.value,
        rule.scale,
        safeMin: rule.safeMin,
        safeMax: rule.safeMax,
      );
      if (converted == null) {
        primaryGaps++;
        gaps.add(
          '${entry.key}: Wert nicht auf ${parameter.name} (${parameter.kind.name}) abbildbar.',
        );
        continue;
      }
      parameters[matriboxSemanticName(parameter.name)] = TargetValue(
        converted,
        entry.value.origin,
        '${rule.heuristic ? 'HEURISTIC/DEVICE_APPROXIMATION: ' : ''}'
        '${entry.key} ${entry.value.value.round()} -> ${parameter.name} (${rule.scale.name}, '
        '${rule.heuristic ? '${_fmt(rule.safeMin!)}..${_fmt(rule.safeMax!)} von ' : ''}'
        '${parameter.minimum}..${parameter.maximum})',
      );
      mapped.add(
        '${entry.key} -> ${parameter.name} = ${_fmt(converted)}'
        '${rule.heuristic ? ' [HEURISTIC]' : ''}',
      );
    }
    var prefGaps = 0;
    for (final pref in block.prefs.entries) {
      // an empty preference says nothing (the sound library leaves speaker/mic unspecified): it is no intent to translate
      if (pref.value.value.isEmpty) continue;
      final used =
          (role == ToneBlockRole.amp && pref.key == 'ampFamilies') ||
          (role == ToneBlockRole.gate &&
              pref.key == 'character' &&
              model.algorithm.parameters.any((p) => p.name == 'ATK'));
      if (role == ToneBlockRole.gate && pref.key == 'character') {
        // ATK/Rel semantics have no confirmed rule: only the model flavour follows the character
        why.add(
          'Öffnungscharakter ${pref.value.value}: Modell mit einstellbarem Attack/Release gewählt.',
        );
        prefGaps++;
        gaps.add(
          'Öffnungscharakter ${pref.value.value}: ATK/Rel nicht gesetzt (keine belegte Regel).',
        );
        continue;
      }
      if (used) {
        why.add(
          '${pref.key} "${pref.value.value}" fließt in die Modellwahl ein.',
        );
        continue;
      }
      prefGaps++;
      gaps.add(
        '${pref.key} "${pref.value.value}": im Katalog nicht abbildbar '
        '(keine belegte Zuordnung auf ein Modell).',
      );
    }

    final quality = (primaryGaps + prefGaps) > 0
        ? ApproximationQuality.limitedApproximation
        : (byUser
              ? ApproximationQuality.direct
              : ApproximationQuality.goodApproximation);

    return MatriboxTargetBlock(
      slot: slot,
      state: RecipeBlockState.defined,
      enabled: TargetValue(true, block.stateOrigin, block.stateReason),
      model: TargetValue(
        model,
        byUser ? ToneOrigin.userOverride : ToneOrigin.deviceTranslation,
        why.join(' '),
      ),
      parameters: parameters,
      report: BlockTranslationReport(
        slot: slot,
        requested: _requested(block),
        quality: quality,
        selectedModel: model.name,
        why: why,
        mapped: mapped,
        notRepresented: gaps,
        candidates: [
          if (match != null)
            for (final c in match.ranked.take(4))
              '${c.model.name} (${c.score.toStringAsFixed(0)})',
        ],
      ),
    );
  }

  static MatriboxTargetBlock _incomplete(
    MatriboxChainSlot slot,
    RecipeBlock block,
    String reason,
  ) => MatriboxTargetBlock(
    slot: slot,
    state: RecipeBlockState.incomplete,
    incompleteReason: reason,
    enabled: TargetValue(true, block.stateOrigin, block.stateReason),
    report: BlockTranslationReport(
      slot: slot,
      requested: _requested(block),
      quality: ApproximationQuality.unsupported,
      why: [reason],
      notRepresented: [reason],
    ),
  );

  static ModelMatch? _match(
    ToneBlockRole role,
    RecipeBlock block,
    MatriboxModelLibrary library,
    String? ampName,
  ) {
    final kind = block.kind?.value;
    switch (role) {
      case ToneBlockRole.fx1:
      case ToneBlockRole.fx2:
        if (kind is! PreAmpKind ||
            kind == PreAmpKind.none ||
            kind == PreAmpKind.other) {
          return null;
        }
        return MatriboxModelMatcher.byTag(library, _roleSlot[role]!, kind.name);
      case ToneBlockRole.gate:
        final adjustable = block.prefs.containsKey('character');
        return MatriboxModelMatcher.byTag(
          library,
          MatriboxChainSlot.nr,
          adjustable ? 'adjustable' : 'simple',
        );
      case ToneBlockRole.amp:
        final gain = block.params['gain']?.value;
        if (gain == null) return null;
        return MatriboxModelMatcher.amp(
          library,
          gain: gain.round(),
          tightness: block.params['tightness']?.value.round(),
          mids: block.params['mids']?.value.round(),
          families: block.prefs['ampFamilies']?.value ?? '',
        );
      case ToneBlockRole.cab:
        final config = switch (kind) {
          CabConfig.c1x12 => '1x12',
          CabConfig.c2x12 => '2x12',
          CabConfig.c4x12 => '4x12',
          _ => null,
        };
        return config == null
            ? null
            : MatriboxModelMatcher.cab(
                library,
                config: config,
                ampName: ampName,
              );
      case ToneBlockRole.eq:
        return MatriboxModelMatcher.byTag(
          library,
          MatriboxChainSlot.eq,
          'guitar',
        );
      case ToneBlockRole.modulation:
        if (kind is! ModulationKind ||
            kind == ModulationKind.none ||
            kind == ModulationKind.other) {
          return null;
        }
        return MatriboxModelMatcher.byTag(
          library,
          MatriboxChainSlot.mod,
          kind.name,
        );
      case ToneBlockRole.delay:
        if (kind is! DelayKind ||
            kind == DelayKind.none ||
            kind == DelayKind.other) {
          return null;
        }
        final tag = kind == DelayKind.analogWarm ? 'analog' : kind.name;
        return MatriboxModelMatcher.byTag(library, MatriboxChainSlot.dly, tag);
      case ToneBlockRole.reverb:
        if (kind is! ReverbKind ||
            kind == ReverbKind.none ||
            kind == ReverbKind.other) {
          return null;
        }
        return MatriboxModelMatcher.byTag(
          library,
          MatriboxChainSlot.rvb,
          kind.name,
        );
    }
  }

  /// Normalizes [value] onto the catalog parameter; null if not representable.
  static double? _convert(
    MatriboxChainParameter p,
    double value,
    MappingScale scale, {
    double? safeMin,
    double? safeMax,
  }) {
    switch (scale) {
      case MappingScale.flag:
        return p.kind == MatriboxParameterKind.flag
            ? (value >= 0.5 ? 1 : 0)
            : null;
      case MappingScale.signed:
        if (p.kind != MatriboxParameterKind.signedNumber) return null;
        return (value.clamp(-100, 100) / 100 * p.maximum)
            .round()
            .toDouble()
            .clamp(p.minimum, p.maximum);
      case MappingScale.milliseconds:
        if (p.kind == MatriboxParameterKind.flag) return null;
        return value.round().toDouble().clamp(p.minimum, p.maximum);
      case MappingScale.safeRange:
        if (p.kind == MatriboxParameterKind.flag ||
            safeMin == null ||
            safeMax == null) {
          return null;
        }
        final safe = safeMin + value.clamp(0, 100) / 100 * (safeMax - safeMin);
        return safe.round().toDouble().clamp(p.minimum, p.maximum);
      case MappingScale.linear:
        if (p.kind == MatriboxParameterKind.flag) return null;
        final raw =
            p.minimum + value.clamp(0, 100) / 100 * (p.maximum - p.minimum);
        final rounded = p.kind == MatriboxParameterKind.decimal
            ? (raw * 10).round() / 10
            : raw.round().toDouble();
        return rounded.clamp(p.minimum, p.maximum);
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static String _requested(RecipeBlock block) {
    final kind = block.kind?.value.name;
    final params = block.params.entries
        .map((e) => '${e.key} ${e.value.value.round()}')
        .join(', ');
    return [?kind, if (params.isNotEmpty) '($params)'].join(' ');
  }

  /// Offline-only device name (11 ASCII characters). Never transferred.
  static TargetValue<String> _deviceName(CanonicalToneRecipe recipe) {
    final ascii = recipe.song.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim();
    if (ascii.isEmpty) {
      return const TargetValue.notSpecified('Songname nicht ASCII-fähig.');
    }
    final name = ascii.length > 11 ? ascii.substring(0, 11).trim() : ascii;
    return TargetValue(
      name,
      ToneOrigin.deviceTranslation,
      'Songname auf 11 ASCII-Zeichen gekürzt; nur Offline-Vorschau, kein Metadaten-Send.',
    );
  }
}
