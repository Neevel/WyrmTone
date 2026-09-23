import 'package:flutter/material.dart';

import '../controllers/usb_controller.dart';
import '../ui/wyrm_components.dart';
import '../ui/wyrm_design.dart';
import 'home_page.dart';

/// Settings → Geräte: the primary receiving device (Matribox 1), its connection status, the
/// Auto-Connect switch, and a link into the untouched technical diagnostics. This replaces the
/// separate "Gerät" bottom-navigation tab; the diagnostic tools themselves are not removed, only
/// moved one step further from the normal flow.
class DeviceSettingsPage extends StatelessWidget {
  const DeviceSettingsPage({required this.controller, super.key});
  final UsbController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.connectionState;
      final (icon, color) = switch (state) {
        DeviceConnectionState.connected => (Icons.usb, WyrmTokens.success),
        DeviceConnectionState.connecting || DeviceConnectionState.detected => (Icons.usb, WyrmTokens.muted),
        DeviceConnectionState.permissionRequired => (Icons.usb_off, WyrmTokens.ember),
        DeviceConnectionState.error => (Icons.error_outline, WyrmTokens.danger),
        DeviceConnectionState.disconnected => (Icons.usb_off, WyrmTokens.muted),
      };
      final device = controller.matriboxDevice;
      return WyrmScaffold(
        title: 'Geräte',
        background: true,
        backgroundIntensity: WyrmBackgroundIntensity.dim,
        body: ListView(
          key: const PageStorageKey('device-settings'),
          padding: WyrmTokens.pagePadding,
          children: [
            const WyrmSectionHeader('Empfangsgerät', subtitle: 'Wohin WyrmTone Sounds übertragen kann'),
            WyrmCard(
              key: const Key('device-settings-primary'),
              accent: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: WyrmTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Matribox 1', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: WyrmTokens.space4),
                        Text(controller.primaryDeviceStatusLabel, key: const Key('device-settings-status')),
                        if (state == DeviceConnectionState.permissionRequired) ...[
                          const SizedBox(height: WyrmTokens.space8),
                          FilledButton.icon(
                            key: const Key('device-settings-allow'),
                            onPressed: controller.busy ? null : controller.requestPermission,
                            icon: const Icon(Icons.lock_open),
                            label: const Text('Verbindung erlauben'),
                          ),
                        ],
                        if (state == DeviceConnectionState.disconnected) ...[
                          const SizedBox(height: WyrmTokens.space4),
                          const Text('Stecke deine Matribox 1 per USB an. WyrmTone verbindet sich dann von selbst.'),
                        ],
                        if (state == DeviceConnectionState.error) ...[
                          const SizedBox(height: WyrmTokens.space4),
                          const Text('Die Verbindung ist fehlgeschlagen. Stecke das Kabel neu ein oder versuche es erneut.'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              key: const Key('device-settings-autoconnect'),
              contentPadding: EdgeInsets.zero,
              value: controller.autoConnect,
              onChanged: controller.setAutoConnect,
              title: const Text('Auto-Connect'),
              subtitle: const Text('Verbindet eine erkannte Matribox 1 automatisch (nur Lesen, es wird nichts gesendet).'),
            ),
            if (device != null) ...[
              const WyrmSectionHeader('Geräteinformationen'),
              WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${device.manufacturerName ?? 'Sonicake'} · ${device.productName ?? 'Matribox 1'}'),
                    Text('${device.vendorIdHex} : ${device.productIdHex}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
            const WyrmSectionHeader('Weitere Geräte', subtitle: 'Vorbereitet für später'),
            const WyrmCard(
              child: Text('Aktuell wird nur die Matribox 1 als Empfangsgerät unterstützt.'),
            ),
            const WyrmSectionHeader('Entwickler'),
            WyrmSecondaryButton(
              key: const Key('open-advanced-diagnostics'),
              label: 'Erweiterte Diagnose',
              icon: Icons.build_outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => HomePage(controller: controller)),
              ),
            ),
            const SizedBox(height: WyrmTokens.space24),
          ],
        ),
      );
    },
  );
}
