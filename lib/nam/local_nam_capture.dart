import '../devices/device_profile.dart';

enum NamArchitecture { a1, a2, a2Lite, custom, unknown }

enum NamCompatibility {
  compatible,
  conversionRequired,
  unsupported,
  unknown,
  invalid,
  missingLocalFile,
}

enum NamDownloadStatus { downloaded, imported, duplicate }

enum NamCabinetContent { withoutCabinet, withCabinet, fullRig, unknown }

class LocalNamCapture {
  const LocalNamCapture({
    required this.localId,
    required this.tone3000ToneId,
    required this.tone3000ModelId,
    required this.toneName,
    required this.captureName,
    required this.creatorName,
    required this.description,
    required this.make,
    required this.gearType,
    required this.tags,
    required this.license,
    required this.source,
    required this.architecture,
    required this.fileSize,
    required this.localUri,
    required this.sha256,
    required this.downloadedAt,
    required this.downloadStatus,
    required this.compatibility,
    required this.targetDevice,
    required this.validationWarnings,
    required this.attribution,
    required this.cabinetContent,
  });
  factory LocalNamCapture.fromJson(Map<String, Object?> j) => LocalNamCapture(
    localId: j['localId'] as String,
    tone3000ToneId: (j['tone3000ToneId'] as num?)?.toInt(),
    tone3000ModelId: (j['tone3000ModelId'] as num?)?.toInt(),
    toneName: j['toneName'] as String,
    captureName: j['captureName'] as String,
    creatorName: j['creatorName'] as String,
    description: j['description'] as String?,
    make: j['make'] as String?,
    gearType: j['gearType'] as String?,
    tags: (j['tags'] as List<Object?>? ?? const []).cast<String>(),
    license: j['license'] as String,
    source: j['source'] as String,
    architecture: NamArchitecture.values.byName(j['architecture'] as String),
    fileSize: (j['fileSize'] as num).toInt(),
    localUri: j['localUri'] as String,
    sha256: j['sha256'] as String,
    downloadedAt: DateTime.parse(j['downloadedAt'] as String).toUtc(),
    downloadStatus: NamDownloadStatus.values.byName(
      j['downloadStatus'] as String,
    ),
    compatibility: NamCompatibility.values.byName(j['compatibility'] as String),
    targetDevice: TargetDeviceId.values.byName(j['targetDevice'] as String),
    validationWarnings: (j['validationWarnings'] as List<Object?>? ?? const [])
        .cast<String>(),
    attribution: j['attribution'] as String,
    cabinetContent: NamCabinetContent.values.byName(
      j['cabinetContent'] as String,
    ),
  );
  final String localId,
      toneName,
      captureName,
      creatorName,
      license,
      source,
      localUri,
      sha256,
      attribution;
  final int? tone3000ToneId, tone3000ModelId;
  final String? description, make, gearType;
  final List<String> tags, validationWarnings;
  final NamArchitecture architecture;
  final int fileSize;
  final DateTime downloadedAt;
  final NamDownloadStatus downloadStatus;
  final NamCompatibility compatibility;
  final TargetDeviceId targetDevice;
  final NamCabinetContent cabinetContent;
  LocalNamCapture withCompatibility(NamCompatibility value) => LocalNamCapture(
    localId: localId,
    tone3000ToneId: tone3000ToneId,
    tone3000ModelId: tone3000ModelId,
    toneName: toneName,
    captureName: captureName,
    creatorName: creatorName,
    description: description,
    make: make,
    gearType: gearType,
    tags: tags,
    license: license,
    source: source,
    architecture: architecture,
    fileSize: fileSize,
    localUri: localUri,
    sha256: sha256,
    downloadedAt: downloadedAt,
    downloadStatus: downloadStatus,
    compatibility: value,
    targetDevice: targetDevice,
    validationWarnings: validationWarnings,
    attribution: attribution,
    cabinetContent: cabinetContent,
  );
  Map<String, Object?> toJson() => {
    'localId': localId,
    'tone3000ToneId': tone3000ToneId,
    'tone3000ModelId': tone3000ModelId,
    'toneName': toneName,
    'captureName': captureName,
    'creatorName': creatorName,
    'description': description,
    'make': make,
    'gearType': gearType,
    'tags': tags,
    'license': license,
    'source': source,
    'architecture': architecture.name,
    'fileSize': fileSize,
    'localUri': localUri,
    'sha256': sha256,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
    'downloadStatus': downloadStatus.name,
    'compatibility': compatibility.name,
    'targetDevice': targetDevice.name,
    'validationWarnings': validationWarnings,
    'attribution': attribution,
    'cabinetContent': cabinetContent.name,
  };
}

NamCompatibility matriboxCompatibility(NamArchitecture a) => switch (a) {
  NamArchitecture.a1 => NamCompatibility.compatible,
  _ => NamCompatibility.unknown,
};
