import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../devices/device_profile.dart';
import 'local_nam_capture.dart';
import 'nam_download_service.dart';
import 'nam_repository.dart';

class PickedNamFile {
  const PickedNamFile({
    required this.name,
    required this.uri,
    required this.bytes,
  });
  final String name, uri;
  final Uint8List bytes;
}

abstract interface class NamFilePicker {
  Future<PickedNamFile?> pick();
}

class PlatformNamFilePicker implements NamFilePicker {
  const PlatformNamFilePicker();
  static const channel = MethodChannel('de.neevel.wyrmtone/ir_files');
  @override
  Future<PickedNamFile?> pick() async {
    final value = await channel.invokeMapMethod<Object?, Object?>(
      'pickNamFile',
    );
    if (value == null) return null;
    return PickedNamFile(
      name: value['fileName'] as String,
      uri: value['uri'] as String,
      bytes: value['bytes'] as Uint8List,
    );
  }
}

class NamImportService {
  NamImportService({
    required this.repository,
    this.picker = const PlatformNamFilePicker(),
    this.validator = const NamValidator(),
    this.clock = DateTime.now,
    NamStorageDirectoryProvider? storageDirectory,
  }) : storageDirectory = storageDirectory ?? getApplicationDocumentsDirectory;
  final NamRepository repository;
  final NamFilePicker picker;
  final NamValidator validator;
  final DateTime Function() clock;
  final NamStorageDirectoryProvider storageDirectory;
  Future<LocalNamCapture?> import() async {
    final picked = await picker.pick();
    if (picked == null) return null;
    final fileName = NamDownloadService.safeNamFileName(picked.name);
    if (!picked.name.toLowerCase().endsWith('.nam')) {
      throw const NamValidationException(
        'Ausgewählte Datei hat nicht die Endung .nam.',
      );
    }
    final validation = validator.validate(picked.bytes, fileName);
    final checksum = sha256.convert(picked.bytes).toString();
    final existing = (await repository.load())
        .where((e) => e.sha256 == checksum)
        .firstOrNull;
    final directory = Directory(
      '${(await storageDirectory()).path}${Platform.pathSeparator}imported_nam',
    );
    await directory.create(recursive: true);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    await destination.writeAsBytes(picked.bytes, flush: true);
    final capture = LocalNamCapture(
      localId: 'import-$checksum',
      tone3000ToneId: null,
      tone3000ModelId: null,
      toneName: fileName,
      captureName: fileName,
      creatorName: 'unbekannt',
      description: null,
      make: null,
      gearType: null,
      tags: const [],
      license: 'unbekannt',
      source: picked.uri,
      architecture: NamArchitecture.unknown,
      fileSize: picked.bytes.length,
      localUri: destination.uri.toString(),
      sha256: checksum,
      downloadedAt: clock().toUtc(),
      downloadStatus: existing == null
          ? NamDownloadStatus.imported
          : NamDownloadStatus.duplicate,
      compatibility: NamCompatibility.unknown,
      targetDevice: TargetDeviceId.matriboxOne,
      validationWarnings: [
        ...validation.warnings,
        'Architektur bei lokalem Import nicht belastbar ermittelt.',
      ],
      attribution: 'Lokaler Import · Creator/Lizenz unbekannt',
      cabinetContent: NamCabinetContent.unknown,
    );
    await repository.upsert(capture);
    return capture;
  }
}
