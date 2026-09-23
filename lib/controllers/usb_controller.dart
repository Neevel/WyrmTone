import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/usb_models.dart';
import '../services/usb_service.dart';
import '../midi/midi_capture_controller.dart';

/// The one connection-state vocabulary the whole app reads, derived from the existing device/MIDI
/// state below (never a second, screen-local notion of "connected"). `detected` and `connected`
/// are kept alongside the milestone's minimum five states because the diagnostics screen already
/// distinguishes "seen, no permission yet" from "seen, permission granted, not opened yet".
enum DeviceConnectionState { disconnected, connecting, permissionRequired, detected, connected, error }

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

  /// Auto-connect: identify + request permission + open the MIDI transport for a detected
  /// Matribox 1 on its own, without the user pressing a button. It NEVER writes anything -- opening
  /// the MIDI transport is the same read-only [openMidi] a manual tap would call, and the raw-USB
  /// diagnostic path is never auto-opened. Settings → Geräte can turn this off.
  bool autoConnect = true;
  final Set<String> _autoPermissionRequestedFor = {};
  bool _autoMidiOpenAttempted = false;

  void setAutoConnect(bool value) {
    if (autoConnect == value) return;
    autoConnect = value;
    if (!value) {
      _autoPermissionRequestedFor.clear();
      _autoMidiOpenAttempted = false;
    }
    notifyListeners();
  }

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

  /// The unified connection state for the primary receiving device (Matribox 1) only -- other
  /// supported devices (DNAfx GiT Core) are diagnosed but are not part of auto-connect or the
  /// unified device-settings UI.
  DeviceConnectionState get connectionState {
    if (midiConnection.isOpen || connection.isOpen) return DeviceConnectionState.connected;
    if (rawMatriboxFailed) return DeviceConnectionState.error;
    final device = matriboxDevice;
    if (device == null) return DeviceConnectionState.disconnected;
    if (!device.hasPermission) return DeviceConnectionState.permissionRequired;
    if (busy) return DeviceConnectionState.connecting;
    return DeviceConnectionState.detected;
  }

  /// Short, non-technical status for a global chip ("Matribox 1 · Verbunden").
  String get primaryDeviceStatusLabel => switch (connectionState) {
    DeviceConnectionState.connected => 'Matribox 1 · Verbunden',
    DeviceConnectionState.connecting => 'Matribox 1 · Verbinde …',
    DeviceConnectionState.permissionRequired => 'Matribox 1 · Verbindung erlauben',
    DeviceConnectionState.detected => 'Matribox 1 · Erkannt',
    DeviceConnectionState.error => 'Matribox 1 · Verbindung fehlgeschlagen',
    DeviceConnectionState.disconnected => 'Keine Matribox verbunden',
  };

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
    await _maybeAutoConnect();
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

  /// Auto-connect, one step at a time, after every state refresh: request permission for a
  /// just-seen Matribox 1 once, then open its MIDI transport once permission is granted. Both
  /// steps run through [_guard], so a step already in progress or a manual action in flight makes
  /// this a no-op instead of a second parallel connection. Never touches raw USB and never selects,
  /// reads or writes a preset.
  Future<void> _maybeAutoConnect() async {
    if (!autoConnect || busy || _disposed) return;
    final device = matriboxDevice;
    if (device == null) {
      _autoPermissionRequestedFor.clear();
      _autoMidiOpenAttempted = false;
      return;
    }
    if (!device.hasPermission) {
      if (!_autoPermissionRequestedFor.add(device.deviceName)) return;
      await _guard(() async {
        await _service.requestUsbPermission(device.deviceName);
        _log('USB-Berechtigung automatisch angefragt (Matribox 1, Auto-Connect).');
      });
      return;
    }
    if (matriboxMidiDevice == null || midiConnection.isOpen || _autoMidiOpenAttempted) return;
    _autoMidiOpenAttempted = true;
    await openMidi();
  }

  Future<void> _handleEvent(Map<Object?, Object?> event) async {
    final type = event['type'];
    switch (type) {
      case 'attached':
        _log('USB-Gerät angeschlossen.');
        await refresh();
        await _maybeAutoConnect();
        return;
      case 'detached':
        rawMatriboxFailed = false;
        _log('USB-Gerät getrennt; Verbindung wurde sicher geschlossen.');
        await refresh();
        await _maybeAutoConnect();
        return;
      case 'permissionResult':
        final granted = event['granted'] == true;
        _log(
          granted
              ? 'USB-Berechtigung erteilt.'
              : 'USB-Berechtigung abgelehnt. Eine erneute Anfrage ist möglich.',
        );
        await refresh();
        await _maybeAutoConnect();
        return;
      case 'connectionClosed':
        connection = const UsbConnectionStatus(isOpen: false);
        _log('Native USB-Verbindung geschlossen.');
        notifyListeners();
        return;
      case 'midiDevicesChanged':
        _log('Android-MIDI-Geräteliste wurde aktualisiert.');
        await refresh();
        await _maybeAutoConnect();
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
