/// The honest verdict of a device translation, BEFORE any device is touched:
/// what of the created sound reaches the Matribox, what is only approximated, what is not
/// translated and what the evidence gate would block.
///
/// - Three separate questions (never merged): technically addressable, productively sendable
///   (evidence) and semantically mapped (an explicit translator rule). A value is only ever produced
///   by the translator's rules; this file only READS the result and asks the evidence gate.
/// - The check is advisory. At transfer time the whole plan (fresh device read, backup, diff, evidence
///   gate) still decides, and the native side validates again.
/// - Compatibility: [MatriboxCompatibility.full] = every relevant intent is translated and sendable,
///   [MatriboxCompatibility.partial] = sensible to transfer, but some intents are approximated or
///   left out (listed), [MatriboxCompatibility.blocked] = a critical part is missing or a needed
///   operation is not released.
library;

import 'matribox_chain_slot.dart';
import 'matribox_evidence_v2.dart';
import 'matribox_hardware_evidence.dart';
import 'matribox_model_library.dart';
import 'matribox_target_preset.dart';
import 'matribox_tone_transfer_plan.dart';
import 'tone_intent.dart';

enum MatriboxCompatibility { full, partial, blocked }

/// One line of the result: which block, what, and why (user-facing German).
class TranslationLine {
  const TranslationLine(this.slot, this.text, {this.detail});
  final MatriboxChainSlot slot;
  final String text;

  /// Technical reason for the developer details (never needed in the normal flow).
  final String? detail;
  @override
  String toString() => '${slot.label}: $text';
}

/// How one block appears in the preview.
class BlockPreview {
  const BlockPreview({
    required this.slot,
    required this.state,
    required this.quality,
    this.model,
    this.parameters = const {},
    this.note,
  });
  final MatriboxChainSlot slot;

  /// defined (on), off, unchanged or incomplete.
  final RecipeBlockState state;
  final ApproximationQuality quality;
  final String? model;

  /// Semantic parameter name -> value text (no wire indices).
  final Map<String, String> parameters;
  final String? note;
}

class MatriboxTranslationResult {
  const MatriboxTranslationResult({
    required this.target,
    required this.blocks,
    required this.mappedIntents,
    required this.approximatedIntents,
    required this.unsupportedIntents,
    required this.blockedOperations,
    required this.unchangedIntents,
    required this.warnings,
    required this.overallCompatibility,
    required this.criticalReasons,
  });

  final MatriboxTargetPreset target;
  final List<BlockPreview> blocks;
  final List<TranslationLine> mappedIntents, approximatedIntents, unsupportedIntents, blockedOperations, unchangedIntents;
  final List<String> warnings;
  final MatriboxCompatibility overallCompatibility;

  /// Why the result is [MatriboxCompatibility.blocked] (empty otherwise).
  final List<String> criticalReasons;

  bool get transferable => overallCompatibility != MatriboxCompatibility.blocked;
  BlockPreview preview(MatriboxChainSlot slot) => blocks.firstWhere((b) => b.slot == slot);
}

abstract final class MatriboxTranslationAnalyzer {
  /// Blocks without which a sound is not meaningfully transferable.
  static const criticalSlots = criticalIncompleteSlots;

  static const _intentWords = <String, String>{
    'strength': 'Stärke',
    'opening': 'Öffnung',
    'amount': 'Menge',
    'gain': 'Gain',
    'presence': 'Präsenz',
    'bass': 'Bass',
    'mids': 'Mitten',
    'treble': 'Höhen',
    'speaker': 'Lautsprecher',
    'microphone': 'Mikrofon',
  };

  /// The translator's gap text as a sentence for the user (the original stays in the details).
  static String friendlyGap(MatriboxChainSlot slot, String gap) {
    final unmapped = RegExp(r'^(\w+) (\d+)/100: keine belegte Abbildungsregel').firstMatch(gap);
    if (unmapped != null) {
      final word = _intentWords[unmapped.group(1)] ?? unmapped.group(1)!;
      return '${slot.label}-$word (${unmapped.group(2)}/100) kann noch nicht sicher übertragen werden';
    }
    final noControl = RegExp(r'^(\w+) \d+/100: (.+) hat keinen Parameter').firstMatch(gap);
    if (noControl != null) {
      return '${noControl.group(2)} hat keinen Regler für ${_intentWords[noControl.group(1)] ?? noControl.group(1)}';
    }
    if (gap.startsWith('speaker') || gap.startsWith('microphone')) {
      return 'Lautsprecher/Mikrofon-Wunsch wird nicht übertragen (keine sichere Zuordnung)';
    }
    if (gap.contains('Öffnungscharakter')) return 'Gate-Öffnungscharakter wird nicht übertragen';
    return gap;
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static MatriboxTranslationResult analyze({
    required MatriboxTargetPreset target,
    required MatriboxModelLibrary library,
    required MatriboxHardwareLedger ledger,
  }) {
    final evidence = MatriboxEvidenceV2(library: library, samples: ActiveSamples.fromLedger(ledger, library));
    final blocks = <BlockPreview>[];
    final mapped = <TranslationLine>[], approximated = <TranslationLine>[], unsupported = <TranslationLine>[];
    final blocked = <TranslationLine>[], unchanged = <TranslationLine>[];
    final warnings = <String>[];
    final critical = <String>[];

    bool sendable(EvidenceDecision v2, HardwareEvidenceDecision legacy) {
      if (v2.level == EvidenceLevel.blocked) return false;
      return MatriboxToneTransferPlan.hardwareDecision(v2, legacy).confirmed;
    }

    for (final slot in MatriboxChainSlot.values) {
      final block = target[slot];
      final report = block.report;
      switch (block.effectiveState) {
        case RecipeBlockState.unchanged:
          unchanged.add(TranslationLine(slot, 'wird nicht verändert', detail: report?.why.join(' ')));
          blocks.add(BlockPreview(slot: slot, state: RecipeBlockState.unchanged, quality: ApproximationQuality.direct, note: 'Bleibt wie am Gerät.'));
        case RecipeBlockState.incomplete:
          final reason = block.incompleteReason ?? 'Kein passendes Modell.';
          unsupported.add(TranslationLine(slot, 'Kein passendes Modell gefunden, der Block wird nicht gesetzt', detail: reason));
          blocks.add(BlockPreview(slot: slot, state: RecipeBlockState.incomplete, quality: ApproximationQuality.unsupported, note: 'Nicht übersetzbar.'));
          if (criticalSlots.contains(slot)) critical.add('${slot.label}: kein passendes Modell.');
        case RecipeBlockState.off:
          if (!sendable(evidence.blockToggle(slot, false), ledger.toggle(slot, false))) {
            blocked.add(TranslationLine(slot, 'Ausschalten ist noch nicht freigegeben'));
          }
          mapped.add(TranslationLine(slot, 'wird ausgeschaltet'));
          blocks.add(BlockPreview(slot: slot, state: RecipeBlockState.off, quality: ApproximationQuality.direct));
        case RecipeBlockState.defined:
          final model = block.model.value;
          if (model == null) {
            unsupported.add(TranslationLine(slot, 'Kein Modell festgelegt'));
            blocks.add(BlockPreview(slot: slot, state: RecipeBlockState.incomplete, quality: ApproximationQuality.unsupported));
            if (criticalSlots.contains(slot)) critical.add('${slot.label}: kein Modell.');
            break;
          }
          // -- evidence for the operations this block would need (advisory; the plan decides)
          if (!model.selectable || !model.algorithm.slots.contains(slot)) {
            blocked.add(TranslationLine(slot, '${model.name} kann hier nicht ausgewählt werden'));
          } else {
            final v2 = evidence.modelSelect(slot, model);
            if (!sendable(v2, ledger.model(slot, model))) {
              blocked.add(TranslationLine(slot, 'Modellwahl ${model.name} ist noch nicht freigegeben', detail: v2.basis));
            }
          }
          final values = <String, String>{};
          for (final entry in block.parameters.entries) {
            if (!entry.value.specified) continue;
            final value = entry.value.value!;
            final parameter = model.parameter(entry.key);
            values[entry.key] = _fmt(value);
            if (parameter == null || !parameter.accepts(value) || parameter.blockedReason != null) {
              blocked.add(TranslationLine(slot, 'Parameter ${entry.key} kann nicht sicher gesetzt werden', detail: parameter?.blockedReason));
              continue;
            }
            final v2 = evidence.parameter(slot, model, parameter, value);
            if (!sendable(v2, ledger.parameter(slot, model, parameter))) {
              blocked.add(TranslationLine(slot, 'Parameter ${entry.key} ist noch nicht freigegeben', detail: v2.basis));
            }
          }
          if (!sendable(evidence.blockToggle(slot, true), ledger.toggle(slot, true))) {
            blocked.add(TranslationLine(slot, 'Einschalten ist noch nicht freigegeben'));
          }
          final quality = report?.quality ?? ApproximationQuality.goodApproximation;
          final summary = '${model.name}${values.isEmpty ? '' : ' (${values.entries.map((e) => '${e.key} ${e.value}').join(', ')})'}';
          if (quality == ApproximationQuality.limitedApproximation) {
            approximated.add(TranslationLine(slot, summary, detail: report?.why.join(' ')));
          } else {
            mapped.add(TranslationLine(slot, summary, detail: report?.why.join(' ')));
          }
          for (final gap in report?.notRepresented ?? const <String>[]) {
            unsupported.add(TranslationLine(slot, friendlyGap(slot, gap), detail: gap));
          }
          blocks.add(BlockPreview(slot: slot, state: RecipeBlockState.defined, quality: quality, model: model.name, parameters: values));
      }
    }

    if (blocked.isNotEmpty) critical.add('${blocked.length} nötige Operation(en) sind noch nicht für das Gerät freigegeben.');
    if (blocks.every((b) => b.state == RecipeBlockState.unchanged)) critical.add('Der Sound legt keinen Block fest.');
    if (unsupported.isNotEmpty) warnings.add('${unsupported.length} Wunsch/Wünsche des Sounds können nicht übertragen werden.');
    if (approximated.isNotEmpty) warnings.add('${approximated.length} Block/Blöcke sind nur teilweise angenähert.');
    final compatibility = critical.isNotEmpty
        ? MatriboxCompatibility.blocked
        : (unsupported.isNotEmpty || approximated.isNotEmpty ? MatriboxCompatibility.partial : MatriboxCompatibility.full);
    return MatriboxTranslationResult(
      target: target,
      blocks: List.unmodifiable(blocks),
      mappedIntents: List.unmodifiable(mapped),
      approximatedIntents: List.unmodifiable(approximated),
      unsupportedIntents: List.unmodifiable(unsupported),
      blockedOperations: List.unmodifiable(blocked),
      unchangedIntents: List.unmodifiable(unchanged),
      warnings: List.unmodifiable(warnings),
      overallCompatibility: compatibility,
      criticalReasons: List.unmodifiable(critical),
    );
  }
}
