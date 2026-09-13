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
