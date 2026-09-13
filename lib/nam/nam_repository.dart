import 'dart:convert';

import '../services/local_persistence.dart';
import 'local_nam_capture.dart';

class NamRepository {
  const NamRepository(this.store);
  static const key = 'local_nam_captures_v1';
  final StringStore store;
  Future<List<LocalNamCapture>> load() async {
    final value = await store.read(key);
    if (value == null) return [];
    return (jsonDecode(value) as List<Object?>)
        .map(
          (e) => LocalNamCapture.fromJson(
            (e as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<void> save(List<LocalNamCapture> items) =>
      store.write(key, jsonEncode(items.map((e) => e.toJson()).toList()));
  Future<void> upsert(LocalNamCapture capture) async {
    final items = await load();
    final i = items.indexWhere((e) => e.localId == capture.localId);
    if (i < 0) {
      items.add(capture);
    } else {
      items[i] = capture;
    }
    await save(items);
  }

  Future<void> remove(String id) async =>
      save((await load()).where((e) => e.localId != id).toList());
}
