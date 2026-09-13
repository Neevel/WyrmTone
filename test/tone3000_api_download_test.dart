import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wyrmtone/tone3000/local_ir_repository.dart';
import 'package:wyrmtone/tone3000/tone3000_api_client.dart';
import 'package:wyrmtone/tone3000/tone3000_config.dart';
import 'package:wyrmtone/tone3000/tone3000_download_service.dart';
import 'package:wyrmtone/tone3000/tone3000_http.dart';
import 'package:wyrmtone/tone3000/tone3000_models.dart';
import 'package:wyrmtone/tone3000/tone3000_oauth.dart';
import 'package:wyrmtone/tone3000/wav_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recommendation_fakes.dart';
import 'support/tone3000_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 14);
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dnafx-tone3000-test-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('tone metadata and only official model URLs are parsed', () async {
    final store = MemoryTone3000SecureStore()
      ..tokens = Tone3000Tokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
      );
    final http = FakeTone3000HttpTransport()
      ..responses.addAll([
        _jsonResponse(
          '{"id":83759,"title":"IR Collection","description":"Cab IRs",'
          '"user":{"username":"creator","display_name":"Creator Name"},'
          '"license":"cc-by","format":"ir","url":"https://www.tone3000.com/tones/83759"}',
        ),
        _jsonResponse(
          '{"data":['
          '{"id":10,"tone_id":83759,"name":"Cab A","size":"custom",'
          '"model_url":"https://files.tone3000.com/models/10.wav"},'
          '{"id":11,"tone_id":83759,"name":"Bad","size":"custom",'
          '"model_url":"https://evil.example/11.wav"}]}',
        ),
      ]);
    final config = Tone3000Config(clientId: 'publishable');
    final session = Tone3000SessionManager(
      store: store,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );
    final api = NetworkTone3000Api(transport: http, sessionManager: session);

    final tone = await api.getTone(83759);
    final models = await api.listModels(83759);

    expect(tone.creatorName, 'Creator Name');
    expect(tone.license, 'cc-by');
    expect(tone.isImpulseResponse, isTrue);
    expect(models, hasLength(1));
    expect(models.single.id, 10);
  });

  test('single-object endpoints tolerate a data envelope', () async {
    final store = MemoryTone3000SecureStore()
      ..tokens = Tone3000Tokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
      );
    final http = FakeTone3000HttpTransport()
      ..responses.addAll([
        _jsonResponse(
          '{"data":{"id":4,"username":"tester","display_name":null}}',
        ),
        _jsonResponse(
          '{"data":{"id":83759,"title":"IR Collection",'
          '"description":null,"user":{"username":"creator",'
          '"display_name":null},"license":"cc-by","format":"ir",'
          '"url":"https://www.tone3000.com/tones/83759"}}',
        ),
      ]);
    final config = Tone3000Config(clientId: 'publishable');
    final session = Tone3000SessionManager(
      store: store,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );
    final api = NetworkTone3000Api(transport: http, sessionManager: session);

    expect((await api.getCurrentUser()).username, 'tester');
    expect((await api.getTone(83759)).creatorName, 'creator');
  });

  test('OAuth user wrapper and opaque user id are accepted', () async {
    final store = MemoryTone3000SecureStore()
      ..tokens = Tone3000Tokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
      );
    final http = FakeTone3000HttpTransport()
      ..responses.add(
        _jsonResponse(
          '{"user":{"id":"opaque-user-id","username":"tester",'
          '"display_name":null}}',
        ),
      );
    final config = Tone3000Config(clientId: 'publishable');
    final session = Tone3000SessionManager(
      store: store,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );
    final api = NetworkTone3000Api(transport: http, sessionManager: session);

    final user = await api.getCurrentUser();
    expect(user.id, 'opaque-user-id');
    expect(user.username, 'tester');
  });

  test('malformed API objects become safe phase-specific errors', () async {
    final store = MemoryTone3000SecureStore()
      ..tokens = Tone3000Tokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
      );
    final http = FakeTone3000HttpTransport()
      ..responses.add(_jsonResponse('{"id":null}'));
    final config = Tone3000Config(clientId: 'publishable');
    final session = Tone3000SessionManager(
      store: store,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );
    final api = NetworkTone3000Api(transport: http, sessionManager: session);

    await expectLater(
      api.getCurrentUser(),
      throwsA(
        isA<Tone3000ApiException>().having(
          (error) => error.message,
          'message',
          contains('USER-DATA'),
        ),
      ),
    );
  });

  test('IR model variants are accepted and unsafe entries skipped', () async {
    final store = MemoryTone3000SecureStore()
      ..tokens = Tone3000Tokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
      );
    final http = FakeTone3000HttpTransport()
      ..responses.add(
        _jsonResponse(
          '{"data":['
          '{"id":"10","file_name":"Cab A.wav","size":null,'
          '"model_url":"https://files.tone3000.com/models/10.wav"},'
          '{"id":11,"model_url":null},'
          '{"id":12,"name":"External",'
          '"model_url":"https://example.com/12.wav"}]}',
        ),
      );
    final config = Tone3000Config(clientId: 'publishable');
    final session = Tone3000SessionManager(
      store: store,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );
    final api = NetworkTone3000Api(transport: http, sessionManager: session);

    final models = await api.listModels(83759);
    expect(models, hasLength(1));
    expect(models.single.id, 10);
    expect(models.single.toneId, 83759);
    expect(models.single.sizeClass, 'IR');
  });

  test(
    'one explicit model download preserves attribution and progress',
    () async {
      final http = FakeTone3000HttpTransport()
        ..responses.add(
          Tone3000HttpResponse(
            statusCode: 200,
            headers: const {'content-type': 'audio/wav'},
            body: _wav(channels: 1),
          ),
        );
      final repository = LocalIrRepository(MemoryStringStore());
      final service = Tone3000DownloadService(
        transport: http,
        directoryProvider: FixedDirectoryProvider(directory),
        repository: repository,
        clock: () => now,
      );
      final progress = <int>[];

      final result = await service.download(
        tone: _tone,
        model: _model,
        accessToken: 'access-token',
        replaceExisting: false,
        cancellationToken: Tone3000CancellationToken(),
        onProgress: (received, _) => progress.add(received),
      );

      expect(http.requests, hasLength(1));
      expect(http.requests.single.uri, _model.modelUrl);
      expect(http.requests.single.uri.path, isNot(contains('/download')));
      expect(
        http.requests.single.headers['Authorization'],
        'Bearer access-token',
      );
      expect(progress.length, 2);
      expect(
        await File.fromUri(Uri.parse(result.record.localUri)).exists(),
        isTrue,
      );
      expect(result.record.creatorName, 'Creator Name');
      expect(result.record.license, 'cc-by');
      expect(result.record.tone3000ToneId, 83759);
      expect(result.record.tone3000ModelId, 10);
    },
  );

  test('same checksum is marked as duplicate', () async {
    final wav = _wav(channels: 1);
    final http = FakeTone3000HttpTransport()
      ..responses.addAll([
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/octet-stream'},
          body: wav,
        ),
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/octet-stream'},
          body: wav,
        ),
      ]);
    final repository = LocalIrRepository(MemoryStringStore());
    final service = Tone3000DownloadService(
      transport: http,
      directoryProvider: FixedDirectoryProvider(directory),
      repository: repository,
    );
    await service.download(
      tone: _tone,
      model: _model,
      accessToken: 'access',
      replaceExisting: false,
      cancellationToken: Tone3000CancellationToken(),
      onProgress: (_, _) {},
    );
    final duplicate = await service.download(
      tone: _tone,
      model: Tone3000Model(
        id: 12,
        toneId: 83759,
        name: 'Other Name',
        sizeClass: 'custom',
        modelUrl: Uri.parse('https://files.tone3000.com/models/12.wav'),
      ),
      accessToken: 'access',
      replaceExisting: false,
      cancellationToken: Tone3000CancellationToken(),
      onProgress: (_, _) {},
    );
    expect(duplicate.isDuplicate, isTrue);
    expect(duplicate.record.creatorName, 'Creator Name');
    expect(duplicate.record.license, 'cc-by');
  });

  test('bad HTTP response and invalid WAV leave no partial file', () async {
    final repository = LocalIrRepository(MemoryStringStore());
    final http = FakeTone3000HttpTransport()
      ..responses.addAll([
        Tone3000HttpResponse(
          statusCode: 500,
          headers: const {'content-type': 'audio/wav'},
          body: Uint8List(0),
        ),
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'audio/wav'},
          body: Uint8List.fromList(utf8.encode('not a wav')),
        ),
      ]);
    final service = Tone3000DownloadService(
      transport: http,
      directoryProvider: FixedDirectoryProvider(directory),
      repository: repository,
    );
    Future<void> attempt() => service.download(
      tone: _tone,
      model: _model,
      accessToken: 'access',
      replaceExisting: false,
      cancellationToken: Tone3000CancellationToken(),
      onProgress: (_, _) {},
    );

    await expectLater(attempt(), throwsA(isA<StateError>()));
    await expectLater(attempt(), throwsA(isA<WavValidationException>()));
    expect(await directory.list().toList(), isEmpty);
  });

  test('canceled download makes no request or partial file', () async {
    final token = Tone3000CancellationToken()..cancel();
    final http = FakeTone3000HttpTransport();
    final service = Tone3000DownloadService(
      transport: http,
      directoryProvider: FixedDirectoryProvider(directory),
      repository: LocalIrRepository(MemoryStringStore()),
    );
    await expectLater(
      service.download(
        tone: _tone,
        model: _model,
        accessToken: 'access',
        replaceExisting: false,
        cancellationToken: token,
        onProgress: (_, _) {},
      ),
      throwsA(isA<Tone3000Canceled>()),
    );
    expect(http.requests, isEmpty);
    expect(await directory.list().toList(), isEmpty);
  });

  test('cancellation during progress leaves no partial file', () async {
    final token = Tone3000CancellationToken();
    final http = FakeTone3000HttpTransport()
      ..responses.add(
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'audio/wav'},
          body: _wav(channels: 1),
        ),
      );
    final service = Tone3000DownloadService(
      transport: http,
      directoryProvider: FixedDirectoryProvider(directory),
      repository: LocalIrRepository(MemoryStringStore()),
    );

    await expectLater(
      service.download(
        tone: _tone,
        model: _model,
        accessToken: 'access',
        replaceExisting: false,
        cancellationToken: token,
        onProgress: (_, _) => token.cancel(),
      ),
      throwsA(isA<Tone3000Canceled>()),
    );
    expect(http.requests, hasLength(1));
    expect(await directory.list().toList(), isEmpty);
  });

  test(
    'existing file requires explicit replacement before any request',
    () async {
      final destination = File(
        '${directory.path}${Platform.pathSeparator}Cab Model.wav',
      );
      await destination.writeAsString('existing');
      final http = FakeTone3000HttpTransport();
      final service = Tone3000DownloadService(
        transport: http,
        directoryProvider: FixedDirectoryProvider(directory),
        repository: LocalIrRepository(MemoryStringStore()),
      );

      await expectLater(
        service.download(
          tone: _tone,
          model: _model,
          accessToken: 'access',
          replaceExisting: false,
          cancellationToken: Tone3000CancellationToken(),
          onProgress: (_, _) {},
        ),
        throwsA(isA<ExistingIrFileException>()),
      );
      expect(http.requests, isEmpty);
      expect(await destination.readAsString(), 'existing');
    },
  );

  test('manipulated filename is confined and normalized to WAV', () {
    final name = Tone3000DownloadService.safeWavFileName(
      '../../secret\\evil:*?"<>|.wav',
    );
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains('\\')));
    expect(name, endsWith('.wav'));
    expect(name, isNot('..wav'));
  });

  test('WAV validator detects stereo and rejects unsupported channels', () {
    const validator = WavValidator();
    expect(validator.validate(_wav(channels: 2)).isStereo, isTrue);
    expect(
      () => validator.validate(_wav(channels: 3)),
      throwsA(isA<WavValidationException>()),
    );
  });
}

Tone3000HttpResponse _jsonResponse(String json) => Tone3000HttpResponse(
  statusCode: 200,
  headers: const {'content-type': 'application/json'},
  body: Uint8List.fromList(utf8.encode(json)),
);

final _tone = Tone3000Tone(
  id: 83759,
  title: 'IR Collection',
  creatorName: 'Creator Name',
  license: 'cc-by',
  format: 'ir',
  url: Uri.parse('https://www.tone3000.com/tones/83759'),
);

final _model = Tone3000Model(
  id: 10,
  toneId: 83759,
  name: 'Cab Model',
  sizeClass: 'custom',
  modelUrl: Uri.parse('https://files.tone3000.com/models/10.wav'),
);

Uint8List _wav({required int channels}) {
  const sampleRate = 44100;
  const bits = 24;
  const dataLength = 12;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, 36 + dataLength, Endian.little);
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  final blockAlign = channels * bits ~/ 8;
  data.setUint32(28, sampleRate * blockAlign, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bits, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, dataLength, Endian.little);
  return bytes;
}
