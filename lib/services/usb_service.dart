import '../models/usb_models.dart';
import '../midi/midi_receive_source.dart';

abstract interface class UsbService {
  MidiReceiveSource get midiReceiveSource;
  Stream<Map<Object?, Object?>> get events;

  Future<List<UsbDeviceInfo>> listUsbDevices();
  Future<void> requestUsbPermission(String deviceName);
  Future<UsbConnectionStatus> openDevice(String deviceName);
  Future<void> closeDevice();
  Future<UsbConnectionStatus> getConnectionStatus();

  Future<List<MidiDeviceDiagnostic>> listMidiDevices();
  Future<MidiConnectionStatus> openMidiDevice(int deviceId);
  Future<void> closeMidiDevice();
  Future<MidiConnectionStatus> getMidiConnectionStatus();
}
