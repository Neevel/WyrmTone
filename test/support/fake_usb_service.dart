import 'dart:async';

import 'package:wyrmtone/models/usb_models.dart';
import 'package:wyrmtone/services/usb_service.dart';
import 'package:flutter/services.dart';

import 'fake_midi_receive_source.dart';

class FakeUsbService implements UsbService {
  @override
  final FakeMidiReceiveSource midiReceiveSource = FakeMidiReceiveSource();
  final StreamController<Map<Object?, Object?>> eventController =
      StreamController.broadcast();
  List<UsbDeviceInfo> devices = [];
  UsbConnectionStatus connection = const UsbConnectionStatus(isOpen: false);
  PlatformException? openError;
  int permissionRequests = 0;
  int closeCalls = 0;
  int openCalls = 0;
  String? lastPermissionDeviceName;
  String? lastOpenedDeviceName;
  List<MidiDeviceDiagnostic> midiDevices = [];
  MidiConnectionStatus midiConnection = const MidiConnectionStatus(
    isOpen: false,
  );
  int midiOpenCalls = 0;
  int midiCloseCalls = 0;

  @override
  Stream<Map<Object?, Object?>> get events => eventController.stream;

  final StreamController<Map<Object?, Object?>> namTransferProgressController = StreamController.broadcast();

  @override
  Stream<Map<Object?, Object?>> get namTransferProgress => namTransferProgressController.stream;

  @override
  Future<List<UsbDeviceInfo>> listUsbDevices() async => devices;

  @override
  Future<void> requestUsbPermission(String deviceName) async {
    permissionRequests++;
    lastPermissionDeviceName = deviceName;
  }

  @override
  Future<UsbConnectionStatus> openDevice(String deviceName) async {
    openCalls++;
    lastOpenedDeviceName = deviceName;
    if (openError case final error?) throw error;
    final device = devices.firstWhere((item) => item.deviceName == deviceName);
    connection = UsbConnectionStatus(
      isOpen: true,
      deviceName: deviceName,
      claimedInterfaceId: device.isMatriboxOneCandidate ? 3 : 0,
    );
    return connection;
  }

  @override
  Future<void> closeDevice() async {
    closeCalls++;
    connection = const UsbConnectionStatus(isOpen: false);
  }

  @override
  Future<UsbConnectionStatus> getConnectionStatus() async => connection;

  @override
  Future<List<MidiDeviceDiagnostic>> listMidiDevices() async => midiDevices;

  @override
  Future<MidiConnectionStatus> openMidiDevice(int deviceId) async {
    midiOpenCalls++;
    midiConnection = MidiConnectionStatus(isOpen: true, deviceId: deviceId);
    return midiConnection;
  }

  @override
  Future<void> closeMidiDevice() async {
    midiCloseCalls++;
    midiConnection = const MidiConnectionStatus(isOpen: false);
  }

  @override
  Future<MidiConnectionStatus> getMidiConnectionStatus() async =>
      midiConnection;

  /// V5B.1: every frame passed to [sendNamCloneTransferFrame], in call
  /// order, exactly as received -- for byte-integrity assertions in tests.
  final List<List<int>> sentNamCloneFrames = [];
  PlatformException? sendNamCloneTransferFrameError;

  @override
  Future<void> sendNamCloneTransferFrame(List<int> bytes) async {
    if (sendNamCloneTransferFrameError case final error?) throw error;
    sentNamCloneFrames.add(List<int>.unmodifiable(bytes));
  }

  /// V5B.2a/b: every session execution's frames, in call order.
  final List<List<List<int>>> namCloneSessionCalls = [];
  Map<Object?, Object?> namCloneSessionResult = const {'outcome': 'SUCCESS'};
  PlatformException? namCloneSessionError;

  /// Every [executeNamCloneTransferSession] invocation, whether it throws
  /// [namCloneSessionError] or succeeds -- unlike [namCloneSessionCalls]
  /// (which only records calls that got past the error check), this counts
  /// the method-channel call itself, for asserting "no automatic retry"
  /// even when every attempt fails before being recorded as sent.
  int namCloneSessionInvocations = 0;

  /// Product NAM transfer V1: when true (the default), [executeNamCloneTransferSession]
  /// emits one [namTransferProgress] event per frame before returning, simulating a
  /// real transfer's per-ACK progress -- set false for tests that drive
  /// [namTransferProgressController] manually (partial progress, out-of-order, etc.).
  bool autoEmitNamTransferProgress = true;

  @override
  Future<Map<Object?, Object?>> executeNamCloneTransferSession(List<List<int>> frames) async {
    namCloneSessionInvocations++;
    if (namCloneSessionError case final error?) throw error;
    namCloneSessionCalls.add(frames.map((f) => List<int>.unmodifiable(f)).toList());
    // A real session always takes real wall-clock time; a deliberate delay
    // here (independent of autoEmitNamTransferProgress) gives tests a real
    // window to emit progress events manually before this resolves, instead
    // of racing a same-microtask completion.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (autoEmitNamTransferProgress) {
      for (var i = 0; i < frames.length; i++) {
        namTransferProgressController.add({
          'confirmedCount': i + 1,
          'lastConfirmedBlock': i,
          'totalFrames': frames.length,
        });
        await Future<void>.microtask(() {});
      }
    }
    return namCloneSessionResult;
  }

  /// Product NAM transfer V1 hardware-certification fix: every
  /// [cancelNamCloneTransferSession] call, in order -- for asserting the
  /// product cancel action reaches the right, narrow native call.
  int cancelNamCloneTransferSessionCalls = 0;

  @override
  Future<void> cancelNamCloneTransferSession() async {
    cancelNamCloneTransferSessionCalls++;
  }

  Future<void> emit(Map<Object?, Object?> event) async {
    eventController.add(event);
    // Let the controller's asynchronous event handler and both service reads
    // complete without relying on timers controlled by the widget-test clock.
    for (var step = 0; step < 10; step++) {
      await Future<void>.microtask(() {});
    }
  }

  Future<void> dispose() async {
    await eventController.close();
    await namTransferProgressController.close();
    await midiReceiveSource.dispose();
  }
}

UsbDeviceInfo dnafxDevice({bool hasPermission = false}) => UsbDeviceInfo(
  deviceName: '/dev/bus/usb/001/002',
  vendorId: dnafxVendorId,
  productId: dnafxProductId,
  deviceClass: 0,
  deviceSubclass: 0,
  deviceProtocol: 0,
  configurationCount: 1,
  hasPermission: hasPermission,
  manufacturerName: hasPermission ? 'Harley Benton' : null,
  productName: hasPermission ? 'DNAfx GiT Core' : null,
  serialNumber: hasPermission ? 'not-for-log' : null,
  interfaces: const [
    UsbInterfaceInfo(
      id: 0,
      alternateSetting: 0,
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      endpoints: [
        UsbEndpointInfo(
          address: 0x81,
          direction: UsbDirection.input,
          type: UsbTransferType.interrupt,
          maxPacketSize: 64,
          interval: 1,
        ),
        UsbEndpointInfo(
          address: 0x02,
          direction: UsbDirection.output,
          type: UsbTransferType.interrupt,
          maxPacketSize: 64,
          interval: 1,
        ),
      ],
    ),
  ],
);

MidiDeviceDiagnostic matriboxMidiDevice() => const MidiDeviceDiagnostic(
  id: 7,
  name: 'SONICAKE MatriBox PRODUCT',
  manufacturer: 'SONICAKE AUDIO',
  product: 'SONICAKE MatriBox PRODUCT',
  usbDeviceName: '/dev/bus/usb/002/002',
  inputPortCount: 1,
  outputPortCount: 1,
  isMatribox: true,
  ports: [
    MidiPortDiagnostic(number: 0, direction: MidiPortDirection.input),
    MidiPortDiagnostic(number: 0, direction: MidiPortDirection.output),
  ],
);

UsbDeviceInfo matriboxDevice({bool hasPermission = false}) => UsbDeviceInfo(
  deviceName: '/dev/bus/usb/002/002',
  vendorId: matriboxVendorId,
  productId: matriboxProductId,
  deviceClass: 0,
  deviceSubclass: 0,
  deviceProtocol: 0,
  configurationCount: 1,
  hasPermission: hasPermission,
  manufacturerName: hasPermission ? 'SONICAKE' : null,
  productName: hasPermission ? 'Matribox' : null,
  serialNumber: hasPermission ? 'matribox-not-for-log' : null,
  interfaces: const [
    UsbInterfaceInfo(
      id: 1,
      alternateSetting: 1,
      interfaceClass: 1,
      interfaceSubclass: 2,
      interfaceProtocol: 32,
      endpoints: [
        UsbEndpointInfo(
          address: 0x82,
          direction: UsbDirection.input,
          type: UsbTransferType.isochronous,
          maxPacketSize: 192,
          interval: 1,
        ),
      ],
    ),
    UsbInterfaceInfo(
      id: 3,
      alternateSetting: 0,
      interfaceClass: 1,
      interfaceSubclass: 3,
      interfaceProtocol: 0,
      endpoints: [
        UsbEndpointInfo(
          address: 0x83,
          direction: UsbDirection.input,
          type: UsbTransferType.bulk,
          maxPacketSize: 64,
          interval: 0,
        ),
        UsbEndpointInfo(
          address: 0x03,
          direction: UsbDirection.output,
          type: UsbTransferType.bulk,
          maxPacketSize: 256,
          interval: 0,
        ),
      ],
    ),
  ],
);
