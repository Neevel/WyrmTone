import 'dart:async';

import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

/// A library NAM with controllable description metadata.
LocalNamCapture fakeNam(
  String id,
  String name, {
  String? make,
  List<String> tags = const [],
  String? desc,
  NamCompatibility compat = NamCompatibility.compatible,
}) => LocalNamCapture(
  localId: id,
  tone3000ToneId: null,
  tone3000ModelId: null,
  toneName: name,
  captureName: name,
  creatorName: 'tester',
  description: desc,
  make: make,
  gearType: 'amp',
  tags: tags,
  license: 'cc',
  source: 'test',
  architecture: NamArchitecture.a1,
  fileSize: 1,
  localUri: Uri.file('/nams/$id.nam').toString(),
  sha256: 'sha-$id',
  downloadedAt: DateTime.utc(2026),
  downloadStatus: NamDownloadStatus.imported,
  compatibility: compat,
  targetDevice: TargetDeviceId.matriboxOne,
  validationWarnings: const [],
  attribution: '',
  cabinetContent: NamCabinetContent.unknown,
);

/// Measured values of a fake NAM. The default attack/decay/transient/composite values are
/// irrelevant on purpose: Similarity V1 must ignore them.
class FakeFeatures {
  const FakeFeatures({
    this.centroid = 1200,
    this.rolloff = 2500,
    this.mid = 0.25,
    this.highMid = 0.15,
    this.crest = 12,
    this.attack = 20,
    this.decay = -10,
    this.transient = 3,
    this.composite = 0.5,
  });
  final double centroid, rolloff, mid, highMid, crest, attack, decay, transient, composite;
}

NamAnalysis fakeAnalysis(EvaluationRole role, String namSha, FakeFeatures f) => NamAnalysis(
  key: CanonicalSignal.forRole(role).keyFor(namSha),
  features: AudioFeatureVector(
    analysisVersion: toneAnalysisVersion,
    level: const {},
    tone: {
      ToneFeatureIds.centroidHz: f.centroid,
      ToneFeatureIds.rolloff85Hz: f.rolloff,
      'tone.band.MID': f.mid,
      'tone.band.HIGH_MID': f.highMid,
      ToneFeatureIds.crestDb: f.crest,
      ToneFeatureIds.attackMs: f.attack,
      ToneFeatureIds.decayDbPerSec: f.decay,
      ToneFeatureIds.transientPeakToBodyDb: f.transient,
      ToneFeatureIds.saturationComposite: f.composite,
    },
  ),
  timings: const AnalysisTimings(namLoadMs: 1, inferenceMs: 1, extractionMs: 1),
  analyzedAt: DateTime.utc(2026),
);

/// In-process stand-in for the isolate runner: counts what the real runner would have done.
class FakeToneAnalysisRunner implements ToneAnalysisRunner {
  FakeToneAnalysisRunner({this.features = const {}, this.available = true, this.failIds = const {}, this.duringCandidate});

  /// Measured values per NAM sha256 (default features for unknown ones).
  final Map<String, FakeFeatures> features;
  bool available;
  final Set<String> failIds;

  /// Called while candidate [index] (id) is "being measured"; may request a cancel.
  Future<void> Function(int index, String id)? duringCandidate;

  int runCalls = 0;
  final startedIds = <String>[], analyzedIds = <String>[];

  /// What the real runner creates per measured NAM: one engine. Must be 0 for cache hits.
  int get enginesCreated => startedIds.length;
  bool _cancel = false;

  @override
  Future<bool> isAvailableFor(EvaluationRole role) async => available;

  @override
  void cancel() => _cancel = true;

  @override
  Stream<AnalysisEvent> run(EvaluationRole role, List<AnalysisCandidate> candidates) async* {
    runCalls++;
    _cancel = false;
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (_cancel) {
        yield const AnalysisStopped();
        return;
      }
      startedIds.add(c.id);
      yield CandidateStarted(c.id);
      await Future<void>.delayed(Duration.zero);
      await duringCandidate?.call(i, c.id);
      if (_cancel) {
        yield const AnalysisStopped(); // the unfinished measurement is discarded
        return;
      }
      if (failIds.contains(c.id)) {
        yield CandidateFailed(c.id, 'unlesbar');
        continue;
      }
      analyzedIds.add(c.id);
      yield CandidateAnalyzed(c.id, fakeAnalysis(role, c.sha256, features[c.sha256] ?? const FakeFeatures()));
    }
  }
}
