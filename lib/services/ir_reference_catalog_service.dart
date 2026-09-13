import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/ir_catalog_entry.dart';

abstract interface class IrReferenceCatalogService {
  Future<List<IrCatalogEntry>> load();
}

class FlutterIrReferenceCatalogService implements IrReferenceCatalogService {
  const FlutterIrReferenceCatalogService();

  static const assetPath = 'assets/catalog/ir_catalog.json';

  @override
  Future<List<IrCatalogEntry>> load() async {
    final decoded = jsonDecode(await rootBundle.loadString(assetPath));
    final root = (decoded as Map<Object?, Object?>).cast<String, Object?>();
    return (root['entries'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(IrCatalogEntry.fromJson)
        .toList(growable: false);
  }
}

class EmptyIrReferenceCatalogService implements IrReferenceCatalogService {
  const EmptyIrReferenceCatalogService();

  @override
  Future<List<IrCatalogEntry>> load() async => const [];
}
