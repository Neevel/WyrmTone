import 'package:flutter/services.dart';

abstract interface class PresetDocumentService {
  Future<bool> export(String json, String suggestedName);
  Future<String?> import();
}

class AndroidPresetDocumentService implements PresetDocumentService {
  const AndroidPresetDocumentService();
  static const _channel = MethodChannel('de.neevel.wyrmtone/preset_exchange');
  @override
  Future<bool> export(String json, String suggestedName) async =>
      await _channel.invokeMethod<bool>('export', {
        'json': json,
        'suggestedName': suggestedName,
      }) ??
      false;
  @override
  Future<String?> import() => _channel.invokeMethod<String>('import');
}
