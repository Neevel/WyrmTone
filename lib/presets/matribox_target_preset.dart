/// The Matribox state WyrmTone WANTS: per chain slot an optional enabled
/// state, an optional model and optional semantic parameters, each with the
/// origin of the decision. A field that is [TargetValue.notSpecified] means
/// the recommendation gave no justified value; it is never filled with a
/// default and the transfer leaves the device value UNCHANGED.
///
/// Wire indices and codes do not appear here; the model is a catalog entry
/// and parameters are semantic names.
library;

import 'matribox_chain_slot.dart';
import 'matribox_model_library.dart';
import 'matribox_transfer_catalog.dart';
import 'tone_intent.dart';

class TargetValue<T> {
  const TargetValue._(this.value, this.origin, this.reason);

  factory TargetValue(T value, ToneOrigin origin, String reason) =>
      TargetValue._(value, origin, reason);

  /// No justified value: the device value stays UNCHANGED.
  const TargetValue.notSpecified(this.reason)
    : value = null,
      origin = ToneOrigin.unchanged;

  final T? value;
  final ToneOrigin origin;
  final String reason;

  bool get specified => value != null;

  Map<String, Object?> toJson() => {
    'value': value,
    'origin': origin.name,
    'reason': reason,
  };

  static TargetValue<T> fromJson<T>(Object? json, T? Function(Object?) read) {
    if (json is! Map) return const TargetValue.notSpecified('Kein Wert gespeichert.');
    final value = read(json['value']);
    final origin = ToneOrigin.values.where((o) => o.name == json['origin']).firstOrNull ?? ToneOrigin.unchanged;
    final reason = '${json['reason']}';
    return value == null ? TargetValue.notSpecified(reason) : TargetValue(value, origin, reason);
  }
}

enum ApproximationQuality { direct, goodApproximation, limitedApproximation, unsupported }

/// Why a block looks the way it does on the device: what was requested, what
/// was selected and why, which parameters were mapped and what the device
/// could not represent.
class BlockTranslationReport {
  const BlockTranslationReport({
    required this.slot,
    required this.requested,
    required this.quality,
    this.selectedModel,
    this.why = const [],
    this.mapped = const [],
    this.notRepresented = const [],
    this.candidates = const [],
  });

  final MatriboxChainSlot slot;
  final String requested;
  final ApproximationQuality quality;
  final String? selectedModel;
  final List<String> why, mapped, notRepresented;

  /// Ranked runner-ups (best first, including the selection).
  final List<String> candidates;
}

class MatriboxTargetBlock {
  MatriboxTargetBlock({
    required this.slot,
    this.enabled = const TargetValue.notSpecified('Keine Empfehlung.'),
    this.model = const TargetValue.notSpecified('Keine Empfehlung.'),
    Map<String, TargetValue<double>> parameters = const {},
    this.userActionRequired,
    this.state = RecipeBlockState.defined,
    this.report,
    this.incompleteReason,
  }) : parameters = Map.unmodifiable(parameters);

  final MatriboxChainSlot slot;
  final TargetValue<bool> enabled;
  final TargetValue<MatriboxTransferModel> model;

  /// Semantic parameter name -> target (including explicit NOT_SPECIFIED
  /// entries, so the preview can say WHY a knob is untouched).
  final Map<String, TargetValue<double>> parameters;

  /// Set when the recommendation needs something the app cannot decide
  /// (e.g. a custom IR whose device slot is unknown).
  final String? userActionRequired;

  /// The recipe's state for this block.
  final RecipeBlockState state;
  final BlockTranslationReport? report;
  final String? incompleteReason;

  /// Central semantics: a block that should be ON needs a model, otherwise
  /// the target is INCOMPLETE -- the device's current model is never reused.
  /// OFF needs no model; UNCHANGED (explicit) leaves the block alone.
  RecipeBlockState get effectiveState {
    if (state != RecipeBlockState.defined) return state;
    if (enabled.value == false) return RecipeBlockState.off;
    if (enabled.value == true && !model.specified) return RecipeBlockState.incomplete;
    return RecipeBlockState.defined;
  }

  bool get hasAnyTarget =>
      enabled.specified ||
      model.specified ||
      parameters.values.any((p) => p.specified);

  Map<String, Object?> toJson() => {
    'slot': slot.label,
    'enabled': enabled.toJson(),
    'model': {
      'value': model.value?.name,
      'origin': model.origin.name,
      'reason': model.reason,
    },
    'parameters': {
      for (final e in parameters.entries) e.key: e.value.toJson(),
    },
    'userActionRequired': userActionRequired,
    'state': state.name,
    'incompleteReason': incompleteReason,
  };

  static MatriboxTargetBlock fromJson(Map<Object?, Object?> json, {MatriboxModelLibrary? library}) {
    final slot = MatriboxChainSlot.values.firstWhere((s) => s.label == json['slot']);
    final parameters = json['parameters'];
    return MatriboxTargetBlock(
      slot: slot,
      enabled: TargetValue.fromJson<bool>(json['enabled'], (v) => v is bool ? v : null),
      model: TargetValue.fromJson<MatriboxTransferModel>(
        json['model'],
        // The static catalog only knows the hand-curated, evidence-confirmed
        // models; catalog-only models (e.g. Angels' "Boost") only resolve
        // through the full vendor-derived library, when one is available.
        (v) => v is! String
            ? null
            : (library?.byName(slot, v) ?? MatriboxTransferCatalog.byName(v)),
      ),
      parameters: {
        if (parameters is Map)
          for (final e in parameters.entries)
            '${e.key}': TargetValue.fromJson<double>(e.value, (v) => v is num ? v.toDouble() : null),
      },
      userActionRequired: json['userActionRequired'] as String?,
      state: RecipeBlockState.values.where((v) => v.name == json['state']).firstOrNull ?? RecipeBlockState.defined,
      incompleteReason: json['incompleteReason'] as String?,
    );
  }
}

class MatriboxTargetPreset {
  MatriboxTargetPreset({
    required Map<MatriboxChainSlot, MatriboxTargetBlock> blocks,
    this.name = const TargetValue.notSpecified('Kein Name empfohlen.'),
    this.bpm = const TargetValue.notSpecified('Kein BPM empfohlen.'),
    this.volume = const TargetValue.notSpecified('Keine Preset-Lautstärke empfohlen.'),
    this.provenance = const [],
  }) : blocks = Map.unmodifiable({
         for (final slot in MatriboxChainSlot.values)
           slot: blocks[slot] ?? MatriboxTargetBlock(slot: slot, state: RecipeBlockState.unchanged),
       });

  final Map<MatriboxChainSlot, MatriboxTargetBlock> blocks;

  /// Offline only: name/BPM/VOL are never part of the hardware transfer.
  final TargetValue<String> name;
  final TargetValue<double> bpm;
  final TargetValue<double> volume;

  /// Free-text notes on what the recommendation could not provide.
  final List<String> provenance;

  MatriboxTargetBlock operator [](MatriboxChainSlot slot) => blocks[slot]!;

  Map<String, Object?> toJson() => {
    'name': name.toJson(),
    'bpm': bpm.toJson(),
    'volume': volume.toJson(),
    'blocks': [for (final slot in MatriboxChainSlot.values) blocks[slot]!.toJson()],
    'provenance': provenance,
  };

  static MatriboxTargetPreset fromJson(Map<Object?, Object?> json, {MatriboxModelLibrary? library}) {
    final blocks = json['blocks'];
    return MatriboxTargetPreset(
      blocks: {
        if (blocks is List)
          for (final b in blocks)
            if (b is Map)
              MatriboxChainSlot.values.firstWhere((s) => s.label == b['slot']):
                  MatriboxTargetBlock.fromJson(b, library: library),
      },
      name: TargetValue.fromJson<String>(json['name'], (v) => v is String ? v : null),
      bpm: TargetValue.fromJson<double>(json['bpm'], (v) => v is num ? v.toDouble() : null),
      volume: TargetValue.fromJson<double>(json['volume'], (v) => v is num ? v.toDouble() : null),
      provenance: [for (final p in (json['provenance'] as List? ?? const [])) '$p'],
    );
  }
}
