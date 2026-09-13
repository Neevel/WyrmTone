import 'dart:convert';

import '../services/local_persistence.dart';
import 'local_ir_record.dart';

class LocalIrRepository {
  LocalIrRepository(this._store);

  static const _key = 'tone3000_local_irs_v1';
  final StringStore _store;

  Future<List<LocalIrRecord>> load() async {
    final encoded = await _store.read(_key);
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(LocalIrRecord.fromJson)
        .toList(growable: false);
  }

  Future<void> save(List<LocalIrRecord> records) => _store.write(
    _key,
    jsonEncode(records.map((record) => record.toJson()).toList()),
  );

  Future<LocalIrRecord?> findByChecksum(String checksum) async {
    for (final record in await load()) {
      if (record.checksumSha256 == checksum) return record;
    }
    return null;
  }

  Future<void> upsert(LocalIrRecord record) async {
    final records = [...await load()];
    final index = records.indexWhere(
      (item) => item.tone3000ModelId == record.tone3000ModelId,
    );
    if (index < 0) {
      records.add(record);
    } else {
      records[index] = record;
    }
    await save(records);
  }
}
