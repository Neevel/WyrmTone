import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'canonical_preset.dart';
import 'preset_validation.dart';
import 'protocol_evidence.dart';

abstract final class PresetPrivacy {
  static final _unsafe = RegExp(
    r'(?:[a-zA-Z]:[\\/]|(?:file|content)://|/(?:storage|sdcard|data|dev|Users|home)/|t3k_|bearer\s|access_token|refresh_token|client_secret|oauth_token)',
    caseSensitive: false,
  );
  static void check(Object? value) {
    if (value is String && _unsafe.hasMatch(value)) {
      throw const FormatException(
        'Private paths or credentials are not permitted in preset files.',
      );
    }
    if (value is List) {
      for (final item in value) {
        check(item);
      }
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (RegExp(
          r'^(?:serialNumber|token|rawMidi|bytes|base64|binary|localUri|uri)$',
          caseSensitive: false,
        ).hasMatch(entry.key.toString())) {
          throw const FormatException(
            'Sensitive or binary fields are not permitted.',
          );
        }
        check(entry.value);
      }
    }
  }
}

String presetHash(CanonicalPreset preset) =>
    sha256.convert(utf8.encode(canonicalJson(preset.toJson()))).toString();

class PresetExportService {
  const PresetExportService(this.validator);
  final PresetValidator validator;
  String export(CanonicalPreset preset, {required DateTime exportedAt}) {
    final validation = validator.validate(preset);
    if (!validation.exportAllowed) {
      throw const FormatException('Preset validation failed; export blocked.');
    }
    final data = {
      'schemaVersion': 1,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'application': {'name': 'WyrmTone', 'format': 'wyrmtone.json'},
      'targetDevice': preset.targetDevice,
      'preset': preset.toJson(),
      'validation': validation.toJson(),
      'evidence': ProtocolEvidenceRegistry.capabilities
          .map((c) => c.toJson())
          .toList(),
      'localAssets': [
        if (preset.ir != null) preset.ir!.toJson(),
        if (preset.nam != null) preset.nam!.toJson(),
      ],
      'sourceAttribution': [
        'WyrmTone offline recommendation; not a device backup.',
        if (preset.ir != null)
          {'creator': preset.ir!.creator, 'license': preset.ir!.license},
        if (preset.nam != null)
          {'creator': preset.nam!.creator, 'license': preset.nam!.license},
      ],
    };
    PresetPrivacy.check(data);
    return canonicalJson(data, pretty: true);
  }

  CanonicalPreset import(String text) {
    try {
      if (utf8.encode(text).length > 3 * 1024 * 1024) {
        throw const FormatException('Preset file exceeds size limit.');
      }
      final data = objectMap(jsonDecode(text));
      PresetPrivacy.check(data);
      if (data['schemaVersion'] != 1 ||
          objectMap(data['application'])['name'] != 'WyrmTone') {
        throw const FormatException(
          'Unknown preset exchange schema; no migration available.',
        );
      }
      DateTime.parse(requiredText(data, 'exportedAt'));
      final preset = CanonicalPreset.fromJson(objectMap(data['preset']));
      if (data['targetDevice'] != preset.targetDevice) {
        throw const FormatException('Conflicting target devices.');
      }
      if (!validator.validate(preset).exportAllowed) {
        throw const FormatException('Imported preset is invalid.');
      }
      // Embedded validation/evidence are never trusted as current permissions.
      return preset;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid WyrmTone preset file.');
    }
  }
}
