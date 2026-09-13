import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/usb_models.dart';
import '../services/usb_service.dart';
import '../midi/midi_capture_controller.dart';

class UsbController extends ChangeNotifier {
  UsbController(this._service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    capture = MidiCaptureController(_service.midiReceiveSource, clock: _clock);
  }
  late final MidiCaptureController capture;
  bool rawMatriboxFailed = false;

  final UsbService _service;
  final DateTime Function() _clock;
  StreamSubscription<Map<Object?, Object?>>? _eventSubscription;
  List<UsbDeviceInfo> devices = const [];
  UsbConnectionStatus connection = const UsbConnectionStatus(isOpen: false);
  List<MidiDeviceDiagnostic> midiDevices = const [];
  MidiConnectionStatus midiConnection = const MidiConnectionStatus(
    isOpen: false,
  );
  final List<String> logs = [];
  bool busy = false;
  bool _disposed = false;

  UsbDeviceInfo? get supportedDevice {
    if (connection.deviceName case final connectedName?) {
      for (final device in devices) {
        if (device.deviceName == connectedName && device.isSupported) {
          return device;
        }
      }
    }
    for (final device in devices) {
      if (device.isSupported) return device;
    }
    return null;
  }

  UsbDeviceInfo? get dnafxDevice =>
      devices.where((device) => device.isPossibleDnafx).firstOrNull;

  UsbDeviceInfo? get matriboxDevice =>
      devices.where((device) => device.isMatriboxOneCandidate).firstOrNull;

  MidiDeviceDiagnostic? get matriboxMidiDevice =>
      midiDevices.where((device) => device.isMatribox).length == 1
      ? midiDevices.where((device) => device.isMatribox).first
      : null;

  bool get rawUsbAllowed =>
      !busy &&
      !(supportedDevice?.isMatriboxOneCandidate == true &&
          (midiConnection.isOpen || rawMatriboxFailed));

  void _syncCapture() => capture.updateConnection(
    detected: matriboxMidiDevice != null,
    opened:
        midiConnection.isOpen &&
        matriboxMidiDevice?.id == midiConnection.deviceId,
    name: matriboxMidiDevice?.displayName,
  );

  UsbConnectionState get state {
    if (connection.isOpen || midiConnection.isOpen) {
      return UsbConnectionState.open;
    }
    final device = supportedDevice;
    if (device == null) {
      return devices.isEmpty
          ? UsbConnectionState.noDevice
          : UsbConnectionState.unknownDevice;
    }
    return device.hasPermission
        ? UsbConnectionState.detected
        : UsbConnectionState.permissionRequired;
  }

  String get stateLabel {
    final device = supportedDevice;
    if (device == null) return state.label;
    final name = switch (device.supportedDeviceType) {
      SupportedDeviceType.dnafxGitCore => 'DNAfx GiT Core',
      SupportedDeviceType.sonicakeMatriboxOne => 'Sonicake Matribox 1',
      SupportedDeviceType.unknown => 'Unbekanntes USB-Gerät',
    };
    if (midiConnection.isOpen) {
      return '$name als MIDI-Gerät geöffnet (read-only)';
    }
    if (connection.isOpen) return '$name verbunden (read-only)';
    if (!device.hasPermission) {
      return '$name erkannt – USB-Berechtigung erforderlich';
    }
    return '$name erkannt';
  }

  Future<void> initialize() async {
    _eventSubscription = _service.events.listen(
      _handleEvent,
      onError: (Object error) => _log('USB-Ereignisfehler: $error'),
    );
    _log('Diagnose gestartet; es werden keine USB-Nutzdaten gesendet.');
    await refresh();
  }

  Future<void> refresh() => _guard(() async {
    devices = await _service.listUsbDevices();
    connection = await _service.getConnectionStatus();
    midiDevices = await _service.listMidiDevices();
    midiConnection = await _service.getMidiConnectionStatus();
    _syncCapture();
    _log('${devices.length} USB-Gerät(e) gefunden.');
    _log('${midiDevices.length} Android-MIDI-Gerät(e) gefunden.');
    if (supportedDevice case final device?) {
      final description = device.isMatriboxOneCandidate
          ? 'Matribox-Kandidat'
          : 'DNAfx GiT Core';
      _log(
        '$description ${device.vendorIdHex}:${device.productIdHex} erkannt; '
        'Berechtigung=${device.hasPermission ? 'erteilt' : 'fehlt'}.',
      );
      if (device.hasPermission) {
        _log('Hersteller- und Produktdeskriptoren gelesen.');
      }
    }
    if (matriboxMidiDevice case final midiDevice?) {
      _log(
        'Matribox dem MIDI-Gerät ${midiDevice.id} zugeordnet; '
        '${midiDevice.inputPortCount} Input- und '
        '${midiDevice.outputPortCount} Output-Port(s).',
      );
    }
  });

  Future<void> requestPermission() async {
    final device = supportedDevice;
    if (device == null) return;
    await _guard(() async {
      await _service.requestUsbPermission(device.deviceName);
      _log('USB-Berechtigung angefragt.');
    });
  }

  Future<void> open() async {
    final device = supportedDevice;
    if (device == null ||
        !device.hasPermission ||
        connection.isOpen ||
        !rawUsbAllowed) {
      return;
    }
    await _guard(() async {
      try {
        connection = await _service.openDevice(device.deviceName);
      } catch (_) {
        if (device.isMatriboxOneCandidate) rawMatriboxFailed = true;
        rethrow;
      }
      final interfaceDescription = device.isMatriboxOneCandidate
          ? 'Interface 3 mit Bulk-IN 0x83 und Bulk-OUT 0x03'
          : 'Interface 0 mit Interrupt-IN 0x81 und Interrupt-OUT 0x02';
      _log('$interfaceDescription gefunden.');
      _log(
        'Verbindung geöffnet; Interface '
        '${connection.claimedInterfaceId ?? '?'} beansprucht. Keine Transfers gesendet.',
      );
    });
  }

  Future<void> close() => _guard(() async {
    await _service.closeDevice();
    connection = const UsbConnectionStatus(isOpen: false);
    _log('Interface freigegeben und Verbindung geschlossen.');
  });

  Future<void> openMidi() async {
    final device = matriboxMidiDevice;
    if (device == null || midiConnection.isOpen) return;
    await _guard(() async {
      midiConnection = await _service.openMidiDevice(device.id);
      _syncCapture();
      _log(
        'Android-MIDI-Gerät ${device.id} read-only geöffnet. '
        'Keine Ports verbunden und keine MIDI-Daten gesendet.',
      );
    });
  }

  Future<void> closeMidi() => _guard(() async {
    await capture.stop();
    await _service.closeMidiDevice();
    midiConnection = const MidiConnectionStatus(isOpen: false);
    _syncCapture();
    _log('Android-MIDI-Gerät sicher geschlossen.');
  });

  Future<void> pauseMidi() async {
    await capture.interrupt();
    await _service.closeMidiDevice();
    midiConnection = const MidiConnectionStatus(isOpen: false);
    _syncCapture();
    if (!_disposed) notifyListeners();
  }

  String get copyableLog => logs.join('\n');

  Future<void> _handleEvent(Map<Object?, Object?> event) async {
    final type = event['type'];
    switch (type) {
      case 'attached':
        _log('USB-Gerät angeschlossen.');
        await refresh();
        return;
      case 'detached':
        rawMatriboxFailed = false;
        _log('USB-Gerät getrennt; Verbindung wurde sicher geschlossen.');
        await refresh();
        return;
      case 'permissionResult':
        final granted = event['granted'] == true;
        _log(
          granted
              ? 'USB-Berechtigung erteilt.'
              : 'USB-Berechtigung abgelehnt. Eine erneute Anfrage ist möglich.',
        );
        await refresh();
        return;
      case 'connectionClosed':
        connection = const UsbConnectionStatus(isOpen: false);
        _log('Native USB-Verbindung geschlossen.');
        notifyListeners();
        return;
      case 'midiDevicesChanged':
        _log('Android-MIDI-Geräteliste wurde aktualisiert.');
        await refresh();
        return;
      case 'midiConnectionClosed':
        midiConnection = const MidiConnectionStatus(isOpen: false);
        await capture.interrupt();
        _syncCapture();
        _log('Android-MIDI-Gerät wurde nativ sicher geschlossen.');
        notifyListeners();
        return;
      default:
        _log('Unbekanntes USB-Ereignis empfangen.');
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await action();
    } on PlatformException catch (error) {
      _log(error.message ?? 'USB-Fehler (${error.code}).');
    } catch (error) {
      _log('Unerwarteter Fehler: $error');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _log(String message) {
    if (_disposed) return;
    final timestamp = _clock().toLocal().toIso8601String();
    logs.add('[$timestamp] $message');
    if (logs.length > 300) logs.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    capture.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }
}
