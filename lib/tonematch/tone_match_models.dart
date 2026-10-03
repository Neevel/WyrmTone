/// Tone Match V1 data model. Device-independent: nothing here knows a Matribox model,
/// algorithm code or protocol byte. See docs/TONE_MATCH.md.
library;

import '../models/tone_target.dart' show SoundRole, ToneDimension;
import '../nam/local_nam_capture.dart';
import 'acoustic_target.dart';

/// Where a statement comes from. No numeric "AI confidence" anywhere.
enum EvidenceKind { known, curated, measured, libraryMetadata, userInput, inferred, heuristic, unknown }

extension EvidenceKindLabel on EvidenceKind {
  String get label => switch (this) {
    EvidenceKind.known => 'Bekannt',
    EvidenceKind.curated => 'Kuratiert',
    EvidenceKind.measured => 'Gemessen',
    EvidenceKind.libraryMetadata => 'Aus Bibliotheksdaten',
    EvidenceKind.userInput => 'Deine Eingabe',
    EvidenceKind.inferred => 'Abgeleitet',
    EvidenceKind.heuristic => 'Geschätzt',
    EvidenceKind.unknown => 'Unbekannt',
  };
}

class ToneEvidence {
  const ToneEvidence(this.kind, this.source);
  final EvidenceKind kind;
  final String source;
}

enum ToneMatchMode { songArtist, audioReference }

class ToneMatchRequest {
  const ToneMatchRequest({required this.text, this.mode = ToneMatchMode.songArtist, this.guitarName, this.guitarPickups});
  final String text;
  final ToneMatchMode mode;
  final String? guitarName;
  final String? guitarPickups;
}

enum IntentConfidence { low, medium, high }

/// What sound is wanted. Provider-independent (local knowledge today, an optional online provider
/// later); the same shape is the input of the later ToneDeviceCapabilities adaptation.
class ToneIntent {
  const ToneIntent({
    required this.query,
    required this.role,
    required this.dimensions,
    required this.ampFamilies,
    required this.namTags,
    required this.cabinet,
    required this.delayKind,
    required this.reverbKind,
    required this.descriptors,
    required this.confidence,
    required this.evidence,
    this.artist,
    this.song,
    this.matchedTitle,
    this.songKnown = false,
  });

  final String query;
  final String? artist, song;

  /// Title of the knowledge entry the intent was derived from.
  final String? matchedTitle;

  /// False when only the artist/style was found, not the specific song.
  final bool songKnown;
  final SoundRole role;

  /// Perceptual 0..100 values (gain, mids, sustain ...); absent = unspecified, never guessed.
  final Map<ToneDimension, int> dimensions;
  final List<String> ampFamilies, namTags;
  final String cabinet;
  final String? delayKind, reverbKind;

  /// Short human words ("warm", "singend") for the result header.
  final List<String> descriptors;
  final IntentConfidence confidence;

  /// Keyed by aspect: `amp`, `gain`, `role`, `song`, `effects`, `cabinet` ...
  final Map<String, ToneEvidence> evidence;

  int? dim(ToneDimension d) => dimensions[d];
}

enum NamMatchLevel { good, partial, uncertain }

/// A scored local NAM. [score] is a sorting number from metadata only (HEURISTIC); it is not a
/// percentage and never shown as one.
class ToneMatchCandidate {
  const ToneMatchCandidate({
    required this.capture,
    required this.score,
    required this.level,
    required this.reasons,
    required this.cautions,
  });
  final LocalNamCapture capture;
  final double score;
  final NamMatchLevel level;
  final List<String> reasons, cautions;
}

/// Abstract plan: what the sound should do, independent of any device.
class TonePlan {
  const TonePlan({
    required this.intent,
    required this.candidate,
    required this.needsIr,
    required this.delayKind,
    required this.reverbKind,
    required this.notes,
  });
  final ToneIntent intent;
  final ToneMatchCandidate? candidate;

  /// null = unknown (cabinet share of the NAM not stated).
  final bool? needsIr;
  final String? delayKind, reverbKind;
  final List<String> notes;
}

/// What a target device can do. Filled by the app from its device profile; the engine never
/// hard-codes a device.
class ToneDeviceCapabilities {
  const ToneDeviceCapabilities({
    required this.name,
    required this.namTransfer,
    required this.presetTransfer,
    this.supportsDelay = true,
    this.supportsReverb = true,
  });
  final String name;
  final bool namTransfer, presetTransfer, supportsDelay, supportsReverb;
}

class DeviceTonePlan {
  const DeviceTonePlan({
    required this.plan,
    required this.device,
    required this.canTransferNam,
    required this.canTransferPreset,
    required this.limitations,
  });
  final TonePlan plan;
  final ToneDeviceCapabilities? device;
  final bool canTransferNam, canTransferPreset;
  final List<String> limitations;
}

enum ToneMatchFailure { noKnowledge, noNams, noSuitableNams, analysisFailed, emptyQuery }

/// One shown sound. There is deliberately no percentage and no quality class: only the order.
class ToneMatchHit {
  const ToneMatchHit({required this.candidate, required this.rank, required this.reasons, required this.measured});
  final ToneMatchCandidate candidate;

  /// 1 = best among the sounds that were checked.
  final int rank;

  /// Plain-language reasons; only statements that follow from the target and the measurements.
  final List<String> reasons;

  /// False if the order rests on the description alone (no acoustic measurement was possible).
  final bool measured;
}

class ToneMatchResult {
  const ToneMatchResult({
    required this.request,
    required this.intent,
    required this.plan,
    this.hits = const [],
    this.target,
    this.checkedCount = 0,
    this.moreAvailable = 0,
    this.measured = false,
    this.analysisUnavailable = false,
    this.skippedCount = 0,
    this.failure,
  });
  final ToneMatchRequest request;
  final ToneIntent? intent;

  /// Device adaptation of the best hit (cabinet hint, device limits); null without a hit.
  final DeviceTonePlan? plan;

  /// At most three, best first.
  final List<ToneMatchHit> hits;

  /// What the match is steered by (acoustic directions with their evidence, and what stays unmapped).
  final AcousticTargetProfile? target;

  /// How many sounds were checked so far, how many more could still be checked on request.
  final int checkedCount, moreAvailable;

  /// True if the hits are ordered by measurement; false = ordered by description only.
  final bool measured;

  /// The fixed test recording is not on this device, so only the description-based pre-selection exists.
  final bool analysisUnavailable;

  /// Sounds that could not be measured (unreadable/incompatible file).
  final int skippedCount;
  final ToneMatchFailure? failure;
  bool get ok => failure == null;
}

/// Prepared for the feedback loop (V1 stores nothing and trains nothing).
enum ToneMatchFeedback { tooDark, tooBright, tooLittleGain, tooMuchGain, moreSustain, fewerEffects, liked, notFitting }

/// Slice-2 types (no implementation yet; see evaluation_signal.dart / tone_features.dart).
class AudioFeatureVector {
  const AudioFeatureVector({required this.analysisVersion, required this.level, required this.tone});
  final int analysisVersion;

  /// LEVEL features (loudness dependent): stored, never scored.
  final Map<String, double> level;

  /// TONE features (computed on the level-normalised output): the only ones a similarity may use.
  final Map<String, double> tone;
}

class AnalysisTimings {
  const AnalysisTimings({required this.namLoadMs, required this.inferenceMs, required this.extractionMs});
  final int namLoadMs, inferenceMs, extractionMs;
  int get totalMs => namLoadMs + inferenceMs + extractionMs;
}

/// Cache key of one analysis: never a file name. Any change of NAM, signal or analysis version
/// produces a different key, so stale results are never reused.
class NamAnalysisKey {
  const NamAnalysisKey({required this.namSha256, required this.signalSha256, required this.signalId, required this.analysisVersion});
  final String namSha256, signalSha256, signalId;
  final int analysisVersion;
  String get value => '$namSha256|$signalSha256|$signalId|a$analysisVersion';
  @override
  bool operator ==(Object other) => other is NamAnalysisKey && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class NamAnalysis {
  const NamAnalysis({required this.key, required this.features, required this.timings, required this.analyzedAt});

  factory NamAnalysis.fromJson(Map<String, Object?> j) => NamAnalysis(
    key: NamAnalysisKey(
      namSha256: j['namSha256'] as String,
      signalSha256: j['signalSha256'] as String,
      signalId: j['signalId'] as String,
      analysisVersion: (j['analysisVersion'] as num).toInt(),
    ),
    features: AudioFeatureVector(
      analysisVersion: (j['analysisVersion'] as num).toInt(),
      level: (j['level'] as Map).cast<String, num>().map((k, v) => MapEntry(k, v.toDouble())),
      tone: (j['tone'] as Map).cast<String, num>().map((k, v) => MapEntry(k, v.toDouble())),
    ),
    timings: AnalysisTimings(
      namLoadMs: (j['namLoadMs'] as num).toInt(),
      inferenceMs: (j['inferenceMs'] as num).toInt(),
      extractionMs: (j['extractionMs'] as num).toInt(),
    ),
    analyzedAt: DateTime.parse(j['analyzedAt'] as String).toUtc(),
  );

  final NamAnalysisKey key;
  final AudioFeatureVector features;
  final AnalysisTimings timings;
  final DateTime analyzedAt;

  Map<String, Object?> toJson() => {
    'namSha256': key.namSha256,
    'signalSha256': key.signalSha256,
    'signalId': key.signalId,
    'analysisVersion': key.analysisVersion,
    'level': features.level,
    'tone': features.tone,
    'namLoadMs': timings.namLoadMs,
    'inferenceMs': timings.inferenceMs,
    'extractionMs': timings.extractionMs,
    'analyzedAt': analyzedAt.toUtc().toIso8601String(),
  };
}
