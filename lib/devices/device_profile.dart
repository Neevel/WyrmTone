enum TargetDeviceId { dnafxGitCore, matriboxOne }

enum CapabilityVerification { confirmed, unverified, notImplemented }

enum UsbClaimStrategy { normal, forceExistingDriver }

class UsbEndpointExpectation {
  const UsbEndpointExpectation({
    required this.address,
    required this.direction,
    required this.transferType,
    required this.maxPacketSize,
  });
  final int address;
  final String direction;
  final String transferType;
  final int maxPacketSize;
}

class UsbInterfaceExpectation {
  const UsbInterfaceExpectation({
    required this.id,
    required this.alternateSetting,
    required this.interfaceClass,
    required this.interfaceSubclass,
    required this.interfaceProtocol,
    required this.endpoints,
  });
  final int id;
  final int alternateSetting;
  final int interfaceClass;
  final int interfaceSubclass;
  final int interfaceProtocol;
  final List<UsbEndpointExpectation> endpoints;
}

class UsbDeviceProfile {
  const UsbDeviceProfile({
    required this.vendorId,
    required this.productId,
    required this.candidateLabel,
    required this.expectedInterface,
    required this.claimStrategy,
    required this.verificationStatus,
  });
  final int vendorId;
  final int productId;
  final String candidateLabel;
  final UsbInterfaceExpectation expectedInterface;
  final UsbClaimStrategy claimStrategy;
  final CapabilityVerification verificationStatus;
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.supportsFactoryAmpModels,
    required this.supportsCustomIr,
    required this.customIrSlotCount,
    required this.supportsNam,
    required this.supportedNamArchitectures,
    required this.supportsPresetTransfer,
    required this.supportsIrTransfer,
    required this.supportsNamTransfer,
    required this.connectionStatus,
    required this.verificationStatus,
  });
  final bool supportsFactoryAmpModels;
  final bool supportsCustomIr;
  final int? customIrSlotCount;
  final bool supportsNam;
  final Set<String> supportedNamArchitectures;
  final CapabilityVerification supportsPresetTransfer,
      supportsIrTransfer,
      supportsNamTransfer,
      connectionStatus,
      verificationStatus;
}

abstract interface class ToneDeviceAdapter {
  TargetDeviceId get id;
  String get displayName;
  DeviceCapabilities get capabilities;
  UsbDeviceProfile get usbProfile;
}

class DnafxGitCoreAdapter implements ToneDeviceAdapter {
  const DnafxGitCoreAdapter();
  @override
  TargetDeviceId get id => TargetDeviceId.dnafxGitCore;
  @override
  String get displayName => 'Harley Benton DNAfx GiT Core';
  @override
  UsbDeviceProfile get usbProfile => const UsbDeviceProfile(
    vendorId: 0x0483,
    productId: 0x5703,
    candidateLabel: 'DNAfx GiT Core',
    expectedInterface: UsbInterfaceExpectation(
      id: 0,
      alternateSetting: 0,
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      endpoints: [
        UsbEndpointExpectation(
          address: 0x81,
          direction: 'in',
          transferType: 'interrupt',
          maxPacketSize: 64,
        ),
        UsbEndpointExpectation(
          address: 0x02,
          direction: 'out',
          transferType: 'interrupt',
          maxPacketSize: 64,
        ),
      ],
    ),
    claimStrategy: UsbClaimStrategy.forceExistingDriver,
    verificationStatus: CapabilityVerification.confirmed,
  );
  @override
  DeviceCapabilities get capabilities => const DeviceCapabilities(
    supportsFactoryAmpModels: true,
    supportsCustomIr: true,
    customIrSlotCount: null,
    supportsNam: false,
    supportedNamArchitectures: {},
    supportsPresetTransfer: CapabilityVerification.notImplemented,
    supportsIrTransfer: CapabilityVerification.notImplemented,
    supportsNamTransfer: CapabilityVerification.notImplemented,
    connectionStatus: CapabilityVerification.confirmed,
    verificationStatus: CapabilityVerification.confirmed,
  );
}

class MatriboxOneAdapter implements ToneDeviceAdapter {
  const MatriboxOneAdapter();
  @override
  TargetDeviceId get id => TargetDeviceId.matriboxOne;
  @override
  String get displayName => 'Sonicake Matribox 1 / QME-50';
  @override
  UsbDeviceProfile get usbProfile => const UsbDeviceProfile(
    vendorId: 0x84EF,
    productId: 0x0054,
    candidateLabel: 'Sonicake Matribox 1 – Kandidat',
    expectedInterface: UsbInterfaceExpectation(
      id: 3,
      alternateSetting: 0,
      interfaceClass: 1,
      interfaceSubclass: 3,
      interfaceProtocol: 0,
      endpoints: [
        UsbEndpointExpectation(
          address: 0x83,
          direction: 'in',
          transferType: 'bulk',
          maxPacketSize: 64,
        ),
        UsbEndpointExpectation(
          address: 0x03,
          direction: 'out',
          transferType: 'bulk',
          maxPacketSize: 256,
        ),
      ],
    ),
    claimStrategy: UsbClaimStrategy.normal,
    verificationStatus: CapabilityVerification.unverified,
  );
  @override
  DeviceCapabilities get capabilities => const DeviceCapabilities(
    supportsFactoryAmpModels: true,
    supportsCustomIr: true,
    customIrSlotCount: 15,
    supportsNam: true,
    supportedNamArchitectures: {'A1'},
    // Preset PARAMETERS: productively transferable for User P01 (see docs/DIRECT_PRESET_TRANSFER.md).
    // IR/NAM FILE upload is a different protocol: selecting a User IR slot, or the device supporting
    // NAM at all, is not evidence of a file-upload command -- both stay notImplemented until that
    // is belegt (see docs/IR_NAM_DEVICE_TRANSFER.md).
    supportsPresetTransfer: CapabilityVerification.confirmed,
    supportsIrTransfer: CapabilityVerification.notImplemented,
    supportsNamTransfer: CapabilityVerification.notImplemented,
    connectionStatus: CapabilityVerification.unverified,
    verificationStatus: CapabilityVerification.unverified,
  );
}

const toneDeviceAdapters = <ToneDeviceAdapter>[
  DnafxGitCoreAdapter(),
  MatriboxOneAdapter(),
];
