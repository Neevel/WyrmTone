import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class Tone3000PkcePair {
  const Tone3000PkcePair({
    required this.verifier,
    required this.challenge,
    required this.state,
  });

  final String verifier;
  final String challenge;
  final String state;
}

class Tone3000PkceGenerator {
  Tone3000PkceGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Tone3000PkcePair generate() {
    final verifier = _randomBase64Url(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    return Tone3000PkcePair(
      verifier: verifier,
      challenge: challenge,
      state: _randomBase64Url(32),
    );
  }

  String _randomBase64Url(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
