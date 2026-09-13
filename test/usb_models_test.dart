import 'package:wyrmtone/models/usb_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recognizes both supported device IDs and leaves unknown IDs unknown',
    () {
      expect(
        _deviceWithIds(dnafxVendorId, dnafxProductId).supportedDeviceType,
        SupportedDeviceType.dnafxGitCore,
      );
      expect(
        _deviceWithIds(matriboxVendorId, matriboxProductId).supportedDeviceType,
        SupportedDeviceType.sonicakeMatriboxOne,
      );
      expect(
        _deviceWithIds(0x1234, 0x5678).supportedDeviceType,
        SupportedDeviceType.unknown,
      );
    },
  );
  test('maps complete native USB data into typed models', () {
    final device = UsbDeviceInfo.fromMap({
      'deviceName': '/dev/usb/1',
      'vendorId': 0x0483,
      'productId': 0x5703,
      'deviceClass': 0,
      'deviceSubclass': 1,
      'deviceProtocol': 2,
      'configurationCount': 1,
      'hasPermission': true,
      'manufacturerName': 'Harley Benton',
      'productName': 'DNAfx GiT Core',
      'serialNumber': 'secret',
      'interfaces': [
        {
          'id': 0,
          'alternateSetting': 0,
          'class': 3,
          'subclass': 0,
          'protocol': 0,
          'endpoints': [
            {
              'address': 0x81,
              'direction': 'in',
              'type': 'bulk',
              'maxPacketSize': 64,
              'interval': 2,
            },
          ],
        },
      ],
    });

    expect(device.isPossibleDnafx, isTrue);
    expect(device.vendorIdHex, '0x0483');
    expect(device.productIdHex, '0x5703');
    expect(device.endpointCount, 1);
    expect(
      device.interfaces.single.endpoints.single.direction,
      UsbDirection.input,
    );
    expect(
      device.interfaces.single.endpoints.single.type,
      UsbTransferType.bulk,
    );
    expect(
      device.interfaces.single.endpoints.single.hexadecimalAddress,
      '0x81',
    );
  });

  test('maps missing optional values and unknown transfer type safely', () {
    final endpoint = UsbEndpointInfo.fromMap({
      'address': 1,
      'direction': 'out',
      'type': 'future-type',
    });

    expect(endpoint.direction, UsbDirection.output);
    expect(endpoint.type, UsbTransferType.unknown);
    expect(endpoint.maxPacketSize, 0);
  });
}

UsbDeviceInfo _deviceWithIds(int vendorId, int productId) => UsbDeviceInfo(
  deviceName: '/dev/test',
  vendorId: vendorId,
  productId: productId,
  deviceClass: 0,
  deviceSubclass: 0,
  deviceProtocol: 0,
  configurationCount: 1,
  hasPermission: false,
  interfaces: const [],
);
