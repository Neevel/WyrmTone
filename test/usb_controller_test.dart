import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/models/usb_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_usb_service.dart';

void main() {
  late FakeUsbService service;
  late UsbController controller;

  setUp(() {
    service = FakeUsbService();
    controller = UsbController(
      service,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
  });

  tearDown(() async {
    controller.dispose();
    await service.dispose();
  });

  test('starts with no device', () async {
    await controller.initialize();
    expect(controller.state, UsbConnectionState.noDevice);
    expect(controller.stateLabel, 'Kein unterstütztes Gerät verbunden');
  });

  test('unknown VID and PID remain unknown', () async {
    service.devices = [
      UsbDeviceInfo(
        deviceName: '/dev/unknown',
        vendorId: 0x1234,
        productId: 0x5678,
        deviceClass: 0,
        deviceSubclass: 0,
        deviceProtocol: 0,
        configurationCount: 1,
        hasPermission: false,
        interfaces: const [],
      ),
    ];
    await controller.initialize();
    expect(controller.state, UsbConnectionState.unknownDevice);
    expect(controller.stateLabel, 'Unbekanntes USB-Gerät erkannt');
  });

  test('represents not-requested and granted permission states', () async {
    service.devices = [dnafxDevice()];
    await controller.initialize();
    expect(controller.state, UsbConnectionState.permissionRequired);

    await controller.requestPermission();
    expect(service.permissionRequests, 1);

    service.devices = [dnafxDevice(hasPermission: true)];
    await service.emit({'type': 'permissionResult', 'granted': true});
    expect(controller.state, UsbConnectionState.detected);
  });

  test(
    'permission denial is understandable and retry remains possible',
    () async {
      service.devices = [dnafxDevice()];
      await controller.initialize();
      await service.emit({'type': 'permissionResult', 'granted': false});

      expect(controller.copyableLog, contains('USB-Berechtigung abgelehnt'));
      await controller.requestPermission();
      expect(service.permissionRequests, 1);
    },
  );

  test('attach and detach events refresh state', () async {
    await controller.initialize();
    service.devices = [dnafxDevice(hasPermission: true)];
    await service.emit({'type': 'attached'});
    expect(controller.state, UsbConnectionState.detected);

    service.devices = [];
    service.connection = const UsbConnectionStatus(isOpen: false);
    await service.emit({'type': 'detached'});
    expect(controller.state, UsbConnectionState.noDevice);
  });

  test('open error is logged and connection remains closed', () async {
    service.devices = [dnafxDevice(hasPermission: true)];
    service.openError = PlatformException(
      code: 'OPEN_FAILED',
      message: 'Interface konnte nicht beansprucht werden.',
    );
    await controller.initialize();
    await controller.open();

    expect(controller.connection.isOpen, isFalse);
    expect(controller.copyableLog, contains('nicht beansprucht'));
  });

  test('open and close safely release the logical connection', () async {
    service.devices = [dnafxDevice(hasPermission: true)];
    await controller.initialize();
    await controller.open();
    expect(controller.state, UsbConnectionState.open);

    await controller.close();
    expect(service.closeCalls, 1);
    expect(controller.state, UsbConnectionState.detected);
  });

  test('serial number never enters copyable logs', () async {
    service.devices = [dnafxDevice(hasPermission: true)];
    await controller.initialize();
    expect(controller.copyableLog, isNot(contains('not-for-log')));
  });

  test('Matribox permission and read-only interface 3 lifecycle', () async {
    service.devices = [matriboxDevice()];
    await controller.initialize();
    expect(controller.matriboxDevice, isNotNull);
    expect(controller.stateLabel, contains('Sonicake Matribox 1 erkannt'));

    await controller.open();
    expect(
      service.openCalls,
      0,
      reason: 'Ohne Berechtigung darf nicht geöffnet werden.',
    );

    await controller.requestPermission();
    expect(service.permissionRequests, 1);
    expect(service.lastPermissionDeviceName, '/dev/bus/usb/002/002');

    service.devices = [matriboxDevice(hasPermission: true)];
    await service.emit({'type': 'permissionResult', 'granted': true});
    await controller.open();
    expect(controller.connection.claimedInterfaceId, 3);
    expect(controller.copyableLog, contains('Bulk-IN 0x83'));
    expect(controller.copyableLog, contains('Keine Transfers gesendet'));

    await controller.open();
    expect(service.openCalls, 1, reason: 'Mehrfaches Öffnen wird verhindert.');
    await controller.close();
    expect(controller.state, UsbConnectionState.detected);
  });

  test('Matribox permission denial does not loop', () async {
    service.devices = [matriboxDevice()];
    await controller.initialize();
    await service.emit({'type': 'permissionResult', 'granted': false});
    expect(service.permissionRequests, 0);
    expect(controller.copyableLog, contains('USB-Berechtigung abgelehnt'));
  });

  test('closing an already closed connection remains safe', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    await controller.initialize();
    await controller.close();
    await controller.close();
    expect(service.closeCalls, 2);
    expect(controller.connection.isOpen, isFalse);
  });

  test('detach while Matribox is open closes logical state safely', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    await controller.initialize();
    await controller.open();
    service.devices = [];
    service.connection = const UsbConnectionStatus(isOpen: false);
    await service.emit({'type': 'detached'});
    expect(controller.connection.isOpen, isFalse);
    expect(controller.state, UsbConnectionState.noDevice);
  });

  test(
    'lists and opens Matribox through read-only Android MIDI path',
    () async {
      service.devices = [matriboxDevice(hasPermission: true)];
      service.midiDevices = [matriboxMidiDevice()];
      await controller.initialize();

      expect(controller.matriboxMidiDevice?.id, 7);
      await controller.openMidi();
      expect(service.midiOpenCalls, 1);
      expect(controller.midiConnection.isOpen, isTrue);
      expect(controller.copyableLog, contains('Keine Ports verbunden'));

      await controller.closeMidi();
      expect(service.midiCloseCalls, 1);
      expect(controller.midiConnection.isOpen, isFalse);
    },
  );

  test('native MIDI close event clears state after detach', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    service.midiDevices = [matriboxMidiDevice()];
    await controller.initialize();
    await controller.openMidi();

    service.midiConnection = const MidiConnectionStatus(isOpen: false);
    await service.emit({
      'type': 'midiConnectionClosed',
      'reason': 'usbDetached',
    });
    expect(controller.midiConnection.isOpen, isFalse);
    expect(controller.copyableLog, contains('nativ sicher geschlossen'));
  });

  test('Matribox Raw USB blocked while MIDI open; DNAfx unaffected', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    service.midiDevices = [matriboxMidiDevice()];
    await controller.initialize();
    await controller.openMidi();
    expect(controller.rawUsbAllowed, isFalse);
    await controller.open();
    expect(service.openCalls, 0);
    await controller.closeMidi();
    expect(controller.rawUsbAllowed, isTrue);
    service.devices = [dnafxDevice(hasPermission: true)];
    service.midiDevices = [];
    await controller.refresh();
    await controller.open();
    expect(service.openCalls, 1);
  });

  test('expected Matribox Raw USB failure reported once', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    service.openError = PlatformException(
      code: 'OPEN_FAILED',
      message: 'expected claim failure',
    );
    await controller.initialize();
    await controller.open();
    await controller.open();
    expect(service.openCalls, 1);
  });

  test('app pause stops output source and closes MidiDevice', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    service.midiDevices = [matriboxMidiDevice()];
    await controller.initialize();
    await controller.openMidi();
    await controller.capture.start();
    await controller.pauseMidi();
    expect(service.midiReceiveSource.active, isFalse);
    expect(service.midiCloseCalls, 1);
    expect(controller.midiConnection.isOpen, isFalse);
  });

  test('USB Detach during capture releases source', () async {
    service.devices = [matriboxDevice(hasPermission: true)];
    service.midiDevices = [matriboxMidiDevice()];
    await controller.initialize();
    await controller.openMidi();
    await controller.capture.start();
    service.devices = [];
    service.midiDevices = [];
    service.midiConnection = const MidiConnectionStatus(isOpen: false);
    await service.emit({'type': 'detached'});
    expect(service.midiReceiveSource.active, isFalse);
  });

  test(
    'switching DNAfx to Matribox closes before opening new device',
    () async {
      service.devices = [dnafxDevice(hasPermission: true)];
      await controller.initialize();
      await controller.open();
      await controller.close();
      service.devices = [matriboxDevice(hasPermission: true)];
      await controller.refresh();
      await controller.open();
      expect(service.closeCalls, 1);
      expect(service.lastOpenedDeviceName, '/dev/bus/usb/002/002');
      expect(controller.connection.claimedInterfaceId, 3);
    },
  );
}
