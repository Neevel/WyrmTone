import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'tone3000_models.dart';

abstract interface class Tone3000SecureStore {
  Future<Tone3000Tokens?> readTokens();
  Future<void> writeTokens(Tone3000Tokens tokens);
  Future<void> clearTokens();
  Future<Tone3000PendingAuthorization?> readPendingAuthorization();
  Future<void> writePendingAuthorization(
    Tone3000PendingAuthorization authorization,
  );
  Future<void> clearPendingAuthorization();
}

class FlutterTone3000SecureStore implements Tone3000SecureStore {
  FlutterTone3000SecureStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _tokensKey = 'tone3000_tokens_v1';
  static const _pendingKey = 'tone3000_pending_oauth_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<Tone3000Tokens?> readTokens() async {
    final encoded = await _storage.read(key: _tokensKey);
    if (encoded == null) return null;
    return Tone3000Tokens.fromJson(
      (jsonDecode(encoded) as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  @override
  Future<void> writeTokens(Tone3000Tokens tokens) =>
      _storage.write(key: _tokensKey, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clearTokens() => _storage.delete(key: _tokensKey);

  @override
  Future<Tone3000PendingAuthorization?> readPendingAuthorization() async {
    final encoded = await _storage.read(key: _pendingKey);
    if (encoded == null) return null;
    return Tone3000PendingAuthorization.fromJson(
      (jsonDecode(encoded) as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  @override
  Future<void> writePendingAuthorization(
    Tone3000PendingAuthorization authorization,
  ) => _storage.write(
    key: _pendingKey,
    value: jsonEncode(authorization.toJson()),
  );

  @override
  Future<void> clearPendingAuthorization() => _storage.delete(key: _pendingKey);
}
