import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'local_ir_record.dart';
import 'local_ir_repository.dart';
import 'tone3000_config.dart';
import 'tone3000_http.dart';
import 'tone3000_models.dart';
import 'wav_validator.dart';

abstract interface class IrStorageDirectoryProvider {
  Future<Directory> directory();
}

class AppIrStorageDirectoryProvider implements IrStorageDirectoryProvider {
  const AppIrStorageDirectoryProvider();

  @override
  Future<Directory> directory() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}tone3000_irs',
  );
}

class ExistingIrFileException implements Exception {
  const ExistingIrFileException(this.fileName);
  final String fileName;
}

class Tone3000DownloadResult {
  const Tone3000DownloadResult({
    required this.record,
    required this.isDuplicate,
  });
  final LocalIrRecord record;
  final bool isDuplicate;
}

abstract interface class Tone3000Downloader {
  Future<Tone3000DownloadResult> download({
    required Tone3000Tone tone,
    required Tone3000Model model,
    required String accessToken,
    required bool replaceExisting,
    required Tone3000CancellationToken cancellationToken,
    required void Function(int received, int? total) onProgress,
  });
}

class Tone3000DownloadService implements Tone3000Downloader {
  const Tone3000DownloadService({
    required this.transport,
    required this.directoryProvider,
    required this.repository,
    this.validator = const WavValidator(),
    this.clock = DateTime.now,
  });

  final Tone3000HttpTransport transport;
  final IrStorageDirectoryProvider directoryProvider;
  final LocalIrRepository repository;
  final WavValidator validator;
  final DateTime Function() clock;

  @override
  Future<Tone3000DownloadResult> download({
    required Tone3000Tone tone,
    required Tone3000Model model,
    required String accessToken,
    required bool replaceExisting,
    required Tone3000CancellationToken cancellationToken,
    required void Function(int received, int? total) onProgress,
  }) async {
    if (!tone.isImpulseResponse ||
        !Tone3000Config.isOfficialHttps(model.modelUrl)) {
      throw StateError('Nur offizielle TONE3000-IR-Modelle sind zulässig.');
    }
    final directory = await directoryProvider.directory();
    await directory.create(recursive: true);
    final fileName = safeWavFileName(model.name);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    final partial = File('${destination.path}.part');
    if (await destination.exists() && !replaceExisting) {
      throw ExistingIrFileException(fileName);
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
      cancellationToken.throwIfCanceled();
      if (response.statusCode != 200) {
        throw StateError(
          'TONE3000-Download fehlgeschlagen (HTTP ${response.statusCode}).',
        );
      }
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (!const {
        'audio/wav',
        'audio/x-wav',
        'audio/wave',
        'application/octet-stream',
      }.contains(contentType)) {
        throw StateError(
          'Unerwarteter Downloadtyp: ${contentType ?? 'fehlend'}.',
        );
      }
      final wav = validator.validate(response.body);
      final checksum = sha256.convert(response.body).toString();
      final duplicate = await repository.findByChecksum(checksum);
      await partial.writeAsBytes(response.body, flush: true);
      cancellationToken.throwIfCanceled();
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      final record = LocalIrRecord(
        localUri: destination.uri.toString(),
        fileName: fileName,
        tone3000ToneId: tone.id,
        tone3000ModelId: model.id,
        toneName: tone.title,
        modelName: model.name,
        creatorName: tone.creatorName,
        license: tone.license,
        sourceUrl: tone.url.toString(),
        downloadedAt: clock().toUtc(),
        fileSize: response.body.length,
        channels: wav.channels,
        sampleRateHz: wav.sampleRateHz,
        bitsPerSample: wav.bitsPerSample,
        durationMs: wav.durationMs,
        checksumSha256: checksum,
        availability: duplicate == null
            ? LocalIrAvailability.downloaded
            : LocalIrAvailability.duplicate,
      );
      await repository.upsert(record);
      return Tone3000DownloadResult(
        record: record,
        isDuplicate: duplicate != null,
      );
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  static String safeWavFileName(String suggested) {
    var base = suggested
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();
    if (base.toLowerCase().endsWith('.wav')) {
      base = base.substring(0, base.length - 4).trim();
    }
    if (base.isEmpty || base == '.' || base == '..') base = 'tone3000_ir';
    if (base.length > 100) base = base.substring(0, 100).trimRight();
    return '$base.wav';
  }
}
