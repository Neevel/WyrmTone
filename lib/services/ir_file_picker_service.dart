import 'package:flutter/services.dart';

import '../models/ir_metadata.dart';

abstract interface class IrFilePickerService {
  Future<PickedIrFolder?> pickWavFolder();
  Future<PickedIrFolder?> restorePersistedWavFolder();
}

class MethodChannelIrFilePicker implements IrFilePickerService {
  MethodChannelIrFilePicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('de.neevel.wyrmtone/ir_files');

  final MethodChannel _channel;

  @override
  Future<PickedIrFolder?> pickWavFolder() => _folder('pickWavFolder');

  @override
  Future<PickedIrFolder?> restorePersistedWavFolder() =>
      _folder('restorePersistedWavFolder');

  Future<PickedIrFolder?> _folder(String method) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(method);
    return value == null ? null : PickedIrFolder.fromMap(value);
  }
}

class EmptyIrFilePickerService implements IrFilePickerService {
  const EmptyIrFilePickerService();

  @override
  Future<PickedIrFolder?> pickWavFolder() async => null;

  @override
  Future<PickedIrFolder?> restorePersistedWavFolder() async => null;
}
