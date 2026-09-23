class Tone3000Config {
  Tone3000Config({required this.clientId, Uri? redirectUri})
    : redirectUri = redirectUri ?? Uri.parse('wyrmtone://oauth/callback');

  /// The app's own PUBLIC OAuth client id (a publishable identifier, comparable to a client-side API
  /// key -- never a secret, never a token). It ships as the default in every normal
  /// `flutter build apk`/`flutter build apk --release` so TONE3000 works out of the box;
  /// `--dart-define=TONE3000_CLIENT_ID=...` still overrides it when set to a non-empty value.
  static const _publicDefaultClientId = 't3k_pub_a1E-BjubeO92VsSYMyvzQ1Ry4s03ZXrh';

  factory Tone3000Config.fromEnvironment() => Tone3000Config(
    clientId: _resolveClientId(const String.fromEnvironment('TONE3000_CLIENT_ID')),
  );

  static String _resolveClientId(String defined) => defined.trim().isEmpty ? _publicDefaultClientId : defined;

  static final authorizeEndpoint = Uri.https(
    'www.tone3000.com',
    '/api/v1/oauth/authorize',
  );
  static final tokenEndpoint = Uri.https(
    'www.tone3000.com',
    '/api/v1/oauth/token',
  );
  static final apiBase = Uri.https('www.tone3000.com', '/api/v1/');

  final String clientId;
  final Uri redirectUri;

  bool get isConfigured => clientId.trim().isNotEmpty;

  String? get validationMessage => isConfigured
      ? null
      : 'TONE3000 ist nicht konfiguriert. Baue die App mit '
            '--dart-define=TONE3000_CLIENT_ID=<Publishable Key>.';

  static bool isOfficialHttps(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'tone3000.com' || uri.host.endsWith('.tone3000.com'));
}
