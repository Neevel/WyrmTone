/// All Matribox models the product layer can talk about: the capture-
/// confirmed and read-confirmed entries of [MatriboxTransferCatalog] plus
/// every model of the local editor catalog (181 algorithms, categories
/// FX1/FX2/AMP/NR/CAB/EQ/MOD/DLY/RVB) built from it -- no second hard-coded
/// model list. Catalog-only models carry `observed` protocol evidence, so a
/// recommendation may pick them while the evidence gate keeps them unsent.
///
/// Semantic metadata (tags) lives in matribox_model_tags.dart and is kept
/// separate from the catalog.
library;

import 'device_catalog.dart';
import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';
import 'matribox_parameter_addressing.dart';
import 'matribox_transfer_catalog.dart';

class MatriboxModelLibrary {
  MatriboxModelLibrary._(this.models);

  final List<MatriboxTransferModel> models;

  /// Only the evidence-backed models (no editor catalog loaded).
  static final base = MatriboxModelLibrary._(MatriboxTransferCatalog.models);

  static const _categorySlots = <String, Set<MatriboxChainSlot>>{
    // FX1 and FX2 list the same 25 algorithms (identical codes).
    'FX1': {MatriboxChainSlot.fx1, MatriboxChainSlot.fx2},
    'FX2': {MatriboxChainSlot.fx1, MatriboxChainSlot.fx2},
    'AMP': {MatriboxChainSlot.amp},
    'NR': {MatriboxChainSlot.nr},
    'CAB': {MatriboxChainSlot.cab},
    'EQ': {MatriboxChainSlot.eq},
    'MOD': {MatriboxChainSlot.mod},
    'DLY': {MatriboxChainSlot.dly},
    'RVB': {MatriboxChainSlot.rvb},
  };

  static MatriboxParameterKind _kind(CatalogParameter p) {
    final control = p.data['xmlControlType'];
    if (control == 'Switch') return MatriboxParameterKind.flag;
    if ((p.minimum ?? 0) < 0) return MatriboxParameterKind.signedNumber;
    if (p.step != null) return MatriboxParameterKind.decimal;
    return MatriboxParameterKind.number;
  }

  /// One vendor parameter. The wire index comes ONLY from the manufacturer ID
  /// ([ParameterAddress]); an invalid ID BLOCKS the parameter, never idx.
  static MatriboxChainParameter _parameter(CatalogParameter p, Iterable<int?> algorithmIds, Set<int> conflictedIds) {
    final address = ParameterAddress.resolve(p.xmlId, algorithmIds);
    final conflict = conflictedIds.contains(p.xmlId);
    return MatriboxChainParameter(
      name: p.name ?? 'param${p.index}',
      wireIndex: conflict ? -1 : (address.wireIndex ?? -1),
      catalogIndex: p.index ?? 0,
      kind: _kind(p),
      minimum: (p.minimum ?? 0).toDouble(),
      maximum: (p.maximum ?? 99).toDouble(),
      defaultValue: (p.data['default'] as num?)?.toDouble(),
      xmlId: p.xmlId,
      controlType: p.controlType ?? 'Knob',
      bind: p.bind,
      subType: p.subType,
      menuIds: p.menuIds,
      step: p.step?.toDouble(),
      blockedReason: conflict ? _conflictReason : address.blockedReason,
    );
  }

  static const _conflictReason =
      'SLOT_DEFINITION_CONFLICT: der Hersteller definiert diesen Parameter in FX1 und FX2 unterschiedlich';

  static String _signature(CatalogParameter p) =>
      '${p.name}|${p.minimum?.toDouble()}|${p.maximum?.toDouble()}|${p.step?.toDouble()}|${p.controlType}|${p.bind}|${p.subType}|${[...p.menuIds]..sort()}';

  /// Manufacturer IDs of an algorithm code whose definition differs between
  /// the categories that list it (FX1 vs FX2): such a parameter is BLOCKED
  /// instead of silently taking one side (e.g. Tape Mod: "Output" vs "VOL").
  static Map<int, Set<int>> _conflicts(DevicePresetCatalog catalog) {
    final byCode = <int, List<CatalogAlgorithm>>{};
    for (final a in catalog.algorithms) {
      final code = a.code;
      if (code != null) byCode.putIfAbsent(code, () => []).add(a);
    }
    final result = <int, Set<int>>{};
    for (final entry in byCode.entries) {
      if (entry.value.length < 2) continue;
      final ids = {for (final a in entry.value) for (final p in a.parameters) if (p.xmlId != null) p.xmlId!};
      for (final id in ids) {
        final signatures = {
          for (final a in entry.value) a.parameters.where((p) => p.xmlId == id).map(_signature).join(';'),
        };
        if (signatures.length > 1) result.putIfAbsent(entry.key, () => {}).add(id);
      }
    }
    return result;
  }

  /// Adds the manufacturer metadata (ID, bind, control type, menus, step) to a
  /// hand-written capture entry. The capture-confirmed wire index must equal
  /// ID - 1 of the same-named vendor parameter; a mismatch BLOCKS the parameter.
  static MatriboxTransferModel _enriched(
    MatriboxTransferModel model,
    CatalogAlgorithm? vendor,
    Set<MatriboxChainSlot> vendorSlots,
    Set<int> conflictedIds,
  ) {
    if (vendor == null) return model;
    final ids = vendor.parameters.map((x) => x.xmlId);
    final parameters = <MatriboxChainParameter>[];
    for (final p in model.algorithm.parameters) {
      final v = vendor.parameters.where((x) => x.name == p.name).firstOrNull;
      if (v == null) {
        parameters.add(p);
        continue;
      }
      final address = ParameterAddress.resolve(v.xmlId, ids);
      final conflict = conflictedIds.contains(v.xmlId);
      final consistent = address.wireIndex == p.wireIndex && !conflict;
      parameters.add(
        MatriboxChainParameter(
          name: p.name,
          wireIndex: consistent ? p.wireIndex : -1,
          catalogIndex: p.catalogIndex,
          kind: p.kind,
          minimum: p.minimum,
          maximum: p.maximum,
          defaultValue: p.defaultValue,
          xmlId: v.xmlId,
          controlType: v.controlType ?? 'Knob',
          bind: v.bind,
          subType: v.subType,
          menuIds: v.menuIds,
          step: v.step?.toDouble(),
          blockedReason: consistent
              ? null
              : conflict
              ? _conflictReason
              : address.blockedReason ?? 'WIRE_MISMATCH: Capture-Index ${p.wireIndex} != Hersteller-ID - 1 (${address.wireIndex})',
        ),
      );
    }
    final a = model.algorithm;
    return MatriboxTransferModel(
      algorithm: MatriboxChainAlgorithm(
        id: a.id,
        name: a.name,
        code: a.code,
        // the manufacturer catalog lists this code in these categories too (e.g. Blues OD in FX1)
        slots: {...a.slots, ...vendorSlots},
        parameters: parameters,
        sendableInFullLive: a.sendableInFullLive,
        note: a.note,
      ),
      selectEvidence: model.selectEvidence,
      parameterEvidence: model.parameterEvidence,
      selectable: model.selectable,
      note: model.note,
    );
  }

  factory MatriboxModelLibrary.fromVendor(DevicePresetCatalog catalog) {
    final conflicts = _conflicts(catalog);
    CatalogAlgorithm? vendorFor(MatriboxTransferModel m) {
      final categories = {
        for (final entry in _categorySlots.entries)
          if (entry.value.intersection(m.algorithm.slots).isNotEmpty) entry.key,
      };
      return catalog.algorithms
          .where((a) => a.code == m.code && categories.contains(a.category))
          .firstOrNull;
    }

    Set<MatriboxChainSlot> vendorSlots(MatriboxTransferModel m) => {
      for (final a in catalog.algorithms)
        if (a.code == m.code && (a.name ?? '').isNotEmpty) ...?_categorySlots[a.category],
    };

    final known = {
      for (final m in MatriboxTransferCatalog.models)
        m.code: _enriched(m, vendorFor(m), vendorSlots(m), conflicts[m.code] ?? const {}),
    };
    final byCode = <int, MatriboxTransferModel>{...known};
    final order = <int>[...known.keys];
    for (final a in catalog.algorithms) {
      final code = a.code;
      final name = a.name;
      final slots = _categorySlots[a.category];
      if (code == null || name == null || name.isEmpty || slots == null) continue;
      if (byCode.containsKey(code)) continue;
      final algorithm = MatriboxChainAlgorithm(
        id: 'catalog:$name',
        name: name,
        code: code,
        slots: slots,
        parameters: [
          for (final p in a.parameters)
            _parameter(p, a.parameters.map((x) => x.xmlId), conflicts[code] ?? const {}),
        ],
      );
      byCode[code] = MatriboxTransferModel(
        algorithm: algorithm,
        selectEvidence: TransferProtocolEvidence.observed,
        parameterEvidence: TransferProtocolEvidence.observed,
        note: 'Nur lokaler Editor-Katalog.',
      );
      order.add(code);
    }
    return MatriboxModelLibrary._(List.unmodifiable([for (final c in order) byCode[c]!]));
  }

  Iterable<MatriboxTransferModel> forSlot(MatriboxChainSlot slot) =>
      models.where((m) => m.algorithm.slots.contains(slot));

  MatriboxTransferModel? byName(MatriboxChainSlot slot, String name) =>
      forSlot(slot).where((m) => m.name == name).firstOrNull;

  MatriboxTransferModel? byCode(MatriboxChainSlot slot, int code) =>
      forSlot(slot).where((m) => m.code == code).firstOrNull;
}
