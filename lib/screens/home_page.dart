import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/usb_controller.dart';
import '../models/usb_models.dart';
import 'matribox_backup_library_panel.dart';
import 'matribox_raw_backup_panel.dart';
import 'midi_capture_panel.dart';
import '../midi/midi_capture_controller.dart';
import '../ui/wyrm_design.dart';

class HomePage extends StatelessWidget {
  const HomePage({required this.controller, super.key});

  final UsbController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => WyrmScaffold(
        title: 'Geräte-Diagnose',
        body: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(controller: controller),
              const SizedBox(height: 12),
              _Actions(controller: controller),
              if (matriboxP01RawBackupEnabled) ...[
                const SizedBox(height: 12),
                MatriboxRawBackupPanel(
                  connectionReady:
                      controller.devices
                              .where((d) => d.isMatriboxOneCandidate)
                              .length ==
                          1 &&
                      controller.matriboxMidiDevice != null &&
                      controller.midiConnection.isOpen &&
                      controller.midiConnection.deviceId ==
                          controller.matriboxMidiDevice?.id,
                  monitoring:
                      controller.capture.state == MidiCaptureState.monitoring,
                ),
                const SizedBox(height: 12),
                const MatriboxBackupLibraryPanel(),
              ],
              const SizedBox(height: 12),
              WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sichere Möglichkeiten',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Geräteerkennung und Verbindungsdiagnose. Soundentwürfe werden nur lokal erstellt.',
                    ),
                    const SizedBox(height: 8),
                    const WyrmStatusBadge(
                      'Preset-, IR- und NAM-Übertragung nicht allgemein verfügbar',
                    ),
                  ],
                ),
              ),
              ExpansionTile(
                key: const Key('advanced-diagnostics'),
                title: const Text('Erweiterte Diagnose'),
                subtitle: const Text('Für Entwicklung und Fehlersuche'),
                initiallyExpanded: false,
                maintainState: true,
                children: [
                  if (controller.supportedDevice?.isMatriboxOneCandidate ==
                      true)
                    _RawUsbAdvanced(controller: controller),
                  const SizedBox(height: 12),
                  if (controller.supportedDevice?.hasPermission == true &&
                      !controller.supportedDevice!.isMatriboxOneCandidate &&
                      !controller.connection.isOpen)
                    FilledButton.tonalIcon(
                      key: const Key('open-button'),
                      onPressed: controller.busy ? null : controller.open,
                      icon: const Icon(Icons.link),
                      label: const Text('Raw-USB-Diagnose öffnen'),
                    ),

                  MidiCapturePanel(controller: controller.capture),
                  const SizedBox(height: 20),
                  Text(
                    'USB-Geräte',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (controller.devices.isEmpty)
                    const Card(
                      key: Key('no-devices'),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Keine USB-Geräte gefunden.'),
                      ),
                    )
                  else
                    ...controller.devices.map(
                      (device) => _DeviceCard(device: device),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Android MIDI-Geräte',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (controller.midiDevices.isEmpty)
                    const Card(
                      key: Key('no-midi-devices'),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Keine Android-MIDI-Geräte gefunden.'),
                      ),
                    )
                  else
                    ...controller.midiDevices.map(
                      (device) => _MidiDeviceCard(device: device),
                    ),
                  const SizedBox(height: 20),
                  _LogCard(controller: controller),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});
  final UsbController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final color = switch (state) {
      UsbConnectionState.open => WyrmTokens.success,
      UsbConnectionState.detected => WyrmTokens.muted,
      UsbConnectionState.permissionRequired => WyrmTokens.ember,
      UsbConnectionState.unknownDevice => Colors.blueGrey,
      UsbConnectionState.noDevice => Colors.grey,
    };
    return Card(
      child: ListTile(
        key: const Key('connection-status'),
        leading: Icon(Icons.usb, color: color),
        title: Text(deviceStatusLabel(controller)),
        subtitle: const Text(
          'WyrmTone erkennt unterstützte Geräte und erstellt Soundentwürfe. Eine allgemeine Presetübertragung ist noch nicht verfügbar.',
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller});
  final UsbController controller;

  @override
  Widget build(BuildContext context) {
    final device = controller.supportedDevice;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          key: const Key('search-button'),
          onPressed: controller.busy ? null : controller.refresh,
          icon: const Icon(Icons.search),
          label: const Text('Geräte suchen'),
        ),
        if (device != null && !device.hasPermission)
          FilledButton.icon(
            key: const Key('permission-button'),
            onPressed: controller.busy ? null : controller.requestPermission,
            icon: const Icon(Icons.lock_open),
            label: const Text('USB-Zugriff erlauben'),
          ),
        if (controller.connection.isOpen)
          FilledButton.icon(
            key: const Key('close-button'),
            onPressed: controller.busy ? null : controller.close,
            icon: const Icon(Icons.link_off),
            label: const Text('Verbindung schließen'),
          ),
        if (controller.matriboxMidiDevice != null &&
            !controller.midiConnection.isOpen)
          FilledButton.icon(
            key: const Key('midi-open-button'),
            onPressed: controller.busy ? null : controller.openMidi,
            icon: const Icon(Icons.piano),
            label: const Text('MIDI-Gerät öffnen'),
          ),
        if (controller.midiConnection.isOpen)
          FilledButton.icon(
            key: const Key('midi-close-button'),
            onPressed: controller.busy ? null : controller.closeMidi,
            icon: const Icon(Icons.close),
            label: const Text('MIDI-Gerät schließen'),
          ),
      ],
    );
  }
}

class _RawUsbAdvanced extends StatelessWidget {
  const _RawUsbAdvanced({required this.controller});
  final UsbController controller;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const Key('raw-usb-diagnostics'),
    title: const Text('Raw-USB-Test'),
    children: [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Android MIDI ist der bevorzugte Weg. Android verwaltet Interface 3 bereits; '
          'ein nicht erzwungener Raw-USB-Claim darf erwartbar scheitern.',
        ),
      ),
      FilledButton.tonalIcon(
        key: const Key('open-button'),
        onPressed:
            controller.supportedDevice?.hasPermission == true &&
                !controller.connection.isOpen &&
                controller.rawUsbAllowed
            ? controller.open
            : null,
        icon: const Icon(Icons.usb),
        label: const Text('Raw-USB-Diagnose öffnen'),
      ),
      if (controller.rawMatriboxFailed)
        const Text(
          'Erwartbarer Claim-Fehlschlag bereits protokolliert; keine weiteren Versuche bis zum Neuanschließen.',
        ),
    ],
  );
}

class _MidiDeviceCard extends StatelessWidget {
  const _MidiDeviceCard({required this.device});
  final MidiDeviceDiagnostic device;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('midi-device-${device.id}'),
      color: device.isMatribox
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (device.isMatribox)
              const Text('Dem angeschlossenen Matribox-USB-Gerät zugeordnet'),
            Text('MIDI-Geräte-ID: ${device.id}'),
            Text('Hersteller: ${device.manufacturer ?? 'Nicht verfügbar'}'),
            Text('USB-Gerät: ${device.usbDeviceName ?? 'Nicht zugeordnet'}'),
            Text(
              'Input-Ports: ${device.inputPortCount} · '
              'Output-Ports: ${device.outputPortCount}',
            ),
            if (device.ports.isEmpty)
              const Text('Keine Ports')
            else
              for (final port in device.ports)
                Text(
                  '${port.direction.label}-Port ${port.number}'
                  '${port.name == null ? '' : ' · ${port.name}'}',
                ),
            const SizedBox(height: 8),
            const Text(
              'Geräte-Output liefert Daten zur App. Geräte-Input würde zum Gerät senden '
              'und bleibt im passiven Monitor geschlossen. Nur das Presetlesen und die bestätigte Übertragung öffnen ihn.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final UsbDeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final adapter = device.deviceAdapter;
    return Card(
      key: Key('device-${device.deviceName}'),
      color: device.isSupported
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ExpansionTile(
        initiallyExpanded: device.isSupported,
        leading: Icon(device.isSupported ? Icons.graphic_eq : Icons.usb),
        title: Text(device.productName ?? device.deviceName),
        subtitle: Text(
          '${device.vendorId} (${device.vendorIdHex}) : '
          '${device.productId} (${device.productIdHex})'
          '${adapter == null ? '' : ' · ${adapter.usbProfile.candidateLabel} erkannt'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _Detail('Device Name', device.deviceName),
          _Detail(
            'Klasse / Subklasse / Protokoll',
            '${device.deviceClass} / ${device.deviceSubclass} / ${device.deviceProtocol}',
          ),
          _Detail(
            'Konfigurationen / Interfaces / Endpunkte',
            '${device.configurationCount} / ${device.interfaces.length} / ${device.endpointCount}',
          ),
          _Detail('Hersteller', device.manufacturerName ?? 'Nicht verfügbar'),
          _Detail('Produkt', device.productName ?? 'Nicht verfügbar'),
          const _Detail(
            'Seriennummer',
            'wird aus Datenschutzgründen nicht angezeigt',
          ),
          _Detail(
            'USB-Berechtigung',
            device.hasPermission ? 'Erteilt' : 'Nicht erteilt',
          ),
          for (final usbInterface in device.interfaces)
            _InterfaceCard(
              usbInterface: usbInterface,
              relevant:
                  device.deviceAdapter?.usbProfile.expectedInterface.id ==
                      usbInterface.id &&
                  device
                          .deviceAdapter
                          ?.usbProfile
                          .expectedInterface
                          .alternateSetting ==
                      usbInterface.alternateSetting,
            ),
        ],
      ),
    );
  }
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard({required this.usbInterface, required this.relevant});
  final UsbInterfaceInfo usbInterface;
  final bool relevant;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: relevant
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: relevant ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Interface ${usbInterface.id} (Alt ${usbInterface.alternateSetting})${relevant ? ' · relevante Schnittstelle' : ''}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Klasse ${usbInterface.interfaceClass}, '
            'Subklasse ${usbInterface.interfaceSubclass}, '
            'Protokoll ${usbInterface.interfaceProtocol}',
          ),
          if (usbInterface.endpoints.isEmpty)
            const Text('Keine Endpunkte')
          else
            for (final endpoint in usbInterface.endpoints)
              Text(
                '${endpoint.hexadecimalAddress} · ${endpoint.direction.label} · '
                '${endpoint.type.label} · max. ${endpoint.maxPacketSize} Byte · '
                'Intervall ${endpoint.interval}',
              ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$label: $value'),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.controller});
  final UsbController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Diagnoseprotokoll',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('copy-log-button'),
                  tooltip: 'Diagnoseprotokoll kopieren',
                  onPressed: controller.logs.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: controller.copyableLog),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Protokoll kopiert.'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const Text('Flüchtig, lokal, ohne Seriennummern oder Binärdaten.'),
            const SizedBox(height: 8),
            SelectableText(
              controller.copyableLog,
              key: const Key('diagnostic-log'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
