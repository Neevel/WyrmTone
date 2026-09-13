import 'package:flutter/services.dart';

abstract interface class LocalIrFileActions {
  Future<void> open(String localUri);
  Future<bool> export(String localUri, String fileName);
}

class PlatformLocalIrFileActions implements LocalIrFileActions {
  const PlatformLocalIrFileActions({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('de.neevel.wyrmtone/ir_files');

  final MethodChannel _channel;

  @override
  Future<void> open(String localUri) =>
      _channel.invokeMethod<void>('openLocalIr', {'uri': localUri});

  @override
  Future<bool> export(String localUri, String fileName) async =>
      await _channel.invokeMethod<bool>('exportLocalIr', {
        'uri': localUri,
        'fileName': fileName,
      }) ??
      false;
}
