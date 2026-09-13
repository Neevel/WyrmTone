import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/guitar_profile.dart';
import '../models/ir_metadata.dart';

abstract interface class StringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesStringStore implements StringStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

class ProfileRepository {
  ProfileRepository(this._store);
  static const _key = 'guitar_profiles_v1';
  final StringStore _store;

  Future<List<GuitarProfile>> load() async {
    final encoded = await _store.read(_key);
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(GuitarProfile.fromJson)
        .toList(growable: false);
  }

  Future<void> save(List<GuitarProfile> profiles) => _store.write(
    _key,
    jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
  );
}

class IrCatalogRepository {
  IrCatalogRepository(this._store);
  static const _key = 'ir_catalog_v1';
  final StringStore _store;

  Future<List<IrMetadata>> load() async {
    final encoded = await _store.read(_key);
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(IrMetadata.fromJson)
        .toList(growable: false);
  }

  Future<void> save(List<IrMetadata> entries) => _store.write(
    _key,
    jsonEncode(entries.map((entry) => entry.toJson()).toList()),
  );

  List<IrMetadata> merge(
    List<IrMetadata> existing,
    Iterable<IrMetadata> imported,
  ) {
    final byKey = <String, IrMetadata>{
      for (final entry in existing) entry.duplicateKey: entry,
    };
    for (final entry in imported) {
      byKey[entry.duplicateKey] = entry;
    }
    return byKey.values.toList(growable: false);
  }
}
