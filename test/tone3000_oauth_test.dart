import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:wyrmtone/tone3000/tone3000_config.dart';
import 'package:wyrmtone/tone3000/tone3000_http.dart';
import 'package:wyrmtone/tone3000/tone3000_models.dart';
import 'package:wyrmtone/tone3000/tone3000_oauth.dart';
import 'package:wyrmtone/tone3000/tone3000_pkce.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tone3000_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 12);

  test('missing publishable client key has an understandable state', () {
    final config = Tone3000Config(clientId: '');
    expect(config.isConfigured, isFalse);
    expect(config.validationMessage, contains('TONE3000_CLIENT_ID'));
    expect(config.redirectUri.toString(), 'wyrmtone://oauth/callback');
  });

  test('PKCE verifier, S256 challenge and state are secure-shaped', () {
    final first = Tone3000PkceGenerator(random: Random(7)).generate();
    final second = Tone3000PkceGenerator(random: Random(8)).generate();
    final expected = base64Url
        .encode(sha256.convert(ascii.encode(first.verifier)).bytes)
        .replaceAll('=', '');

    expect(first.verifier.length, greaterThanOrEqualTo(43));
    expect(first.verifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(first.challenge, expected);
    expect(first.state, isNot(second.state));
  });

  test('successful callback validates state and stores tokens', () async {
    final store = MemoryTone3000SecureStore();
    final browser = FakeTone3000Browser();
    addTearDown(browser.dispose);
    final http = FakeTone3000HttpTransport()
      ..responses.add(
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: utf8.encode(
            '{"access_token":"access-value","refresh_token":"refresh-value","expires_in":3600}',
          ),
        ),
      );
    final config = Tone3000Config(clientId: 'publishable-test');
    final tokenClient = Tone3000TokenClient(
      config: config,
      transport: http,
      clock: () => now,
    );
    final oauth = Tone3000OAuthService(
      config: config,
      store: store,
      browser: browser,
      tokenClient: tokenClient,
      pkceGenerator: Tone3000PkceGenerator(random: Random(2)),
      clock: () => now,
    );

    final authorization = await oauth.startSelectTone();
    final result = await oauth.handleCallback(
      config.redirectUri.replace(
        queryParameters: {
          'code': 'short-code',
          'state': store.pending!.state,
          'tone_id': '83759',
        },
      ),
    );

    expect(authorization.queryParameters['prompt'], 'select_tone');
    expect(authorization.queryParameters['format'], 'ir');
    expect(authorization.queryParameters['code_challenge_method'], 'S256');
    expect(result.toneId, 83759);
    expect(store.tokens!.accessToken, 'access-value');
    expect(store.pending, isNull);
    expect(http.requests.single.body, contains('code_verifier='));
    expect(http.requests.single.body, isNot(contains('refresh-value')));
  });

  test('NAM selection reuses OAuth PKCE with NAM A1 parameters', () async {
    final store = MemoryTone3000SecureStore();
    final browser = FakeTone3000Browser();
    addTearDown(browser.dispose);
    final config = Tone3000Config(clientId: 'publishable-test');
    final oauth = Tone3000OAuthService(
      config: config,
      store: store,
      browser: browser,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: FakeTone3000HttpTransport(),
        clock: () => now,
      ),
      pkceGenerator: Tone3000PkceGenerator(random: Random(3)),
      clock: () => now,
    );

    final authorization = await oauth.startSelectTone(
      mode: Tone3000SelectionMode.namA1,
    );

    expect(authorization.queryParameters['prompt'], 'select_tone');
    expect(authorization.queryParameters['format'], 'nam');
    expect(authorization.queryParameters['architecture'], '1');
    expect(authorization.queryParameters['code_challenge_method'], 'S256');
    expect(store.pending!.selectionMode, Tone3000SelectionMode.namA1);
  });

  test('wrong state is rejected and pending state is erased', () async {
    final store = MemoryTone3000SecureStore()
      ..pending = Tone3000PendingAuthorization(
        verifier: 'v' * 50,
        state: 'expected',
        createdAt: now,
      );
    final config = Tone3000Config(clientId: 'publishable-test');
    final oauth = Tone3000OAuthService(
      config: config,
      store: store,
      browser: FakeTone3000Browser(),
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: FakeTone3000HttpTransport(),
        clock: () => now,
      ),
      clock: () => now,
    );

    await expectLater(
      oauth.handleCallback(
        config.redirectUri.replace(
          queryParameters: {'state': 'wrong', 'code': 'x', 'tone_id': '1'},
        ),
      ),
      throwsA(isA<Tone3000AuthException>()),
    );
    expect(store.pending, isNull);
  });

  test('OAuth cancellation is handled without token exchange', () async {
    final store = MemoryTone3000SecureStore()
      ..pending = Tone3000PendingAuthorization(
        verifier: 'v' * 50,
        state: 'expected',
        createdAt: now,
      );
    final http = FakeTone3000HttpTransport();
    final config = Tone3000Config(clientId: 'publishable-test');
    final oauth = Tone3000OAuthService(
      config: config,
      store: store,
      browser: FakeTone3000Browser(),
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );

    final result = await oauth.handleCallback(
      config.redirectUri.replace(
        queryParameters: {'state': 'expected', 'canceled': 'true'},
      ),
    );
    expect(result.canceled, isTrue);
    expect(http.requests, isEmpty);
    expect(store.pending, isNull);
  });

  test('expired access token is refreshed automatically', () async {
    final store = MemoryTone3000SecureStore()
      ..tokens = Tone3000Tokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );
    final http = FakeTone3000HttpTransport()
      ..responses.add(
        Tone3000HttpResponse(
          statusCode: 200,
          headers: const {},
          body: utf8.encode(
            '{"access_token":"new-access","refresh_token":"new-refresh","expires_in":7200}',
          ),
        ),
      );
    final config = Tone3000Config(clientId: 'publishable-test');
    final manager = Tone3000SessionManager(
      store: store,
      tokenClient: Tone3000TokenClient(
        config: config,
        transport: http,
        clock: () => now,
      ),
      clock: () => now,
    );

    expect(await manager.accessToken(), 'new-access');
    expect(store.tokens!.refreshToken, 'new-refresh');
    expect(http.requests.single.body, contains('grant_type=refresh_token'));
  });

  test(
    'invalid refresh token clears secure session without leaking tokens',
    () async {
      final store = MemoryTone3000SecureStore()
        ..tokens = Tone3000Tokens(
          accessToken: 'secret-access',
          refreshToken: 'secret-refresh',
          expiresAt: now.subtract(const Duration(seconds: 1)),
        );
      final http = FakeTone3000HttpTransport()
        ..responses.add(
          Tone3000HttpResponse(
            statusCode: 400,
            headers: const {},
            body: utf8.encode(
              '{"error":"invalid_grant","debug":"secret-access"}',
            ),
          ),
        );
      final config = Tone3000Config(clientId: 'publishable-test');
      final manager = Tone3000SessionManager(
        store: store,
        tokenClient: Tone3000TokenClient(
          config: config,
          transport: http,
          clock: () => now,
        ),
        clock: () => now,
      );

      Object? captured;
      try {
        await manager.accessToken();
      } catch (error) {
        captured = error;
      }
      expect(captured, isA<Tone3000ReauthenticationRequired>());
      expect('$captured', isNot(contains('secret-access')));
      expect('$captured', isNot(contains('secret-refresh')));
      expect(store.tokens, isNull);
    },
  );
}
