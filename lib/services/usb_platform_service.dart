import 'package:flutter/services.dart';

import '../models/usb_models.dart';
import '../midi/midi_receive_source.dart';
import 'usb_service.dart';

class MethodChannelUsbService implements UsbService {
  MethodChannelUsbService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    EventChannel? namTransferProgressChannel,
  }) : _methods = methodChannel ?? const MethodChannel(_methodChannelName),
       _events = eventChannel ?? const EventChannel(_eventChannelName),
       _namTransferProgress =
           namTransferProgressChannel ?? const EventChannel(_namTransferProgressChannelName);

  static const _methodChannelName = 'de.neevel.wyrmtone/usb_methods';
  static const _eventChannelName = 'de.neevel.wyrmtone/usb_events';
  static const _namTransferProgressChannelName = 'de.neevel.wyrmtone/nam_transfer_progress';

  final MethodChannel _methods;
  final EventChannel _events;
  final EventChannel _namTransferProgress;
  @override
  final MidiReceiveSource midiReceiveSource = MethodChannelMidiReceiveSource();

  @override
  Stream<Map<Object?, Object?>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .cast<Map<Object?, Object?>>();

  @override
  Stream<Map<Object?, Object?>> get namTransferProgress => _namTransferProgress
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .cast<Map<Object?, Object?>>();

  @override
  Future<List<UsbDeviceInfo>> listUsbDevices() async {
    final devices = await _methods.invokeListMethod<Object?>('listUsbDevices');
    return (devices ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(UsbDeviceInfo.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> requestUsbPermission(String deviceName) => _methods.invokeMethod(
    'requestUsbPermission',
    <String, Object?>{'deviceName': deviceName},
  );

  @override
  Future<UsbConnectionStatus> openDevice(String deviceName) async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'openDevice',
      <String, Object?>{'deviceName': deviceName},
    );
    return UsbConnectionStatus.fromMap(result ?? const {});
  }

  @override
  Future<void> closeDevice() => _methods.invokeMethod('closeDevice');

  @override
  Future<UsbConnectionStatus> getConnectionStatus() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'getConnectionStatus',
    );
    return UsbConnectionStatus.fromMap(result ?? const {});
  }

  @override
  Future<List<MidiDeviceDiagnostic>> listMidiDevices() async {
    final devices = await _methods.invokeListMethod<Object?>('listMidiDevices');
    return (devices ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(MidiDeviceDiagnostic.fromMap)
        .toList(growable: false);
  }

  @override
  Future<MidiConnectionStatus> openMidiDevice(int deviceId) async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'openMidiDevice',
      <String, Object?>{'deviceId': deviceId},
    );
    return MidiConnectionStatus.fromMap(result ?? const {});
  }

  @override
  Future<void> closeMidiDevice() => _methods.invokeMethod('closeMidiDevice');

  @override
  Future<MidiConnectionStatus> getMidiConnectionStatus() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'getMidiConnectionStatus',
    );
    return MidiConnectionStatus.fromMap(result ?? const {});
  }

  @override
  Future<void> sendNamCloneTransferFrame(List<int> bytes) => _methods.invokeMethod(
    'sendNamCloneTransferFrame',
    <String, Object?>{'bytes': Uint8List.fromList(bytes)},
  );

  @override
  Future<Map<Object?, Object?>> executeNamCloneTransferSession(List<List<int>> frames) async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'executeNamCloneTransferSession',
      <String, Object?>{'frames': [for (final f in frames) Uint8List.fromList(f)]},
    );
    return result ?? const {};
  }

  @override
  Future<void> cancelNamCloneTransferSession() => _methods.invokeMethod('cancelNamCloneTransferSession');
}
