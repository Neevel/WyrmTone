enum LocalIrAvailability { downloaded, invalid, duplicate }

class LocalIrRecord {
  const LocalIrRecord({
    required this.localUri,
    required this.fileName,
    required this.tone3000ToneId,
    required this.tone3000ModelId,
    required this.toneName,
    required this.modelName,
    required this.creatorName,
    required this.license,
    required this.sourceUrl,
    required this.downloadedAt,
    required this.fileSize,
    required this.channels,
    required this.sampleRateHz,
    required this.bitsPerSample,
    required this.durationMs,
    required this.checksumSha256,
    required this.availability,
  });

  factory LocalIrRecord.fromJson(Map<String, Object?> json) => LocalIrRecord(
    localUri: json['localUri'] as String,
    fileName: json['fileName'] as String,
    tone3000ToneId: (json['tone3000ToneId'] as num).toInt(),
    tone3000ModelId: (json['tone3000ModelId'] as num).toInt(),
    toneName: json['toneName'] as String,
    modelName: json['modelName'] as String,
    creatorName: json['creatorName'] as String,
    license: json['license'] as String,
    sourceUrl: json['sourceUrl'] as String,
    downloadedAt: DateTime.parse(json['downloadedAt'] as String).toUtc(),
    fileSize: (json['fileSize'] as num).toInt(),
    channels: (json['channels'] as num).toInt(),
    sampleRateHz: (json['sampleRateHz'] as num).toInt(),
    bitsPerSample: (json['bitsPerSample'] as num).toInt(),
    durationMs: (json['durationMs'] as num).toInt(),
    checksumSha256: json['checksumSha256'] as String,
    availability: LocalIrAvailability.values.byName(
      json['availability'] as String,
    ),
  );

  final String localUri;
  final String fileName;
  final int tone3000ToneId;
  final int tone3000ModelId;
  final String toneName;
  final String modelName;
  final String creatorName;
  final String license;
  final String sourceUrl;
  final DateTime downloadedAt;
  final int fileSize;
  final int channels;
  final int sampleRateHz;
  final int bitsPerSample;
  final int durationMs;
  final String checksumSha256;
  final LocalIrAvailability availability;

  Map<String, Object?> toJson() => {
    'localUri': localUri,
    'fileName': fileName,
    'tone3000ToneId': tone3000ToneId,
    'tone3000ModelId': tone3000ModelId,
    'toneName': toneName,
    'modelName': modelName,
    'creatorName': creatorName,
    'license': license,
    'sourceUrl': sourceUrl,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
    'fileSize': fileSize,
    'channels': channels,
    'sampleRateHz': sampleRateHz,
    'bitsPerSample': bitsPerSample,
    'durationMs': durationMs,
    'checksumSha256': checksumSha256,
    'availability': availability.name,
  };
}
