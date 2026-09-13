import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../devices/device_profile.dart';
import '../tone3000/tone3000_config.dart';
import '../tone3000/tone3000_http.dart';
import '../tone3000/tone3000_models.dart';
import 'local_nam_capture.dart';
import 'nam_repository.dart';

class NamValidationException implements Exception {
  const NamValidationException(this.message);
  final String message;
}

class ExistingNamFileException implements Exception {
  const ExistingNamFileException(this.fileName);
  final String fileName;
}

class NamValidationResult {
  const NamValidationResult(this.warnings);
  final List<String> warnings;
}

class NamValidator {
  const NamValidator();
  NamValidationResult validate(Uint8List bytes, String fileName) {
    if (!fileName.toLowerCase().endsWith('.nam')) {
      throw const NamValidationException('Dateiendung ist nicht .nam.');
    }
    if (bytes.length < 100 || bytes.length > 100 * 1024 * 1024) {
      throw const NamValidationException(
        'Dateigröße ist für ein NAM-Capture unplausibel.',
      );
    }
    final warnings = <String>[];
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) throw const FormatException();
      if (!decoded.keys.any(
        (key) => {
          'architecture',
          'config',
          'metadata',
          'weights',
          'state_dict',
        }.contains('$key'),
      )) {
        warnings.add(
          'Keine bekannten NAM-Metadatenfelder erkannt; Architektur stammt ausschließlich aus der API.',
        );
      }
    } catch (_) {
      throw const NamValidationException(
        'Datei ist kein erkennbares NAM-JSON-Modell.',
      );
    }
    return NamValidationResult(warnings);
  }
}

NamArchitecture namArchitectureFromApi(String? value) =>
    switch (value?.toLowerCase()) {
      '1' || 'a1' => NamArchitecture.a1,
      '2' || 'a2' => NamArchitecture.a2,
      '2-lite' || 'a2-lite' || 'a2_lite' => NamArchitecture.a2Lite,
      'custom' => NamArchitecture.custom,
      _ => NamArchitecture.unknown,
    };

abstract interface class NamDownloader {
  Future<LocalNamCapture> download({
    required Tone3000Tone tone,
    required Tone3000Model model,
    required String accessToken,
    required bool replaceExisting,
    required Tone3000CancellationToken cancellationToken,
    required void Function(int, int?) onProgress,
  });
}

typedef NamStorageDirectoryProvider = Future<Directory> Function();

class NamDownloadService implements NamDownloader {
  NamDownloadService({
    required this.transport,
    required this.repository,
    this.validator = const NamValidator(),
    this.clock = DateTime.now,
    NamStorageDirectoryProvider? storageDirectory,
  }) : storageDirectory = storageDirectory ?? getApplicationDocumentsDirectory;
  final Tone3000HttpTransport transport;
  final NamRepository repository;
  final NamValidator validator;
  final DateTime Function() clock;
  final NamStorageDirectoryProvider storageDirectory;
  @override
  Future<LocalNamCapture> download({
    required Tone3000Tone tone,
    required Tone3000Model model,
    required String accessToken,
    required bool replaceExisting,
    required Tone3000CancellationToken cancellationToken,
    required void Function(int, int?) onProgress,
  }) async {
    if (!tone.isNam || !Tone3000Config.isOfficialHttps(model.modelUrl)) {
      throw const NamValidationException(
        'Nur offizielle TONE3000-NAM-Modelle sind zulässig.',
      );
    }
    final directory = Directory(
      '${(await storageDirectory()).path}${Platform.pathSeparator}tone3000_nam',
    );
    await directory.create(recursive: true);
    final fileName = safeNamFileName(model.name);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    final partial = File('${destination.path}.part');
    if (await destination.exists() && !replaceExisting) {
      throw ExistingNamFileException(fileName);
    }
    try {
      if (await partial.exists()) await partial.delete();
      final response = await transport.send(
        method: 'GET',
        uri: model.modelUrl,
        headers: {'Authorization': 'Bearer $accessToken'},
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      if (response.statusCode != 200) {
        throw StateError(
          'NAM-Download fehlgeschlagen (HTTP ${response.statusCode}).',
        );
      }
      final type = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (!{
        'application/octet-stream',
        'application/json',
        'text/plain',
        'application/x-nam',
      }.contains(type)) {
        throw StateError('Unerwarteter NAM-Downloadtyp: ${type ?? 'fehlend'}.');
      }
      final validation = validator.validate(response.body, fileName);
      final checksum = sha256.convert(response.body).toString();
      final existing = (await repository.load())
          .where((e) => e.sha256 == checksum || e.tone3000ModelId == model.id)
          .firstOrNull;
      await partial.writeAsBytes(response.body, flush: true);
      cancellationToken.throwIfCanceled();
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      if (!await destination.exists()) {
        throw const NamValidationException(
          'NAM-Datei konnte nicht im lokalen Speicher bestätigt werden.',
        );
      }
      final architecture = namArchitectureFromApi(model.architectureVersion);
      final capture = LocalNamCapture(
        localId: 't3k-${model.id}',
        tone3000ToneId: tone.id,
        tone3000ModelId: model.id,
        toneName: tone.title,
        captureName: model.name,
        creatorName: tone.creatorName,
        description: tone.description,
        make: tone.make,
        gearType: tone.gearType,
        tags: tone.tags,
        license: tone.license,
        source: tone.url.toString(),
        architecture: architecture,
        fileSize: response.body.length,
        localUri: destination.uri.toString(),
        sha256: checksum,
        downloadedAt: clock().toUtc(),
        downloadStatus: existing == null
            ? NamDownloadStatus.downloaded
            : NamDownloadStatus.duplicate,
        compatibility: matriboxCompatibility(architecture),
        targetDevice: TargetDeviceId.matriboxOne,
        validationWarnings: validation.warnings,
        attribution: '${tone.creatorName} · ${tone.license} · TONE3000',
        cabinetContent: _cabinetContent(tone.gearType),
      );
      await repository.upsert(capture);
      return capture;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  static String safeNamFileName(String input) {
    var name = input.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    if (name.toLowerCase().endsWith('.nam')) {
      name = name.substring(0, name.length - 4);
    }
    if (name.isEmpty || name == '.' || name == '..') name = 'tone3000_capture';
    return '${name.length > 100 ? name.substring(0, 100) : name}.nam';
  }
}

NamCabinetContent _cabinetContent(String? gear) => switch (gear) {
  'amp' => NamCabinetContent.withoutCabinet,
  'amp-cab' => NamCabinetContent.withCabinet,
  'full-rig' => NamCabinetContent.fullRig,
  _ => NamCabinetContent.unknown,
};
