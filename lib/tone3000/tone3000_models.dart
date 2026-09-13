class Tone3000Tokens {
  const Tone3000Tokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory Tone3000Tokens.fromTokenResponse(
    Map<String, Object?> json,
    DateTime now,
  ) => Tone3000Tokens(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresAt: now.add(Duration(seconds: (json['expires_in'] as num).round())),
  );

  factory Tone3000Tokens.fromJson(Map<String, Object?> json) => Tone3000Tokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
  );

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

class Tone3000PendingAuthorization {
  const Tone3000PendingAuthorization({
    required this.verifier,
    required this.state,
    required this.createdAt,
    this.selectionMode = Tone3000SelectionMode.ir,
  });

  factory Tone3000PendingAuthorization.fromJson(Map<String, Object?> json) =>
      Tone3000PendingAuthorization(
        verifier: json['verifier'] as String,
        state: json['state'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        selectionMode: Tone3000SelectionMode.values.byName(
          json['selectionMode'] as String? ?? Tone3000SelectionMode.ir.name,
        ),
      );

  final String verifier;
  final String state;
  final DateTime createdAt;
  final Tone3000SelectionMode selectionMode;

  Map<String, Object?> toJson() => {
    'verifier': verifier,
    'state': state,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'selectionMode': selectionMode.name,
  };
}

enum Tone3000SelectionMode { ir, namA1 }

class Tone3000User {
  const Tone3000User({required this.id, required this.username});

  factory Tone3000User.fromJson(Map<String, Object?> json) {
    final rawId = json['id'];
    final displayName = _nonEmptyString(json['display_name']);
    final username = _nonEmptyString(json['username']);
    if (rawId is! num && rawId is! String) {
      throw const FormatException('Invalid TONE3000 user id');
    }
    return Tone3000User(
      id: rawId!,
      username: displayName ?? username ?? 'TONE3000-Nutzer',
    );
  }

  // The public API documents a numeric ID, while OAuth-backed deployments may
  // expose an opaque string ID. The app never interprets or transmits this ID.
  final Object id;
  final String username;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class Tone3000Tone {
  const Tone3000Tone({
    required this.id,
    required this.title,
    required this.creatorName,
    required this.license,
    required this.format,
    required this.url,
    this.description,
    this.make,
    this.gearType,
    this.tags = const [],
  });

  factory Tone3000Tone.fromJson(Map<String, Object?> json) {
    final user = (json['user'] as Map<Object?, Object?>)
        .cast<String, Object?>();
    final displayName = user['display_name'] as String?;
    return Tone3000Tone(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      creatorName: displayName?.trim().isNotEmpty == true
          ? displayName!
          : user['username'] as String,
      license: json['license'] as String,
      format: json['format'] as String,
      url: Uri.parse(json['url'] as String),
      description: json['description'] as String?,
      make: _firstNamed(json['makes']),
      gearType: _enumLabel(json['gear']),
      tags: _names(json['tags']),
    );
  }

  final int id;
  final String title;
  final String creatorName;
  final String license;
  final String format;
  final Uri url;
  final String? description;
  final String? make;
  final String? gearType;
  final List<String> tags;

  bool get isImpulseResponse => format == 'ir';
  bool get isNam => format == 'nam';
}

class Tone3000Model {
  const Tone3000Model({
    required this.id,
    required this.toneId,
    required this.name,
    required this.sizeClass,
    required this.modelUrl,
    this.architectureVersion,
  });

  factory Tone3000Model.fromJson(
    Map<String, Object?> json, {
    int? fallbackToneId,
  }) {
    final modelUrl = Uri.parse(
      _nonEmptyString(json['model_url']) ??
          _nonEmptyString(json['download_url']) ??
          '',
    );
    final name =
        _nonEmptyString(json['name']) ??
        _nonEmptyString(json['file_name']) ??
        (modelUrl.pathSegments.isEmpty ? null : modelUrl.pathSegments.last) ??
        'TONE3000 IR';
    return Tone3000Model(
      id: _integer(json['id']),
      toneId: _integer(json['tone_id'], fallback: fallbackToneId),
      name: name,
      sizeClass:
          _enumLabel(json['size']) ??
          _nonEmptyString(json['size_class']) ??
          'IR',
      modelUrl: modelUrl,
      architectureVersion: _architecture(json['architecture_version']),
    );
  }

  final int id;
  final int toneId;
  final String name;
  final String sizeClass;
  final Uri modelUrl;
  final String? architectureVersion;
}

String? _architecture(Object? value) {
  if (value is num) return value.toInt().toString();
  return _nonEmptyString(value);
}

List<String> _names(Object? value) {
  if (value is! List<Object?>) return const [];
  return value
      .map((item) {
        if (item is String) return item;
        if (item is Map<Object?, Object?>) return _nonEmptyString(item['name']);
        return null;
      })
      .whereType<String>()
      .toList(growable: false);
}

String? _firstNamed(Object? value) => _names(value).firstOrNull;

int _integer(Object? value, {int? fallback}) {
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  if (fallback != null) return fallback;
  throw const FormatException('Invalid numeric identifier');
}

String? _enumLabel(Object? value) {
  final direct = _nonEmptyString(value);
  if (direct != null) return direct;
  if (value is Map<Object?, Object?>) {
    return _nonEmptyString(value['name']) ?? _nonEmptyString(value['value']);
  }
  return null;
}

class Tone3000Selection {
  const Tone3000Selection({required this.tone, required this.models});
  final Tone3000Tone tone;
  final List<Tone3000Model> models;
}
