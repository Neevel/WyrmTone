class Tone3000Config {
  Tone3000Config({required this.clientId, Uri? redirectUri})
    : redirectUri = redirectUri ?? Uri.parse('wyrmtone://oauth/callback');

  factory Tone3000Config.fromEnvironment() => Tone3000Config(
    clientId: const String.fromEnvironment('TONE3000_CLIENT_ID'),
  );

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
