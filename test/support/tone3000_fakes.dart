import 'dart:async';
import 'dart:io';

import 'package:wyrmtone/tone3000/tone3000_api_client.dart';
import 'package:wyrmtone/tone3000/tone3000_browser.dart';
import 'package:wyrmtone/tone3000/tone3000_download_service.dart';
import 'package:wyrmtone/tone3000/tone3000_http.dart';
import 'package:wyrmtone/tone3000/tone3000_models.dart';
import 'package:wyrmtone/tone3000/tone3000_secure_store.dart';

class MemoryTone3000SecureStore implements Tone3000SecureStore {
  Tone3000Tokens? tokens;
  Tone3000PendingAuthorization? pending;

  @override
  Future<void> clearPendingAuthorization() async => pending = null;

  @override
  Future<void> clearTokens() async => tokens = null;

  @override
  Future<Tone3000PendingAuthorization?> readPendingAuthorization() async =>
      pending;

  @override
  Future<Tone3000Tokens?> readTokens() async => tokens;

  @override
  Future<void> writePendingAuthorization(
    Tone3000PendingAuthorization authorization,
  ) async => pending = authorization;

  @override
  Future<void> writeTokens(Tone3000Tokens value) async => tokens = value;
}

class FakeTone3000Browser implements Tone3000Browser {
  final controller = StreamController<Uri>.broadcast();
  final opened = <Uri>[];

  @override
  Stream<Uri> get callbacks => controller.stream;

  @override
  Future<void> open(Uri authorizationUri) async => opened.add(authorizationUri);

  Future<void> dispose() => controller.close();
}

class RecordedHttpRequest {
  const RecordedHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class FakeTone3000HttpTransport implements Tone3000HttpTransport {
  final responses = <Tone3000HttpResponse>[];
  final requests = <RecordedHttpRequest>[];

  @override
  Future<Tone3000HttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String? body,
    void Function(int received, int? total)? onProgress,
    Tone3000CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCanceled();
    requests.add(
      RecordedHttpRequest(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
      ),
    );
    final response = responses.removeAt(0);
    if (response.body.isNotEmpty) {
      onProgress?.call(response.body.length ~/ 2, response.body.length);
      cancellationToken?.throwIfCanceled();
      onProgress?.call(response.body.length, response.body.length);
    }
    return response;
  }
}

class FixedDirectoryProvider implements IrStorageDirectoryProvider {
  const FixedDirectoryProvider(this.value);
  final Directory value;

  @override
  Future<Directory> directory() async => value;
}

class FakeTone3000Api implements Tone3000Api {
  Tone3000User user = const Tone3000User(id: 1, username: 'marcel');
  Tone3000Tone? tone;
  List<Tone3000Model> models = const [];

  @override
  Future<Tone3000User> getCurrentUser() async => user;

  @override
  Future<Tone3000Tone> getTone(int toneId) async => tone!;

  @override
  Future<List<Tone3000Model>> listModels(int toneId) async => models;
}
