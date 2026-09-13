import 'package:wyrmtone/data/dnafx_capabilities.dart';
import 'package:wyrmtone/data/target_sounds.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/ir_metadata.dart';
import 'package:wyrmtone/models/recommendation.dart';
import 'package:wyrmtone/services/ir_filename_parser.dart';
import 'package:wyrmtone/services/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = RecommendationEngine();
  const parser = IrFilenameParser();
  final cob = targetSounds.firstWhere(
    (sound) => sound.id == 'cob-angels-dont-kill',
  );
  final nirvana = targetSounds.firstWhere(
    (sound) => sound.id == 'nirvana-come-as-you-are',
  );

  GuitarProfile profile({
    PickupType pickup = PickupType.passiveHumbucker,
    OutputLevel output = OutputLevel.medium,
    ToneCharacter tone = ToneCharacter.neutral,
    GuitarTuning tuning = GuitarTuning.dStandard,
    PlaybackPath path = PlaybackPath.frfr,
  }) => GuitarProfile(
    id: 'test',
    name: 'Test',
    guitarType: GuitarType.superstrat,
    pickupType: pickup,
    outputLevel: output,
    toneCharacter: tone,
    tuning: tuning,
    playbackPath: path,
  );

  int parameter(SoundRecommendation result, String name) =>
      result.parameters.firstWhere((item) => item.name == name).value;

  test('Children of Bodom keeps confirmed J900 and D-standard basis', () {
    final result = engine.recommend(
      target: cob,
      guitar: profile(),
      irCatalog: const [],
      capabilities: confirmedDnafxCapabilities,
    );
    expect(result.ampModel, 'J900');
    expect(result.effectChain, contains('PURE BOOST'));
    expect(parameter(result, 'NOISE_GATE_ATTACK'), 86);
  });

  test('active humbucker reduces gain and bass and raises gate attack', () {
    final passive = engine.recommend(
      target: cob,
      guitar: profile(),
      irCatalog: const [],
      capabilities: confirmedDnafxCapabilities,
    );
    final active = engine.recommend(
      target: cob,
      guitar: profile(pickup: PickupType.activeHumbucker),
      irCatalog: const [],
      capabilities: confirmedDnafxCapabilities,
    );
    expect(parameter(active, 'GAIN'), lessThan(parameter(passive, 'GAIN')));
    expect(parameter(active, 'BASS'), lessThan(parameter(passive, 'BASS')));
    expect(parameter(active, 'NOISE_GATE_ATTACK'), greaterThan(86));
  });

  test('hot passive humbucker and Drop C bright profile stay tight', () {
    final result = engine.recommend(
      target: cob,
      guitar: profile(
        output: OutputLevel.high,
        tone: ToneCharacter.bright,
        tuning: GuitarTuning.dropC,
      ),
      irCatalog: const [],
      capabilities: confirmedDnafxCapabilities,
    );
    expect(parameter(result, 'GAIN'), 64);
    expect(parameter(result, 'BASS'), lessThanOrEqualTo(38));
    expect(parameter(result, 'TREBLE'), 58);
  });

  test(
    'Nirvana plus singlecoil gains moderately without lowering gate attack',
    () {
      final result = engine.recommend(
        target: nirvana,
        guitar: profile(pickup: PickupType.singleCoil, output: OutputLevel.low),
        irCatalog: const [],
        capabilities: confirmedDnafxCapabilities,
      );
      expect(parameter(result, 'GAIN'), 41);
      expect(parameter(result, 'NOISE_GATE_ATTACK'), 80);
    },
  );

  test('real guitar cab disables cab simulation and IR recommendations', () {
    final result = engine.recommend(
      target: cob,
      guitar: profile(path: PlaybackPath.powerAmpAndGuitarCab),
      irCatalog: [parser.parse('Marshall_1960_V30_SM57_CapEdge.wav')],
      capabilities: confirmedDnafxCapabilities,
    );
    expect(result.cabSimulationEnabled, isFalse);
    expect(result.irCandidates, isEmpty);
    expect(result.warnings.join(' '), contains('reale Gitarrenbox'));
  });

  test('all automatic parameter changes are limited to ten points', () {
    final result = engine.recommend(
      target: cob,
      guitar: profile(
        pickup: PickupType.activeHumbucker,
        tone: ToneCharacter.bright,
        tuning: GuitarTuning.dropB,
      ),
      irCatalog: const [],
      capabilities: confirmedDnafxCapabilities,
    );
    for (final item in result.parameters) {
      expect((item.value - item.baseValue).abs(), lessThanOrEqualTo(10));
    }
  });

  test('IR ranking prefers matching high-confidence technical metadata', () {
    final matching = parser.parse('Marshall_1960_V30_SM57_CapEdge.wav');
    final alternative = parser.parse('Mesa_OS_Greenback_R121_Room.wav');
    final unknown = parser.parse('Angels_Dont_Kill_take.wav');
    final result = engine.recommend(
      target: cob,
      guitar: profile(),
      irCatalog: [unknown, alternative, matching],
      capabilities: confirmedDnafxCapabilities,
    );
    expect(result.irCandidates.first.ir.fileName, matching.fileName);
    expect(result.irCandidates.last.ir.fileName, unknown.fileName);
    expect(result.irCandidates.last.isUncertain, isTrue);
    expect(
      result.irCandidates.first.score,
      greaterThan(result.irCandidates.last.score),
    );
  });

  test(
    'missing metadata is penalized rather than treated as a perfect match',
    () {
      const uncertain = IrMetadata(
        fileName: 'unknown.wav',
        confidence: 0,
        detectedTags: [],
      );
      final result = engine.recommend(
        target: cob,
        guitar: profile(),
        irCatalog: const [uncertain],
        capabilities: confirmedDnafxCapabilities,
      );
      expect(result.irCandidates.single.score, lessThan(20));
      expect(result.irCandidates.single.isUncertain, isTrue);
    },
  );

  test('gate feedback respects inverse DNAfx attack semantics', () {
    expect(
      RecommendationFeedback.gateCutsNotes.proposedCorrection,
      contains('ATTACK erhöhen'),
    );
    expect(
      RecommendationFeedback.gateCutsNotes.proposedCorrection,
      isNot(contains('ATTACK senken')),
    );
  });
}
