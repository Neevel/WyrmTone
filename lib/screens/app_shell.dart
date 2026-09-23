import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/usb_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../services/local_persistence.dart';
import '../sounds/sound_selection.dart';
import '../sounds/sound_session.dart';
import '../ui/wyrm_design.dart';
import 'device_settings_page.dart';
import 'guitars_page.dart';
import 'library_page.dart';
import 'sounds_page.dart';
import 'your_sound_page.dart';
import 'dashboard_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.usbController,
    required this.recommendationController,
    this.tone3000Controller,
    this.soundSession,
    super.key,
  });

  final UsbController usbController;
  final RecommendationController recommendationController;
  final Tone3000Controller? tone3000Controller;

  /// The sound flow state. Created here (without persistence) when a test does not provide one.
  final SoundSession? soundSession;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  late final SoundSession _session;
  late final bool _ownsSession;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.soundSession == null;
    _session =
        widget.soundSession ??
        SoundSession(
          controller: widget.recommendationController,
          repository: SoundSelectionRepository(_MemoryStore()),
          tone3000: widget.tone3000Controller,
        );
    _session.ensureLoaded();
  }

  @override
  void dispose() {
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  void _findSound() => setState(() => index = 1);
  void _navigate(int value) => setState(() {
    index = value;
  });

  void _openDeviceSettings(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DeviceSettingsPage(controller: widget.usbController)),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        usb: widget.usbController,
        recommendations: widget.recommendationController,
        library: widget.tone3000Controller,
        openDevice: () => _openDeviceSettings(context),
        openProfile: () => _navigate(3),
        openLibrary: () => _navigate(2),
        createSound: _findSound,
        sounds: _session,
        openSound: (context) => openYourSound(
          context,
          controller: widget.recommendationController,
          session: _session,
          usbController: widget.usbController,
          openProfile: () => _navigate(3),
        ),
      ),
      SoundsPage(
        controller: widget.recommendationController,
        session: _session,
        openProfile: () => _navigate(3),
      ),
      LibraryPage(
        controller: widget.recommendationController,
        tone3000: widget.tone3000Controller,
      ),
      GuitarsPage(
        controller: widget.recommendationController,
        usbController: widget.usbController,
      ),
    ];
    return Scaffold(
      body: Column(
        children: [
          _GlobalDeviceStatusBar(controller: widget.usbController, onTap: () => _openDeviceSettings(context)),
          Expanded(
            child: MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true,
              child: IndexedStack(
                index: index,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    TickerMode(enabled: i == index, child: pages[i]),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Start',
          ),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Sounds'),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            label: 'Bibliothek',
          ),
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Profil'),
        ],
      ),
    );
  }
}

/// Dezent, always visible, never a full device card: what "Empfangsgerät" state the app is in
/// right now, one tap away from Settings → Geräte. Never itself reads, backs up or sends anything.
class _GlobalDeviceStatusBar extends StatelessWidget {
  const _GlobalDeviceStatusBar({required this.controller, required this.onTap});
  final UsbController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.connectionState;
      final color = switch (state) {
        DeviceConnectionState.connected => WyrmTokens.success,
        DeviceConnectionState.error => WyrmTokens.danger,
        DeviceConnectionState.permissionRequired => WyrmTokens.ember,
        _ => WyrmTokens.muted,
      };
      return Material(
        color: WyrmTokens.surface.withValues(alpha: 0.92),
        child: InkWell(
          key: const Key('global-device-status'),
          onTap: onTap,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WyrmTokens.space12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: color),
                  const SizedBox(width: WyrmTokens.space8),
                  Expanded(
                    child: Text(
                      controller.primaryDeviceStatusLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: WyrmTokens.muted),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Keeps the flow working (without saving) when no persistent store was handed in.
class _MemoryStore implements StringStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
