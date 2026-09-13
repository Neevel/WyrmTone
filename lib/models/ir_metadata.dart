class IrMetadata {
  const IrMetadata({
    required this.fileName,
    required this.confidence,
    required this.detectedTags,
    this.uri,
    this.manufacturerOrCollection,
    this.cabinet,
    this.speaker,
    this.microphone,
    this.microphonePosition,
    this.brightness,
    this.tightness,
    this.lowEnd,
    this.note,
  });

  factory IrMetadata.fromJson(Map<String, Object?> json) => IrMetadata(
    fileName: json['fileName'] as String,
    uri: json['uri'] as String?,
    manufacturerOrCollection: json['manufacturerOrCollection'] as String?,
    cabinet: json['cabinet'] as String?,
    speaker: json['speaker'] as String?,
    microphone: json['microphone'] as String?,
    microphonePosition: json['microphonePosition'] as String?,
    brightness: json['brightness'] as int?,
    tightness: json['tightness'] as int?,
    lowEnd: json['lowEnd'] as int?,
    confidence: (json['confidence'] as num).toDouble(),
    detectedTags: (json['detectedTags'] as List<Object?>).cast<String>(),
    note: json['note'] as String?,
  );

  final String fileName;
  final String? uri;
  final String? manufacturerOrCollection;
  final String? cabinet;
  final String? speaker;
  final String? microphone;
  final String? microphonePosition;
  final int? brightness;
  final int? tightness;
  final int? lowEnd;
  final double confidence;
  final List<String> detectedTags;
  final String? note;

  IrMetadata copyWith({String? uri}) => IrMetadata(
    fileName: fileName,
    uri: uri ?? this.uri,
    manufacturerOrCollection: manufacturerOrCollection,
    cabinet: cabinet,
    speaker: speaker,
    microphone: microphone,
    microphonePosition: microphonePosition,
    brightness: brightness,
    tightness: tightness,
    lowEnd: lowEnd,
    confidence: confidence,
    detectedTags: detectedTags,
    note: note,
  );

  String get duplicateKey => (uri?.toLowerCase().trim().isNotEmpty ?? false)
      ? uri!.toLowerCase().trim()
      : fileName.toLowerCase().trim();

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'uri': uri,
    'manufacturerOrCollection': manufacturerOrCollection,
    'cabinet': cabinet,
    'speaker': speaker,
    'microphone': microphone,
    'microphonePosition': microphonePosition,
    'brightness': brightness,
    'tightness': tightness,
    'lowEnd': lowEnd,
    'confidence': confidence,
    'detectedTags': detectedTags,
    'note': note,
  };
}

class PickedIrFile {
  const PickedIrFile({required this.fileName, required this.uri});

  factory PickedIrFile.fromMap(Map<Object?, Object?> map) => PickedIrFile(
    fileName: map['fileName'] as String? ?? 'unknown.wav',
    uri: map['uri'] as String? ?? '',
  );

  final String fileName;
  final String uri;
}

class PickedIrFolder {
  const PickedIrFolder({required this.treeUri, required this.files});

  factory PickedIrFolder.fromMap(Map<Object?, Object?> map) => PickedIrFolder(
    treeUri: map['treeUri'] as String? ?? '',
    files: (map['files'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(PickedIrFile.fromMap)
        .where((file) => file.fileName.toLowerCase().endsWith('.wav'))
        .toList(growable: false),
  );

  final String treeUri;
  final List<PickedIrFile> files;
}
