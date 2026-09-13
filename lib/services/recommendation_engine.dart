import '../models/dnafx_capabilities.dart';
import '../models/guitar_profile.dart';
import '../models/ir_metadata.dart';
import '../models/recommendation.dart';
import '../models/target_sound.dart';

class IrScoreWeights {
  static const cabinetAndSpeaker = 0.30;
  static const brightness = 0.25;
  static const tightness = 0.20;
  static const microphoneAndPosition = 0.15;
  static const guitarAndTuning = 0.10;
}

class RecommendationEngine {
  const RecommendationEngine();

  SoundRecommendation recommend({
    required TargetSound target,
    required GuitarProfile guitar,
    required List<IrMetadata> irCatalog,
    required DnafxCapabilities capabilities,
  }) {
    final deltas = <String, int>{};
    final parameterReasons = <String, List<String>>{};
    final generalReasons = <String>[];
    final warnings = [...target.approximations];
    final plainAmpModel = target.ampModel.split(' ').first;
    if (!capabilities.ampModels.contains(plainAmpModel)) {
      warnings.add(
        'Amp-Modell $plainAmpModel ist nicht in den bestätigten DNAfx-Fähigkeiten enthalten.',
      );
    }
    for (final effect in target.effects) {
      if (!effect.contains('unbestätigt') &&
          !capabilities.effectModels.contains(effect)) {
        warnings.add(
          'Effekt $effect ist nicht als verfügbares DNAfx-Modell bestätigt.',
        );
      }
    }

    void adjust(String parameter, int delta, String reason) {
      deltas[parameter] = (deltas[parameter] ?? 0) + delta;
      parameterReasons.putIfAbsent(parameter, () => []).add(reason);
    }

    switch (guitar.pickupType) {
      case PickupType.activeHumbucker:
        adjust(
          'GAIN',
          -6,
          'Aktiver Humbucker liefert hohen Pegel; Gain reduziert.',
        );
        adjust(
          'BASS',
          -5,
          'Tieffrequente Sättigung des aktiven Pickups kontrolliert.',
        );
        adjust(
          'NOISE_GATE_ATTACK',
          3,
          'DNAfx-ATTACK leicht erhöht: Das Gate öffnet schneller.',
        );
        break;
      case PickupType.passiveHumbucker:
        if (guitar.outputLevel == OutputLevel.high) {
          adjust(
            'GAIN',
            -4,
            'Heißer passiver Humbucker: Gain leicht reduziert.',
          );
          adjust('BASS', -3, 'Heißer Humbucker: Bass leicht kontrolliert.');
        } else if (guitar.outputLevel == OutputLevel.low) {
          adjust(
            'GAIN',
            5,
            'Schwacher passiver Humbucker: Gain moderat erhöht.',
          );
        }
        break;
      case PickupType.singleCoil:
        adjust('GAIN', 5, 'Singlecoil: Gain moderat erhöht.');
        adjust('TREBLE', -3, 'Singlecoil-Spitzen vorsichtig abgemildert.');
        generalReasons.add(
          'Noise Gate bleibt bei Singlecoil bewusst vorsichtig; bei Brummen manuell prüfen.',
        );
        break;
      case PickupType.p90:
        if (guitar.outputLevel == OutputLevel.low) {
          adjust(
            'GAIN',
            3,
            'Niedriger P90-Ausgangspegel moderat ausgeglichen.',
          );
        }
        generalReasons.add(
          'P90 kann brummen; Gate nicht automatisch aggressiver eingestellt.',
        );
        break;
    }

    switch (guitar.toneCharacter) {
      case ToneCharacter.dark:
        adjust('TREBLE', 4, 'Dunkler Pickup: Höhen für Definition erhöht.');
        adjust('PRESENCE', 4, 'Dunkler Pickup: Presence erhöht.');
        break;
      case ToneCharacter.bright:
        adjust(
          'TREBLE',
          -4,
          'Heller Pickup: Höhen zur Schärfekontrolle reduziert.',
        );
        adjust('PRESENCE', -4, 'Heller Pickup: Presence reduziert.');
        break;
      case ToneCharacter.neutral:
        break;
    }

    if (guitar.tuning.depth >= 2) {
      final bassReduction = guitar.tuning.depth >= 4 ? -7 : -4;
      adjust(
        'BASS',
        bassReduction,
        'Tiefe Stimmung: Bass vor Verzerrung reduziert.',
      );
      adjust(
        'PRESENCE',
        2,
        'Tiefe Stimmung: Anschlag und obere Mitten erhalten.',
      );
      generalReasons.add(
        'Tiefe Stimmung erhöht nicht automatisch das Amp-Gain; Tightness wird bei der IR-Wahl stärker gewichtet.',
      );
    }

    final parameters = target.baseParameters.entries
        .where((entry) => capabilities.parameterNames.contains(entry.key))
        .map((entry) {
          final rawDelta = deltas[entry.key] ?? 0;
          final limitedDelta = rawDelta.clamp(-10, 10);
          return ParameterRecommendation(
            name: entry.key,
            baseValue: entry.value,
            value: (entry.value + limitedDelta).clamp(0, 100),
            reasons:
                parameterReasons[entry.key] ??
                const ['Basispreset unverändert.'],
            confirmed:
                entry.key == 'NOISE_GATE_ATTACK' &&
                target.id == 'cob-angels-dont-kill',
          );
        })
        .toList(growable: false);

    final cabEnabled = !guitar.usesRealGuitarCab;
    if (!cabEnabled) {
      warnings.add(
        'Endstufe plus reale Gitarrenbox: Cab-Simulation und Custom-IR normalerweise deaktivieren.',
      );
    }
    final rankedIrs = cabEnabled
        ? (irCatalog.map((ir) => _scoreIr(ir, target, guitar)).toList()
            ..sort((left, right) => right.score.compareTo(left.score)))
        : <IrRecommendation>[];

    return SoundRecommendation(
      ampModel: target.ampModel,
      effectChain: [...target.effects, target.ampModel],
      parameters: parameters,
      irCandidates: rankedIrs.take(3).toList(growable: false),
      cabSimulationEnabled: cabEnabled,
      reasons: [...target.confirmedFacts, ...generalReasons],
      warnings: warnings,
    );
  }

  IrRecommendation _scoreIr(
    IrMetadata ir,
    TargetSound target,
    GuitarProfile guitar,
  ) {
    final reasons = <String>[];
    var weighted = 0.0;

    final cabSpeaker = _cabSpeakerScore(ir, target);
    weighted += cabSpeaker * IrScoreWeights.cabinetAndSpeaker;
    if (cabSpeaker >= 65) {
      reasons.add('Cabinet/Speaker passen zum Zielstil.');
    }

    final brightness = _traitScore(
      ir.brightness,
      _desiredBrightness(target, guitar),
    );
    weighted += brightness * IrScoreWeights.brightness;
    if (brightness >= 70) {
      reasons.add('Brightness passt zur Gitarre und zum Ziel.');
    }

    final desiredTightness = (target.tightness + guitar.tuning.depth * 4).clamp(
      0,
      100,
    );
    final tightness = _traitScore(ir.tightness, desiredTightness);
    weighted += tightness * IrScoreWeights.tightness;
    if (tightness >= 70) {
      reasons.add('Tightness unterstützt Stimmung und Anschlag.');
    }

    final micPosition = _micPositionScore(ir);
    weighted += micPosition * IrScoreWeights.microphoneAndPosition;
    if (micPosition >= 65) {
      reasons.add('Mikrofon/Position liefern verwertbare technische Hinweise.');
    }

    final guitarTuning = _guitarTuningScore(ir, guitar);
    weighted += guitarTuning * IrScoreWeights.guitarAndTuning;

    final name = ir.fileName.toLowerCase();
    final songHint = [
      target.artist,
      target.song,
    ].any((value) => name.contains(value.toLowerCase()));
    if (songHint) {
      weighted += 3;
      reasons.add(
        'Künstler-/Songname ist nur ein schwacher Dateinamenhinweis.',
      );
    }

    // Even a good trait match is discounted when it came from sparse filename data.
    final confidenceFactor = 0.45 + (0.55 * ir.confidence);
    final score = (weighted * confidenceFactor).round().clamp(0, 100);
    final uncertain = ir.confidence < 0.6 || score < 45;
    if (uncertain) {
      reasons.add(
        'Unsichere Empfehlung wegen unvollständiger Dateinamen-Metadaten.',
      );
    }
    return IrRecommendation(
      ir: ir,
      score: score,
      reasons: reasons,
      isUncertain: uncertain,
    );
  }

  double _cabSpeakerScore(IrMetadata ir, TargetSound target) {
    var score = 0.0;
    var evidence = 0;
    final desired = '${target.cabinetStyle} ${target.ampStyle}'.toLowerCase();
    for (final value in [ir.manufacturerOrCollection, ir.cabinet, ir.speaker]) {
      if (value == null) continue;
      evidence++;
      final normalized = value.toLowerCase();
      final match =
          desired.contains(normalized) ||
          (normalized == 'v30' && desired.contains('v30')) ||
          (normalized == '1960' && desired.contains('marshall')) ||
          (normalized == '4x12' && desired.contains('4x12'));
      score += match ? 100 : 35;
    }
    return evidence == 0 ? 0 : score / evidence;
  }

  double _traitScore(int? actual, int desired) => actual == null
      ? 0
      : (100 - (actual - desired).abs()).clamp(0, 100).toDouble();

  int _desiredBrightness(TargetSound target, GuitarProfile guitar) =>
      switch (guitar.toneCharacter) {
        ToneCharacter.dark => (target.brightness + 10).clamp(0, 100),
        ToneCharacter.bright => (target.brightness - 10).clamp(0, 100),
        ToneCharacter.neutral => target.brightness,
      };

  double _micPositionScore(IrMetadata ir) {
    if (ir.microphone == null && ir.microphonePosition == null) return 0;
    if (ir.microphone != null && ir.microphonePosition != null) return 85;
    return 45;
  }

  double _guitarTuningScore(IrMetadata ir, GuitarProfile guitar) {
    if (ir.tightness == null && ir.lowEnd == null) return 0;
    var desiredTightness = 55 + guitar.tuning.depth * 5;
    if (guitar.pickupType == PickupType.activeHumbucker) {
      desiredTightness += 5;
    }
    final tight = _traitScore(ir.tightness, desiredTightness.clamp(0, 100));
    final low = _traitScore(ir.lowEnd, guitar.tuning.depth >= 4 ? 48 : 58);
    final available = [tight, low].where((value) => value > 0).toList();
    return available.isEmpty
        ? 0
        : available.reduce((a, b) => a + b) / available.length;
  }
}
