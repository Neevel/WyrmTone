import 'dart:typed_data';

/// Offline reader for Wireshark/USBPcap files (pcap or pcapng, link type 249).
///
/// Unlike `tool/matribox_capture_inspector.dart` (TShark, MIDI endpoints only)
/// this keeps EVERY endpoint, because the NAM transport is still unknown. It
/// only parses bytes it is given; it never opens a capture adapter or device.
enum UsbDirection { hostToDevice, deviceToHost }

const _typeNames = {0: 'isochronous', 1: 'interrupt', 2: 'control', 3: 'bulk'};

class UsbTransfer {
  const UsbTransfer({
    required this.index,
    required this.timestampUs,
    required this.direction,
    required this.endpoint,
    required this.transferType,
    required this.bus,
    required this.device,
    required this.payload,
  });

  final int index;
  final int? timestampUs;
  final UsbDirection direction;

  /// Endpoint address without the direction bit (0x83 -> 0x03).
  final int endpoint;
  final int transferType;
  final int bus;
  final int device;
  final Uint8List payload;

  String get typeName => _typeNames[transferType] ?? 'type$transferType';
  bool get isIsochronous => transferType == 0;
  String get endpointLabel =>
      '0x${(endpoint | (direction == UsbDirection.deviceToHost ? 0x80 : 0)).toRadixString(16).padLeft(2, '0')}';
}

class UsbCapture {
  const UsbCapture({
    required this.frameCount,
    required this.transfers,
    required this.emptyTransfers,
    required this.ignoredFrames,
  });

  final int frameCount;

  /// Only frames that carry payload bytes, in capture order.
  final List<UsbTransfer> transfers;
  final int emptyTransfers;
  final int ignoredFrames;
}

/// Throws [FormatException] for empty, truncated or corrupt files and for
/// link types other than USBPcap (249).
UsbCapture readUsbCapture(Uint8List bytes) {
  if (bytes.length < 24) {
    throw const FormatException('Capture file is too short.');
  }
  final magic = ByteData.sublistView(bytes).getUint32(0, Endian.little);
  final frames = magic == 0x0a0d0d0a
      ? _readPcapng(bytes)
      : _readPcap(bytes, magic);
  final transfers = <UsbTransfer>[];
  var empty = 0, ignored = 0;
  for (final frame in frames) {
    final parsed = _parseUsbPcap(
      frame.data,
      transfers.length,
      frame.timestampUs,
    );
    if (parsed == null) {
      ignored++;
    } else if (parsed.payload.isEmpty) {
      empty++;
    } else {
      transfers.add(parsed);
    }
  }
  return UsbCapture(
    frameCount: frames.length,
    transfers: List.unmodifiable(transfers),
    emptyTransfers: empty,
    ignoredFrames: ignored,
  );
}

class _Frame {
  const _Frame(this.timestampUs, this.data);
  final int? timestampUs;
  final Uint8List data;
}

const _linkTypeUsbPcap = 249;

List<_Frame> _readPcap(Uint8List bytes, int magic) {
  final (endian, nano) = switch (magic) {
    // The magic was read little endian: a1b2c3d4 means a little-endian file.
    0xa1b2c3d4 => (Endian.little, false),
    0xd4c3b2a1 => (Endian.big, false),
    0xa1b23c4d => (Endian.little, true),
    0x4d3cb2a1 => (Endian.big, true),
    _ => throw const FormatException('Unknown capture file magic.'),
  };
  final view = ByteData.sublistView(bytes);
  if (view.getUint32(20, endian) != _linkTypeUsbPcap) {
    throw const FormatException('Unsupported link type; only USBPcap (249).');
  }
  final frames = <_Frame>[];
  var offset = 24;
  while (offset < bytes.length) {
    if (offset + 16 > bytes.length) {
      throw FormatException('Truncated packet header at offset $offset.');
    }
    final seconds = view.getUint32(offset, endian);
    final fraction = view.getUint32(offset + 4, endian);
    final length = view.getUint32(offset + 8, endian);
    offset += 16;
    if (length > bytes.length - offset) {
      throw FormatException('Truncated packet data at offset $offset.');
    }
    frames.add(
      _Frame(
        seconds * 1000000 + (nano ? fraction ~/ 1000 : fraction),
        Uint8List.sublistView(bytes, offset, offset + length),
      ),
    );
    offset += length;
  }
  return frames;
}

List<_Frame> _readPcapng(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final frames = <_Frame>[];
  var endian = Endian.little;
  var interfaces = <({int linkType, double unitUs})>[];
  var offset = 0;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) {
      throw FormatException('Truncated block header at offset $offset.');
    }
    final type = view.getUint32(offset, endian); // SHB type is a palindrome
    if (type == 0x0a0d0d0a) {
      final order = view.getUint32(offset + 8, Endian.little);
      endian = switch (order) {
        0x1a2b3c4d => Endian.little,
        0x4d3c2b1a => Endian.big,
        _ => throw const FormatException('Invalid pcapng byte-order magic.'),
      };
      interfaces = [];
    }
    final total = view.getUint32(offset + 4, endian);
    if (total < 12 || total % 4 != 0 || offset + total > bytes.length) {
      throw FormatException('Corrupt or truncated block at offset $offset.');
    }
    final body = offset + 8;
    switch (type) {
      case 1: // Interface Description Block
        interfaces.add((
          linkType: view.getUint16(body, endian),
          unitUs: _timestampUnitUs(view, body + 8, offset + total - 4, endian),
        ));
      case 6: // Enhanced Packet Block
        final id = view.getUint32(body, endian);
        final captured = view.getUint32(body + 12, endian);
        if (id >= interfaces.length ||
            body + 20 + captured > offset + total - 4) {
          throw FormatException('Invalid packet block at offset $offset.');
        }
        if (interfaces[id].linkType != _linkTypeUsbPcap) {
          throw const FormatException(
            'Unsupported link type; only USBPcap (249).',
          );
        }
        final ticks =
            (view.getUint32(body + 4, endian) << 32) |
            view.getUint32(body + 8, endian);
        frames.add(
          _Frame(
            (ticks * interfaces[id].unitUs).round(),
            Uint8List.sublistView(bytes, body + 20, body + 20 + captured),
          ),
        );
    }
    offset += total;
  }
  return frames;
}

/// Microseconds per timestamp tick from the `if_tsresol` option (default 1 us).
double _timestampUnitUs(ByteData view, int start, int end, Endian endian) {
  var offset = start;
  while (offset + 4 <= end) {
    final code = view.getUint16(offset, endian);
    final length = view.getUint16(offset + 2, endian);
    if (code == 0) break;
    if (code == 9 && length >= 1 && offset + 5 <= end) {
      final resolution = view.getUint8(offset + 4);
      final exponent = resolution & 0x7f;
      final seconds = resolution & 0x80 == 0
          ? _pow(0.1, exponent)
          : _pow(0.5, exponent);
      return seconds * 1e6;
    }
    offset += 4 + ((length + 3) & ~3);
  }
  return 1;
}

double _pow(double base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}

/// USBPcap pseudo header (little endian, 27 bytes + optional extras).
/// Direction of the payload: a request (info bit 0 = 0) carries host data, a
/// completion (info bit 0 = 1) carries device data.
UsbTransfer? _parseUsbPcap(Uint8List frame, int index, int? timestampUs) {
  if (frame.length < 27) return null;
  final view = ByteData.sublistView(frame);
  final headerLength = view.getUint16(0, Endian.little);
  if (headerLength < 27 || headerLength > frame.length) return null;
  final info = view.getUint8(16);
  final transferType = view.getUint8(22);
  if (transferType == 254) return null; // IRP information, no USB data
  return UsbTransfer(
    index: index,
    timestampUs: timestampUs,
    direction: info & 1 == 0
        ? UsbDirection.hostToDevice
        : UsbDirection.deviceToHost,
    endpoint: view.getUint8(21) & 0x7f,
    transferType: transferType,
    bus: view.getUint16(17, Endian.little),
    device: view.getUint16(19, Endian.little),
    payload: Uint8List.sublistView(frame, headerLength),
  );
}
