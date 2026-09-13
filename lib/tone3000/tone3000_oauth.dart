import 'tone3000_browser.dart';
import 'tone3000_config.dart';
import 'tone3000_http.dart';
import 'tone3000_models.dart';
import 'tone3000_pkce.dart';
import 'tone3000_secure_store.dart';

class Tone3000AuthException implements Exception {
  const Tone3000AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Tone3000ReauthenticationRequired extends Tone3000AuthException {
  const Tone3000ReauthenticationRequired()
    : super('Die TONE3000-Anmeldung ist abgelaufen. Bitte erneut verbinden.');
}

class Tone3000OAuthResult {
  const Tone3000OAuthResult._({
    this.toneId,
    required this.canceled,
    required this.selectionMode,
  });
  const Tone3000OAuthResult.selected(int toneId, Tone3000SelectionMode mode)
    : this._(toneId: toneId, canceled: false, selectionMode: mode);
  const Tone3000OAuthResult.canceled(Tone3000SelectionMode mode)
    : this._(canceled: true, selectionMode: mode);

  final int? toneId;
  final bool canceled;
  final Tone3000SelectionMode selectionMode;
}

class Tone3000TokenClient {
  const Tone3000TokenClient({
    required this.config,
    required this.transport,
    required this.clock,
  });

  final Tone3000Config config;
  final Tone3000HttpTransport transport;
  final DateTime Function() clock;

  Future<Tone3000Tokens> exchangeCode({
    required String code,
    required String verifier,
  }) => _request({
    'grant_type': 'authorization_code',
    'code': code,
    'code_verifier': verifier,
    'redirect_uri': config.redirectUri.toString(),
    'client_id': config.clientId,
  });

  Future<Tone3000Tokens> refresh(String refreshToken) => _request({
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'client_id': config.clientId,
  });

  Future<Tone3000Tokens> _request(Map<String, String> fields) async {
    final response = await transport.send(
      method: 'POST',
      uri: Tone3000Config.tokenEndpoint,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: formEncode(fields),
    );
    if (response.statusCode == 400) {
      String? error;
      try {
        error = response.json['error'] as String?;
      } catch (_) {}
      if (error == 'invalid_grant') {
        throw const Tone3000ReauthenticationRequired();
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const Tone3000AuthException(
        'TONE3000 hat die Anmeldung nicht akzeptiert.',
      );
    }
    try {
      return Tone3000Tokens.fromTokenResponse(response.json, clock().toUtc());
    } catch (_) {
      throw const Tone3000AuthException(
        'TONE3000 hat eine ungültige Token-Antwort geliefert.',
      );
    }
  }
}

class Tone3000SessionManager {
  const Tone3000SessionManager({
    required this.store,
    required this.tokenClient,
    required this.clock,
  });

  final Tone3000SecureStore store;
  final Tone3000TokenClient tokenClient;
  final DateTime Function() clock;

  Future<bool> get hasSession async => await store.readTokens() != null;

  Future<String> accessToken() async {
    final current = await store.readTokens();
    if (current == null) throw const Tone3000ReauthenticationRequired();
    if (current.expiresAt.isAfter(
      clock().toUtc().add(const Duration(minutes: 1)),
    )) {
      return current.accessToken;
    }
    try {
      final refreshed = await tokenClient.refresh(current.refreshToken);
      await store.writeTokens(refreshed);
      return refreshed.accessToken;
    } on Tone3000ReauthenticationRequired {
      await store.clearTokens();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await store.clearTokens();
    await store.clearPendingAuthorization();
  }
}

class Tone3000OAuthService {
  Tone3000OAuthService({
    required this.config,
    required this.store,
    required this.browser,
    required this.tokenClient,
    Tone3000PkceGenerator? pkceGenerator,
    DateTime Function()? clock,
  }) : pkceGenerator = pkceGenerator ?? Tone3000PkceGenerator(),
       clock = clock ?? DateTime.now;

  final Tone3000Config config;
  final Tone3000SecureStore store;
  final Tone3000Browser browser;
  final Tone3000TokenClient tokenClient;
  final Tone3000PkceGenerator pkceGenerator;
  final DateTime Function() clock;

  Future<Uri> startSelectTone({
    Tone3000SelectionMode mode = Tone3000SelectionMode.ir,
  }) async {
    if (!config.isConfigured) {
      throw Tone3000AuthException(config.validationMessage!);
    }
    final pkce = pkceGenerator.generate();
    await store.writePendingAuthorization(
      Tone3000PendingAuthorization(
        verifier: pkce.verifier,
        state: pkce.state,
        createdAt: clock().toUtc(),
        selectionMode: mode,
      ),
    );
    final uri = Tone3000Config.authorizeEndpoint.replace(
      queryParameters: {
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri.toString(),
        'response_type': 'code',
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        'state': pkce.state,
        'prompt': 'select_tone',
        'format': mode == Tone3000SelectionMode.ir ? 'ir' : 'nam',
        if (mode == Tone3000SelectionMode.namA1) 'architecture': '1',
        'menubar': 'true',
      },
    );
    await browser.open(uri);
    return uri;
  }

  Future<Tone3000OAuthResult> handleCallback(Uri callback) async {
    if (callback.scheme != config.redirectUri.scheme ||
        callback.host != config.redirectUri.host ||
        callback.path != config.redirectUri.path) {
      throw const Tone3000AuthException('Ungültiger OAuth-Rücksprung.');
    }
    final pending = await store.readPendingAuthorization();
    try {
      if (pending == null ||
          clock().toUtc().difference(pending.createdAt) >
              const Duration(minutes: 10)) {
        throw const Tone3000AuthException(
          'Die TONE3000-Anfrage ist abgelaufen. Bitte erneut starten.',
        );
      }
      final returnedState = callback.queryParameters['state'];
      if (returnedState == null ||
          !_secureEquals(returnedState, pending.state)) {
        throw const Tone3000AuthException(
          'TONE3000-Rücksprung wegen falschem Sicherheitsstatus abgelehnt.',
        );
      }
      if (callback.queryParameters['canceled'] == 'true' ||
          callback.queryParameters['error'] == 'access_denied') {
        return Tone3000OAuthResult.canceled(pending.selectionMode);
      }
      final code = callback.queryParameters['code'];
      final toneId = int.tryParse(callback.queryParameters['tone_id'] ?? '');
      if (code == null || toneId == null) {
        throw const Tone3000AuthException(
          'TONE3000 hat keine vollständige Tonauswahl zurückgegeben.',
        );
      }
      final tokens = await tokenClient.exchangeCode(
        code: code,
        verifier: pending.verifier,
      );
      await store.writeTokens(tokens);
      return Tone3000OAuthResult.selected(toneId, pending.selectionMode);
    } finally {
      await store.clearPendingAuthorization();
    }
  }

  bool _secureEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
