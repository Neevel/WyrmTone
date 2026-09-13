import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tone3000_config.dart';

class Tone3000Canceled implements Exception {
  const Tone3000Canceled();
}

class Tone3000CancellationToken {
  bool _canceled = false;
  bool get isCanceled => _canceled;
  void cancel() => _canceled = true;
  void throwIfCanceled() {
    if (_canceled) throw const Tone3000Canceled();
  }
}

class Tone3000HttpResponse {
  const Tone3000HttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;

  String get text => utf8.decode(body);
  Map<String, Object?> get json =>
      (jsonDecode(text) as Map<Object?, Object?>).cast<String, Object?>();
}

abstract interface class Tone3000HttpTransport {
  Future<Tone3000HttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String? body,
    void Function(int received, int? total)? onProgress,
    Tone3000CancellationToken? cancellationToken,
  });
}

class NetworkTone3000HttpTransport implements Tone3000HttpTransport {
  NetworkTone3000HttpTransport({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<Tone3000HttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String? body,
    void Function(int received, int? total)? onProgress,
    Tone3000CancellationToken? cancellationToken,
  }) async {
    if (!Tone3000Config.isOfficialHttps(uri)) {
      throw StateError('Nicht erlaubter TONE3000-Endpunkt.');
    }
    cancellationToken?.throwIfCanceled();
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    final bytes = BytesBuilder(copy: false);
    final total = response.contentLength < 0 ? null : response.contentLength;
    var received = 0;
    await for (final chunk in response) {
      cancellationToken?.throwIfCanceled();
      bytes.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return Tone3000HttpResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      body: bytes.takeBytes(),
    );
  }
}

String formEncode(Map<String, String> values) => values.entries
    .map(
      (entry) =>
          '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
    )
    .join('&');
