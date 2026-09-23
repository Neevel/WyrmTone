/// Deterministic, offline model matching: recipe traits -> Matribox model
/// candidates -> score + reasons -> selected model. No randomness, no LLM;
/// ties are broken by the library (= catalog) order.
library;

import 'matribox_chain_slot.dart';
import 'matribox_model_library.dart';
import 'matribox_model_tags.dart';
import 'matribox_transfer_catalog.dart';

class ModelCandidate {
  const ModelCandidate(this.model, this.score, this.reasons);
  final MatriboxTransferModel model;
  final double score;
  final List<String> reasons;
}

class ModelMatch {
  const ModelMatch(this.ranked);

  /// Best first.
  final List<ModelCandidate> ranked;

  ModelCandidate? get selected => ranked.firstOrNull;
  bool get isEmpty => ranked.isEmpty;
}

abstract final class MatriboxModelMatcher {
  static ModelMatch _rank(List<ModelCandidate> candidates, MatriboxModelLibrary library) {
    final order = {for (var i = 0; i < library.models.length; i++) library.models[i].code: i};
    final sorted = [...candidates]
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : (order[a.model.code] ?? 0).compareTo(order[b.model.code] ?? 0);
      });
    return ModelMatch(List.unmodifiable(sorted));
  }

  /// Models in [slot] tagged [tag]; [preferred] tags add a bonus.
  static ModelMatch byTag(
    MatriboxModelLibrary library,
    MatriboxChainSlot slot,
    String tag, {
    Set<String> preferred = const {},
  }) {
    final candidates = <ModelCandidate>[];
    for (final model in library.forSlot(slot)) {
      final tags = matriboxModelTags[model.name]?.tags;
      if (tags == null || !tags.contains(tag)) continue;
      final hits = preferred.intersection(tags);
      candidates.add(
        ModelCandidate(
          model,
          100.0 + 10 * hits.length,
          ['Art "$tag" (Modellname/Katalog)', if (hits.isNotEmpty) 'passt zu ${hits.join(', ')}'],
        ),
      );
    }
    return _rank(candidates, library);
  }

  static double _closeness(int actual, int target, int weight) =>
      ((100 - (actual - target).abs()).clamp(0, 100) * weight / 100);

  /// Amp scoring: closeness of gain (40), tightness (30) and mids (20) to the
  /// model's centres, +5 for each requested family (british, high gain) the model belongs to.
  static ModelMatch amp(
    MatriboxModelLibrary library, {
    required int gain,
    int? tightness,
    int? mids,
    String families = '',
  }) {
    final candidates = <ModelCandidate>[];
    for (final model in library.forSlot(MatriboxChainSlot.amp)) {
      final tags = matriboxModelTags[model.name];
      if (tags?.gainCenter == null) continue;
      var score = _closeness(gain, tags!.gainCenter!, 40);
      final reasons = <String>['Gain $gain ~ ${tags.gainCenter}'];
      if (tightness != null && tags.tightnessCenter != null) {
        score += _closeness(tightness, tags.tightnessCenter!, 30);
        reasons.add('Straffheit $tightness ~ ${tags.tightnessCenter}');
      }
      if (mids != null && tags.midsCenter != null) {
        score += _closeness(mids, tags.midsCenter!, 20);
        reasons.add('Mitten $mids ~ ${tags.midsCenter}');
      }
      final wanted = families.toLowerCase();
      if (wanted.contains('british') && tags.tags.contains('british')) {
        score += 5;
        reasons.add('Familie british');
      }
      if (wanted.contains('high gain') && tags.tags.contains('highGain')) {
        score += 5;
        reasons.add('Familie high gain');
      }
      candidates.add(ModelCandidate(model, score, reasons));
    }
    return _rank(candidates, library);
  }

  static final _config = RegExp(r'(\d)x(\d+)');

  /// Cabinet scoring: same speaker configuration (50) and, if the selected
  /// amp's name starts with the same family token as the cabinet, +30
  /// (`Sol 100 OD` -> `Sol 4x12`). Speaker/mic cannot be derived from the
  /// catalog and are not scored.
  static ModelMatch cab(
    MatriboxModelLibrary library, {
    required String config,
    String? ampName,
  }) {
    final family = ampName == null ? null : _familyToken(ampName);
    final candidates = <ModelCandidate>[];
    for (final model in library.forSlot(MatriboxChainSlot.cab)) {
      final match = _config.firstMatch(model.name);
      if (match == null || '${match.group(1)}x${match.group(2)}' != config) continue;
      var score = 50.0;
      final reasons = <String>['Konfiguration $config'];
      if (family != null && model.name.toLowerCase().startsWith(family)) {
        score += 30;
        reasons.add('gleiche Modellfamilie wie der Amp ("$family")');
      }
      candidates.add(ModelCandidate(model, score, reasons));
    }
    return _rank(candidates, library);
  }

  static String _familyToken(String name) {
    final first = name.split(' ').first;
    final letters = RegExp(r'^[A-Za-z]+').firstMatch(first)?.group(0) ?? first;
    return letters.toLowerCase();
  }
}
