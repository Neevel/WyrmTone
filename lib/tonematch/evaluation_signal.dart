/// Descriptor of a WyrmTone DI evaluation recording (Slice 2). The recordings are our own dry DI
/// takes (original WAV: 44.1 kHz stereo, LEFT = DRY, RIGHT = WET and never used). Nothing here
/// generates or fakes a signal. Independent of the CloData Reference Signal V4.
/// See docs/TONE_MATCH.md, "Slice 2".
library;

enum EvaluationRole { rhythm, lead, clean }

/// Format of the ORIGINAL recordings (Matribox USB audio: 44.1 kHz, stereo, 24-bit PCM).
/// The existing NamInferenceEngine needs mono Float32 at 48 kHz and does not resample, so
/// evaluation-signal preparation is: LEFT/DRY only -> exact 24-bit decode -> the single
/// resampler (EvaluationResampler, 44.1 -> 48 kHz) -> NAM.
const evaluationOriginalSampleRate = 44100;
const evaluationChannels = 2;
const evaluationBitDepth = 24;

/// Sample rate fed to the NAM engine (and used by all analysis).
const evaluationSampleRate = 48000;

/// Hard duration limits per role (seconds); the recording spec asks for the "target".
const evaluationDurationLimits = <EvaluationRole, ({double min, double target, double max})>{
  EvaluationRole.rhythm: (min: 20, target: 28, max: 30),
  EvaluationRole.lead: (min: 20, target: 28, max: 30),
  EvaluationRole.clean: (min: 12, target: 18, max: 20),
};

class EvaluationSignalException implements Exception {
  const EvaluationSignalException(this.message);
  final String message;
  @override
  String toString() => 'EvaluationSignalException: $message';
}

class EvaluationSignalDescriptor {
  const EvaluationSignalDescriptor({
    required this.id,
    required this.version,
    required this.role,
    required this.file,
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
    required this.durationSeconds,
    required this.sha256,
  });

  factory EvaluationSignalDescriptor.fromJson(Map<String, Object?> j) => EvaluationSignalDescriptor(
    id: j['id'] as String,
    version: (j['version'] as num).toInt(),
    role: EvaluationRole.values.byName(j['role'] as String),
    file: j['file'] as String,
    sampleRate: (j['sampleRate'] as num).toInt(),
    channels: (j['channels'] as num).toInt(),
    bitDepth: (j['bitDepth'] as num).toInt(),
    durationSeconds: (j['durationSeconds'] as num).toDouble(),
    sha256: j['sha256'] as String,
  );

  /// `wyrmtone-<role>-v<version>`, e.g. `wyrmtone-rhythm-v1`.
  final String id;
  final int version;
  final EvaluationRole role;

  /// Asset path of the WAV. Never used as a cache key: [sha256] is.
  final String file;
  final int sampleRate, channels, bitDepth;
  final double durationSeconds;

  /// SHA-256 (lowercase hex) of the ORIGINAL WAV file bytes: the identity of the signal.
  final String sha256;

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'role': role.name,
    'file': file,
    'sampleRate': sampleRate,
    'channels': channels,
    'bitDepth': bitDepth,
    'durationSeconds': durationSeconds,
    'sha256': sha256,
  };

  /// Problems that make this descriptor unusable; empty = valid.
  List<String> validate() {
    final limits = evaluationDurationLimits[role]!;
    return [
      if (id != 'wyrmtone-${role.name}-v$version') 'id passt nicht zu Rolle/Version (erwartet wyrmtone-${role.name}-v$version).',
      if (sampleRate != evaluationOriginalSampleRate) 'Samplerate der Originaldatei muss $evaluationOriginalSampleRate Hz sein.',
      if (channels != evaluationChannels) 'Das Original muss Stereo sein (links = Dry).',
      if (bitDepth != evaluationBitDepth) 'Das Signal muss $evaluationBitDepth Bit PCM sein.',
      if (durationSeconds < limits.min || durationSeconds > limits.max) 'Dauer ${durationSeconds}s außerhalb ${limits.min}–${limits.max}s.',
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) 'sha256 ist kein 64-stelliger Hex-Wert (Kleinbuchstaben).',
      if (file.isEmpty) 'Dateipfad fehlt.',
    ];
  }
}

/// The evaluation signals. Development location of the files is `assets/tonematch/evaluation/`
/// (NOT registered as app assets: release distribution is a separate, later decision).
abstract final class EvaluationSignalRegistry {
  static const bundled = <EvaluationSignalDescriptor>[
    EvaluationSignalDescriptor(
      id: 'wyrmtone-rhythm-v1',
      version: 1,
      role: EvaluationRole.rhythm,
      file: 'assets/tonematch/evaluation/wyrmtone-rhythm-v1.wav',
      sampleRate: 44100,
      channels: 2,
      bitDepth: 24,
      durationSeconds: 1284252 / 44100,
      sha256: 'f526393c00eba41e478a1880a523bac65dc038aae9835f74b7cbaa0aa3c6725e',
    ),
    EvaluationSignalDescriptor(
      id: 'wyrmtone-lead-v1',
      version: 1,
      role: EvaluationRole.lead,
      file: 'assets/tonematch/evaluation/wyrmtone-lead-v1.wav',
      sampleRate: 44100,
      channels: 2,
      bitDepth: 24,
      durationSeconds: 1065070 / 44100,
      sha256: 'f08fcc64d0a1c3a4a3a5e25bef3266d3f9adaac3b6b9af01617d8c95a2073bbd',
    ),
    EvaluationSignalDescriptor(
      id: 'wyrmtone-clean-v1',
      version: 1,
      role: EvaluationRole.clean,
      file: 'assets/tonematch/evaluation/wyrmtone-clean-v1.wav',
      sampleRate: 44100,
      channels: 2,
      bitDepth: 24,
      durationSeconds: 629582 / 44100,
      sha256: '1b3dafb9c9922ae2ceeb65f7487f8b6df1dfd466adbefba45159138128fb5ac8',
    ),
  ];

  static EvaluationSignalDescriptor? forRole(EvaluationRole role, [List<EvaluationSignalDescriptor> from = bundled]) {
    final matches = [for (final d in from) if (d.role == role) d]..sort((a, b) => b.version.compareTo(a.version));
    return matches.firstOrNull;
  }
}
