import '../models/usb_models.dart';
import '../midi/midi_receive_source.dart';

abstract interface class UsbService {
  MidiReceiveSource get midiReceiveSource;
  Stream<Map<Object?, Object?>> get events;

  /// Product NAM transfer V1: one event per CONFIRMED ACK during
  /// [executeNamCloneTransferSession] (never per sent frame), each shaped
  /// `{confirmedCount, lastConfirmedBlock, totalFrames}` -- real progress
  /// for a "347 von 590" UI. A dedicated stream (not [events]) so up to 590
  /// events per transfer never compete with other USB event consumers.
  /// Empty/no events outside an active transfer.
  Stream<Map<Object?, Object?>> get namTransferProgress;

  Future<List<UsbDeviceInfo>> listUsbDevices();
  Future<void> requestUsbPermission(String deviceName);
  Future<UsbConnectionStatus> openDevice(String deviceName);
  Future<void> closeDevice();
  Future<UsbConnectionStatus> getConnectionStatus();

  Future<List<MidiDeviceDiagnostic>> listMidiDevices();
  Future<MidiConnectionStatus> openMidiDevice(int deviceId);
  Future<void> closeMidiDevice();
  Future<MidiConnectionStatus> getMidiConnectionStatus();

  /// V5B.1: sends exactly [bytes] on the Matribox input port 0. The ONLY
  /// parameter is the already-built, already-validated frame bytes -- no
  /// clone/preset slot, no NAM path, no protocol choice. The native side
  /// fails closed unless its own separate `REAL_MATRIBOX_WRITE` compile
  /// gate is enabled (hardcoded false in this milestone).
  Future<void> sendNamCloneTransferFrame(List<int> bytes);

  /// V5B.2a/b: the real, strict stop-and-wait NAM Clone-transfer session.
  /// [frames] is the already-built, already-validated list of 47-byte
  /// frame arrays (the frozen transfer plan) -- no slot, no NAM path, no
  /// protocol choice. Fails closed the same way [sendNamCloneTransferFrame]
  /// does; only actually sends anything if `REAL_MATRIBOX_WRITE` is
  /// enabled natively.
  Future<Map<Object?, Object?>> executeNamCloneTransferSession(List<List<int>> frames);

  /// Product NAM transfer V1 hardware-certification fix: cancels ONLY an
  /// active [executeNamCloneTransferSession] call, if one is running --
  /// unlike [closeDevice] this never tears down the USB connection, the
  /// passive monitor, or any other session. This is the call the product
  /// UI's "Abbrechen" button during a transfer must use; [closeDevice]
  /// never reaches the native NAM transfer session at all. No-op if no
  /// transfer is active.
  Future<void> cancelNamCloneTransferSession();
}
