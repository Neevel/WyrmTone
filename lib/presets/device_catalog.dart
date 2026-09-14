import 'canonical_preset.dart';
import 'protocol_evidence.dart';

class CatalogParameter {
  CatalogParameter(Map<String, Object?> data) : data = Map.unmodifiable(data);
  final Map<String, Object?> data;
  String? get name => data['name'] as String?;
  int? get index => data['index'] as int?;
  num? get minimum => data['minimum'] as num?;
  num? get maximum => data['maximum'] as num?;
  num? get step => data['step'] as num?;
}

class CatalogAlgorithm {
  CatalogAlgorithm(Map<String, Object?> data)
    : data = Map.unmodifiable(data),
      parameters = List.unmodifiable(
        (data['parameters'] as List).map((p) => CatalogParameter(objectMap(p))),
      );
  final Map<String, Object?> data;
  final List<CatalogParameter> parameters;
  String? get name => data['name'] as String?;
  String? get category => data['category'] as String?;
  int? get code => data['code'] as int?;
  CatalogParameter? parameter(String name) =>
      parameters.where((p) => p.name == name).firstOrNull;
}

class DevicePresetCatalog {
  DevicePresetCatalog(Map<String, Object?> data)
    : algorithms = List.unmodifiable(
        (data['algorithms'] as List).map((a) => CatalogAlgorithm(objectMap(a))),
      );
  final List<CatalogAlgorithm> algorithms;
  CatalogAlgorithm? find(String? name) {
    final matches = algorithms.where((a) => a.name == name).toList();
    return matches.length == 1 ? matches.single : null;
  }

  CatalogAlgorithm? byCode(int code) {
    final matches = algorithms.where((a) => a.code == code).toList();
    return matches.length == 1 ? matches.single : null;
  }

  EvidenceLevel indexEvidence(
    CatalogAlgorithm algorithm,
    CatalogParameter parameter,
  ) {
    if (algorithm.code == 0x07000047 &&
        parameter.name == 'Gain' &&
        parameter.index == 0) {
      return EvidenceLevel.confirmed;
    }
    if (algorithm.code == 0x07000059 &&
        ((parameter.name == 'Bass' && parameter.index == 3) ||
            (parameter.name == 'Middle' && parameter.index == 4) ||
            (parameter.name == 'Gain' && parameter.index == 0))) {
      return EvidenceLevel.correlated;
    }
    return EvidenceLevel.observed;
  }
}
