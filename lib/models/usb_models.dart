import '../devices/device_profile.dart';

const int dnafxVendorId = 0x0483;
const int dnafxProductId = 0x5703;
const int matriboxVendorId = 0x84EF;
const int matriboxProductId = 0x0054;

enum SupportedDeviceType { dnafxGitCore, sonicakeMatriboxOne, unknown }

enum UsbConnectionState {
  noDevice('Kein unterstütztes Gerät verbunden'),
  unknownDevice('Unbekanntes USB-Gerät erkannt'),
  permissionRequired('USB-Berechtigung erforderlich'),
  detected('Unterstütztes Gerät erkannt'),
  open('Read-only-Verbindung geöffnet');

  const UsbConnectionState(this.label);
  final String label;
}

enum UsbDirection {
  input('IN'),
  output('OUT');

  const UsbDirection(this.label);
  final String label;
}

enum UsbTransferType {
  control('Control'),
  isochronous('Isochronous'),
  bulk('Bulk'),
  interrupt('Interrupt'),
  unknown('Unbekannt');

  const UsbTransferType(this.label);
  final String label;

  static UsbTransferType fromNative(String? value) {
    return values.where((item) => item.name == value).firstOrNull ?? unknown;
  }
}

class UsbEndpointInfo {
  const UsbEndpointInfo({
    required this.address,
    required this.direction,
    required this.type,
    required this.maxPacketSize,
    required this.interval,
  });

  factory UsbEndpointInfo.fromMap(Map<Object?, Object?> map) {
    return UsbEndpointInfo(
      address: _integer(map['address']),
      direction: map['direction'] == 'in'
          ? UsbDirection.input
          : UsbDirection.output,
      type: UsbTransferType.fromNative(map['type'] as String?),
      maxPacketSize: _integer(map['maxPacketSize']),
      interval: _integer(map['interval']),
    );
  }

  final int address;
  final UsbDirection direction;
  final UsbTransferType type;
  final int maxPacketSize;
  final int interval;

  String get hexadecimalAddress =>
      '0x${address.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

class UsbInterfaceInfo {
  const UsbInterfaceInfo({
    required this.id,
    required this.alternateSetting,
    required this.interfaceClass,
    required this.interfaceSubclass,
    required this.interfaceProtocol,
    required this.endpoints,
  });

  factory UsbInterfaceInfo.fromMap(Map<Object?, Object?> map) {
    return UsbInterfaceInfo(
      id: _integer(map['id']),
      alternateSetting: _integer(map['alternateSetting']),
      interfaceClass: _integer(map['class']),
      interfaceSubclass: _integer(map['subclass']),
      interfaceProtocol: _integer(map['protocol']),
      endpoints: _mapList(map['endpoints'])
          .map(UsbEndpointInfo.fromMap)
          .toList(growable: false),
    );
  }

  final int id;
  final int alternateSetting;
  final int interfaceClass;
  final int interfaceSubclass;
  final int interfaceProtocol;
  final List<UsbEndpointInfo> endpoints;
}

class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.deviceClass,
    required this.deviceSubclass,
    required this.deviceProtocol,
    required this.configurationCount,
    required this.hasPermission,
    required this.interfaces,
    this.manufacturerName,
    this.productName,
    this.serialNumber,
  });

  factory UsbDeviceInfo.fromMap(Map<Object?, Object?> map) {
    return UsbDeviceInfo(
      deviceName: map['deviceName'] as String? ?? 'Unbekanntes Gerät',
      vendorId: _integer(map['vendorId']),
      productId: _integer(map['productId']),
      deviceClass: _integer(map['deviceClass']),
      deviceSubclass: _integer(map['deviceSubclass']),
      deviceProtocol: _integer(map['deviceProtocol']),
      configurationCount: _integer(map['configurationCount']),
      hasPermission: map['hasPermission'] as bool? ?? false,
      manufacturerName: map['manufacturerName'] as String?,
      productName: map['productName'] as String?,
      serialNumber: map['serialNumber'] as String?,
      interfaces: _mapList(map['interfaces'])
          .map(UsbInterfaceInfo.fromMap)
          .toList(growable: false),
    );
  }

  final String deviceName;
  final int vendorId;
  final int productId;
  final int deviceClass;
  final int deviceSubclass;
  final int deviceProtocol;
  final int configurationCount;
  final bool hasPermission;
  final String? manufacturerName;
  final String? productName;
  final String? serialNumber;
  final List<UsbInterfaceInfo> interfaces;

  bool get isPossibleDnafx =>
      vendorId == dnafxVendorId && productId == dnafxProductId;
  bool get isMatriboxOneCandidate =>
      vendorId == matriboxVendorId && productId == matriboxProductId;
  SupportedDeviceType get supportedDeviceType => isPossibleDnafx
      ? SupportedDeviceType.dnafxGitCore
      : isMatriboxOneCandidate
      ? SupportedDeviceType.sonicakeMatriboxOne
      : SupportedDeviceType.unknown;
  bool get isSupported => supportedDeviceType != SupportedDeviceType.unknown;
  ToneDeviceAdapter? get deviceAdapter => switch (supportedDeviceType) {
    SupportedDeviceType.dnafxGitCore => const DnafxGitCoreAdapter(),
    SupportedDeviceType.sonicakeMatriboxOne => const MatriboxOneAdapter(),
    SupportedDeviceType.unknown => null,
  };
  int get endpointCount => interfaces.fold(
    0,
    (total, interface) => total + interface.endpoints.length,
  );
  String get vendorIdHex => _hex16(vendorId);
  String get productIdHex => _hex16(productId);
}

class UsbConnectionStatus {
  const UsbConnectionStatus({
    required this.isOpen,
    this.deviceName,
    this.claimedInterfaceId,
  });

  factory UsbConnectionStatus.fromMap(Map<Object?, Object?> map) {
    return UsbConnectionStatus(
      isOpen: map['isOpen'] as bool? ?? false,
      deviceName: map['deviceName'] as String?,
      claimedInterfaceId: map['claimedInterfaceId'] as int?,
    );
  }

  final bool isOpen;
  final String? deviceName;
  final int? claimedInterfaceId;
}

enum MidiPortDirection {
  input('Input'),
  output('Output');

  const MidiPortDirection(this.label);
  final String label;
}

class MidiPortDiagnostic {
  const MidiPortDiagnostic({
    required this.number,
    required this.direction,
    this.name,
  });

  factory MidiPortDiagnostic.fromMap(Map<Object?, Object?> map) {
    return MidiPortDiagnostic(
      number: _integer(map['number']),
      direction: map['direction'] == 'input'
          ? MidiPortDirection.input
          : MidiPortDirection.output,
      name: map['name'] as String?,
    );
  }

  final int number;
  final MidiPortDirection direction;
  final String? name;
}

class MidiDeviceDiagnostic {
  const MidiDeviceDiagnostic({
    required this.id,
    required this.inputPortCount,
    required this.outputPortCount,
    required this.ports,
    required this.isMatribox,
    this.name,
    this.manufacturer,
    this.product,
    this.usbDeviceName,
  });

  factory MidiDeviceDiagnostic.fromMap(Map<Object?, Object?> map) {
    return MidiDeviceDiagnostic(
      id: _integer(map['id']),
      name: map['name'] as String?,
      manufacturer: map['manufacturer'] as String?,
      product: map['product'] as String?,
      usbDeviceName: map['usbDeviceName'] as String?,
      inputPortCount: _integer(map['inputPortCount']),
      outputPortCount: _integer(map['outputPortCount']),
      isMatribox: map['isMatribox'] == true,
      ports: _mapList(map['ports'])
          .map(MidiPortDiagnostic.fromMap)
          .toList(growable: false),
    );
  }

  final int id;
  final String? name;
  final String? manufacturer;
  final String? product;
  final String? usbDeviceName;
  final int inputPortCount;
  final int outputPortCount;
  final List<MidiPortDiagnostic> ports;
  final bool isMatribox;

  String get displayName => product ?? name ?? 'MIDI-Gerät $id';
}

class MidiConnectionStatus {
  const MidiConnectionStatus({required this.isOpen, this.deviceId});

  factory MidiConnectionStatus.fromMap(Map<Object?, Object?> map) {
    return MidiConnectionStatus(
      isOpen: map['isOpen'] == true,
      deviceId: map['deviceId'] as int?,
    );
  }

  final bool isOpen;
  final int? deviceId;
}

String _hex16(int value) =>
    '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';

int _integer(Object? value) => value is int ? value : 0;

List<Map<Object?, Object?>> _mapList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value.whereType<Map<Object?, Object?>>().toList(growable: false);
}
