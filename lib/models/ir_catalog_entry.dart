import 'ir_metadata.dart';

class WavFormatInfo {
  const WavFormatInfo({
    required this.container,
    required this.encoding,
    required this.sampleRateHz,
    required this.channels,
    required this.bitsPerSample,
    required this.durationMs,
  });

  factory WavFormatInfo.fromJson(Map<String, Object?> json) => WavFormatInfo(
    container: json['container'] as String? ?? 'WAV',
    encoding: json['encoding'] as String? ?? 'unbekannt',
    sampleRateHz: json['sampleRateHz'] as int?,
    channels: json['channels'] as int?,
    bitsPerSample: json['bitsPerSample'] as int?,
    durationMs: json['durationMs'] as int?,
  );

  final String container;
  final String encoding;
  final int? sampleRateHz;
  final int? channels;
  final int? bitsPerSample;
  final int? durationMs;
}

class IrCatalogEntry {
  const IrCatalogEntry({
    required this.metadata,
    required this.normalizedFileName,
    required this.format,
    required this.suitabilityHints,
    this.duplicateGroup,
  });

  factory IrCatalogEntry.fromJson(Map<String, Object?> json) => IrCatalogEntry(
    metadata: IrMetadata.fromJson(
      (json['metadata'] as Map<Object?, Object?>).cast<String, Object?>(),
    ),
    normalizedFileName: json['normalizedFileName'] as String,
    format: WavFormatInfo.fromJson(
      (json['format'] as Map<Object?, Object?>).cast<String, Object?>(),
    ),
    suitabilityHints: (json['suitabilityHints'] as List<Object?>? ?? const [])
        .cast<String>(),
    duplicateGroup: json['duplicateGroup'] as String?,
  );

  final IrMetadata metadata;
  final String normalizedFileName;
  final WavFormatInfo format;
  final List<String> suitabilityHints;
  final String? duplicateGroup;
}

enum IrAvailabilityStatus {
  present('vorhanden'),
  missing('nicht gefunden'),
  unknown('unbekannt'),
  duplicate('Duplikat');

  const IrAvailabilityStatus(this.label);
  final String label;
}

class IrLibraryEntry {
  const IrLibraryEntry({
    required this.metadata,
    required this.status,
    required this.matchedFiles,
    this.reference,
  });

  final IrMetadata metadata;
  final IrAvailabilityStatus status;
  final List<PickedIrFile> matchedFiles;
  final IrCatalogEntry? reference;
}
