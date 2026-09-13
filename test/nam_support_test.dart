import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/data/target_sounds.dart';
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/nam/nam_download_service.dart';
import 'package:wyrmtone/nam/nam_import_service.dart';
import 'package:wyrmtone/nam/nam_repository.dart';
import 'package:wyrmtone/models/target_sound.dart';
import 'package:wyrmtone/services/nam_recommendation_engine.dart';
import 'package:wyrmtone/tone3000/tone3000_http.dart';
import 'package:wyrmtone/tone3000/tone3000_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recommendation_fakes.dart';
import 'support/tone3000_fakes.dart';

void main() {
  late Directory temp;
  late NamRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dnafx-nam-test-');
    repository = NamRepository(MemoryStringStore());
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('architecture and Matribox compatibility are conservative', () {
    expect(namArchitectureFromApi('1'), NamArchitecture.a1);
    expect(namArchitectureFromApi('A2'), NamArchitecture.a2);
    expect(namArchitectureFromApi('a2-lite'), NamArchitecture.a2Lite);
    expect(namArchitectureFromApi(null), NamArchitecture.unknown);
    expect(
      matriboxCompatibility(NamArchitecture.a1),
      NamCompatibility.compatible,
    );
    expect(matriboxCompatibility(NamArchitecture.a2), NamCompatibility.unknown);
    expect(
      matriboxCompatibility(NamArchitecture.unknown),
      NamCompatibility.unknown,
    );
  });

  test('safe file names cannot escape local storage', () {
    final name = NamDownloadService.safeNamFileName(r'..\bad/evil:*?"<>|.nam');
    expect(name, endsWith('.nam'));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains(r'\')));
    expect(name, isNot('..'));
  });

  test('validator rejects extension, invalid JSON and implausible size', () {
    const validator = NamValidator();
    expect(
      () => validator.validate(_validNam(), 'capture.wav'),
      throwsA(isA<NamValidationException>()),
    );
    expect(
      () =>
          validator.validate(Uint8List.fromList(List.filled(200, 1)), 'x.nam'),
      throwsA(isA<NamValidationException>()),
    );
    expect(
      () => validator.validate(utf8.encode('{}'), 'x.nam'),
      throwsA(isA<NamValidationException>()),
    );
  });

  test(
    'explicit official NAM A1 download stores metadata and attribution',
    () async {
      final http = FakeTone3000HttpTransport()
        ..responses.add(_downloadResponse(_validNam()));
      final service = NamDownloadService(
        transport: http,
        repository: repository,
        storageDirectory: () async => temp,
        clock: () => DateTime.utc(2026, 9, 10),
      );

      final capture = await service.download(
        tone: _tone(),
        model: _model(),
        accessToken: 'access-token',
        replaceExisting: false,
        cancellationToken: Tone3000CancellationToken(),
        onProgress: (_, _) {},
      );

      expect(capture.architecture, NamArchitecture.a1);
      expect(capture.compatibility, NamCompatibility.compatible);
      expect(capture.attribution, contains('Creator'));
      expect(capture.attribution, contains('TONE3000'));
      expect(capture.targetDevice, TargetDeviceId.matriboxOne);
      expect(
        http.requests.single.headers['Authorization'],
        'Bearer access-token',
      );
      expect(await File.fromUri(Uri.parse(capture.localUri)).exists(), isTrue);
      expect((await repository.load()).single.sha256, capture.sha256);
    },
  );

  test(
    'duplicate checksum is marked without hiding the second capture',
    () async {
      final bytes = _validNam();
      final http = FakeTone3000HttpTransport()
        ..responses.add(_downloadResponse(bytes))
        ..responses.add(_downloadResponse(bytes));
      final service = NamDownloadService(
        transport: http,
        repository: repository,
        storageDirectory: () async => temp,
      );
      await service.download(
        tone: _tone(),
        model: _model(),
        accessToken: 'token',
        replaceExisting: false,
        cancellationToken: Tone3000CancellationToken(),
        onProgress: (_, _) {},
      );
      final duplicate = await service.download(
        tone: _tone(),
        model: _model(id: 22, name: 'Second Capture'),
        accessToken: 'token',
        replaceExisting: false,
        cancellationToken: Tone3000CancellationToken(),
        onProgress: (_, _) {},
      );
      expect(duplicate.downloadStatus, NamDownloadStatus.duplicate);
      expect(await repository.load(), hasLength(2));
    },
  );

  test(
    'non-official URL, bad HTTP and bad content type are rejected',
    () async {
      final service = NamDownloadService(
        transport: FakeTone3000HttpTransport(),
        repository: repository,
        storageDirectory: () async => temp,
      );
      await expectLater(
        service.download(
          tone: _tone(),
          model: _model(url: 'https://example.com/model.nam'),
          accessToken: 'token',
          replaceExisting: false,
          cancellationToken: Tone3000CancellationToken(),
          onProgress: (_, _) {},
        ),
        throwsA(isA<NamValidationException>()),
      );

      for (final response in [
        Tone3000HttpResponse(
          statusCode: 404,
          headers: const {},
          body: _validNam(),
        ),
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'audio/wav'},
          body: _validNam(),
        ),
      ]) {
        final http = FakeTone3000HttpTransport()..responses.add(response);
        final checked = NamDownloadService(
          transport: http,
          repository: repository,
          storageDirectory: () async => temp,
        );
        await expectLater(
          checked.download(
            tone: _tone(),
            model: _model(name: 'failed-${response.statusCode}'),
            accessToken: 'token',
            replaceExisting: false,
            cancellationToken: Tone3000CancellationToken(),
            onProgress: (_, _) {},
          ),
          throwsA(anything),
        );
      }
    },
  );

  test('cancellation removes partial NAM file', () async {
    final token = Tone3000CancellationToken();
    final service = NamDownloadService(
      transport: _CancelingTransport(token, _validNam()),
      repository: repository,
      storageDirectory: () async => temp,
    );
    await expectLater(
      service.download(
        tone: _tone(),
        model: _model(),
        accessToken: 'token',
        replaceExisting: false,
        cancellationToken: token,
        onProgress: (_, _) {},
      ),
      throwsA(isA<Tone3000Canceled>()),
    );
    final files = await temp
        .list(recursive: true)
        .where((e) => e is File)
        .toList();
    expect(files, isEmpty);
  });

  test('manual import is read-only at source and remains unknown', () async {
    final bytes = _validNam();
    final importer = NamImportService(
      repository: repository,
      picker: _FakeNamPicker(
        PickedNamFile(
          name: 'local.nam',
          uri: 'content://documents/local.nam',
          bytes: bytes,
        ),
      ),
      storageDirectory: () async => temp,
    );
    final capture = await importer.import();
    expect(capture!.architecture, NamArchitecture.unknown);
    expect(capture.compatibility, NamCompatibility.unknown);
    expect(capture.source, 'content://documents/local.nam');
    expect(capture.validationWarnings, isNotEmpty);
  });

  test('recommendations use NAM only for Matribox and obey cabinet rules', () {
    const engine = NamRecommendationEngine();
    final target = _targetSound();
    final withoutCab = _capture(NamCabinetContent.withoutCabinet);
    final withCab = _capture(NamCabinetContent.withCabinet, id: 'with-cab');
    final unknown = _capture(NamCabinetContent.unknown, id: 'unknown');
    expect(
      engine.recommend(
        device: TargetDeviceId.dnafxGitCore,
        target: target,
        captures: [withoutCab],
      ),
      isEmpty,
    );
    final results = engine.recommend(
      device: TargetDeviceId.matriboxOne,
      target: target,
      captures: [withoutCab, withCab, unknown],
    );
    expect(results, hasLength(3));
    expect(
      results
          .firstWhere((e) => e.capture.localId == 'base')
          .additionalIrRequired,
      isTrue,
    );
    expect(
      results
          .firstWhere((e) => e.capture.localId == 'with-cab')
          .additionalIrRequired,
      isFalse,
    );
    expect(
      results
          .firstWhere((e) => e.capture.localId == 'unknown')
          .additionalIrRequired,
      isNull,
    );
  });
}

Uint8List _validNam() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({'architecture': 'standard', 'weights': List.filled(80, 0)}),
  ),
);

Tone3000HttpResponse _downloadResponse(Uint8List bytes) => Tone3000HttpResponse(
  statusCode: 200,
  headers: const {'content-type': 'application/octet-stream'},
  body: bytes,
);

Tone3000Tone _tone() => Tone3000Tone(
  id: 7,
  title: 'JCM Capture',
  creatorName: 'Creator',
  license: 'CC-BY',
  format: 'nam',
  url: Uri.parse('https://www.tone3000.com/tones/7'),
  description: 'tight high gain',
  make: 'Marshall',
  gearType: 'amp',
  tags: const ['jcm', 'v30'],
);

Tone3000Model _model({
  int id = 21,
  String name = 'JCM A1',
  String url = 'https://cdn.tone3000.com/model.nam',
}) => Tone3000Model(
  id: id,
  toneId: 7,
  name: name,
  sizeClass: 'standard',
  modelUrl: Uri.parse(url),
  architectureVersion: '1',
);

class _CancelingTransport implements Tone3000HttpTransport {
  _CancelingTransport(this.token, this.bytes);
  final Tone3000CancellationToken token;
  final Uint8List bytes;
  @override
  Future<Tone3000HttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String? body,
    void Function(int received, int? total)? onProgress,
    Tone3000CancellationToken? cancellationToken,
  }) async {
    onProgress?.call(bytes.length, bytes.length);
    token.cancel();
    return _downloadResponse(bytes);
  }
}

class _FakeNamPicker implements NamFilePicker {
  const _FakeNamPicker(this.value);
  final PickedNamFile? value;
  @override
  Future<PickedNamFile?> pick() async => value;
}

LocalNamCapture _capture(NamCabinetContent cabinet, {String id = 'base'}) =>
    LocalNamCapture(
      localId: id,
      tone3000ToneId: 1,
      tone3000ModelId: 2,
      toneName: 'Marshall JCM',
      captureName: 'JCM A1',
      creatorName: 'Creator',
      description: 'high gain tight',
      make: 'Marshall',
      gearType: 'amp',
      tags: const ['jcm'],
      license: 'CC-BY',
      source: 'https://www.tone3000.com/tones/1',
      architecture: NamArchitecture.a1,
      fileSize: 200,
      localUri: 'file:///capture.nam',
      sha256: id,
      downloadedAt: DateTime.utc(2026),
      downloadStatus: NamDownloadStatus.downloaded,
      compatibility: NamCompatibility.compatible,
      targetDevice: TargetDeviceId.matriboxOne,
      validationWarnings: const [],
      attribution: 'Creator · CC-BY · TONE3000',
      cabinetContent: cabinet,
    );

TargetSound _targetSound() => targetSounds.first;
