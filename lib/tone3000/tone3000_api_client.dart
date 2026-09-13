import 'tone3000_config.dart';
import 'tone3000_http.dart';
import 'tone3000_models.dart';
import 'tone3000_oauth.dart';

abstract interface class Tone3000Api {
  Future<Tone3000User> getCurrentUser();
  Future<Tone3000Tone> getTone(int toneId);
  Future<List<Tone3000Model>> listModels(int toneId);
}

class Tone3000ApiException implements Exception {
  const Tone3000ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NetworkTone3000Api implements Tone3000Api {
  const NetworkTone3000Api({
    required this.transport,
    required this.sessionManager,
  });

  final Tone3000HttpTransport transport;
  final Tone3000SessionManager sessionManager;

  @override
  Future<Tone3000User> getCurrentUser() async {
    final response = await _get(Tone3000Config.apiBase.resolve('user'));
    try {
      return Tone3000User.fromJson(
        _object(response, expectedKey: 'username', envelopeKey: 'user'),
      );
    } catch (_) {
      throw const Tone3000ApiException(
        'TONE3000 hat ungültige Kontodaten geliefert (USER-DATA).',
      );
    }
  }

  @override
  Future<Tone3000Tone> getTone(int toneId) async {
    final response = await _get(
      Tone3000Config.apiBase.resolve('tones/$toneId'),
    );
    try {
      return Tone3000Tone.fromJson(
        _object(response, expectedKey: 'title', envelopeKey: 'tone'),
      );
    } catch (_) {
      throw const Tone3000ApiException(
        'TONE3000 hat ungültige Tone-Daten geliefert (TONE-DATA).',
      );
    }
  }

  @override
  Future<List<Tone3000Model>> listModels(int toneId) async {
    final uri = Tone3000Config.apiBase
        .resolve('models')
        .replace(
          queryParameters: {
            'tone_id': '$toneId',
            'page': '1',
            'page_size': '300',
          },
        );
    final response = await _get(uri);
    try {
      final rawModels = response['data'];
      if (rawModels is! List<Object?>) throw const FormatException();
      final models = <Tone3000Model>[];
      for (final item in rawModels) {
        if (item is! Map<Object?, Object?>) continue;
        try {
          final model = Tone3000Model.fromJson(
            item.cast<String, Object?>(),
            fallbackToneId: toneId,
          );
          if (Tone3000Config.isOfficialHttps(model.modelUrl)) {
            models.add(model);
          }
        } catch (_) {
          // An incomplete/unavailable model must not make the selected tone
          // unusable. Without a valid official URL it is never downloadable.
        }
      }
      return models;
    } catch (_) {
      throw const Tone3000ApiException(
        'TONE3000 hat ungültige Modelldaten geliefert (MODEL-DATA).',
      );
    }
  }

  // Single-object endpoints are documented as direct objects. Accepting a
  // `data` envelope as well makes the client tolerant of API gateway wrappers.
  Map<String, Object?> _object(
    Map<String, Object?> response, {
    required String expectedKey,
    required String envelopeKey,
  }) {
    if (response.containsKey(expectedKey)) return response;
    final data = response['data'];
    if (data is Map<Object?, Object?>) return data.cast<String, Object?>();
    final envelope = response[envelopeKey];
    if (envelope is Map<Object?, Object?>) {
      return envelope.cast<String, Object?>();
    }
    return response;
  }

  Future<Map<String, Object?>> _get(Uri uri) async {
    late final Tone3000HttpResponse response;
    try {
      final accessToken = await sessionManager.accessToken();
      response = await transport.send(
        method: 'GET',
        uri: uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
    } on Tone3000AuthException {
      rethrow;
    } catch (_) {
      throw const Tone3000ApiException(
        'TONE3000 ist derzeit nicht erreichbar (NETWORK).',
      );
    }
    if (response.statusCode == 401) {
      throw const Tone3000ReauthenticationRequired();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const Tone3000ApiException(
        'TONE3000-Daten konnten nicht geladen werden.',
      );
    }
    try {
      return response.json;
    } catch (_) {
      throw const Tone3000ApiException(
        'TONE3000 hat ungültige Daten geliefert.',
      );
    }
  }
}
