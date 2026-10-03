import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/usb_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../services/local_persistence.dart';
import '../sounds/sound_selection.dart';
import '../sounds/sound_session.dart';
import '../ui/wyrm_design.dart';
import 'device_settings_page.dart';
import 'preset_workspace_page.dart';
import 'guitars_page.dart';
import 'library_page.dart';
import 'sounds_page.dart';
import 'your_sound_page.dart';
import 'dashboard_page.dart';
import 'tone_match_page.dart';
import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../tonematch/tone_knowledge_provider.dart';
import '../tonematch/tone_match_controller.dart';
import '../tonematch/tone_analysis_runner.dart';
import '../tonematch/analysis_interfaces.dart' show ToneMatchCache;
import '../tonematch/tone_match_models.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.usbController,
    required this.recommendationController,
    this.tone3000Controller,
    this.soundSession,
    this.toneMatchRunner,
    this.toneMatchCache,
    super.key,
  });

  final UsbController usbController;
  final RecommendationController recommendationController;
  final Tone3000Controller? tone3000Controller;

  /// The sound flow state. Created here (without persistence) when a test does not provide one.
  final SoundSession? soundSession;

  /// Acoustic check of NAMs for Tone Match (runner + cache). Without them Tone Match shows only the
  /// description-based pre-selection.
  final ToneAnalysisRunner? toneMatchRunner;
  final ToneMatchCache? toneMatchCache;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  late final SoundSession _session;
  late final bool _ownsSession;
  late final ToneMatchController _toneMatch;

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
    final runner = widget.toneMatchRunner, cache = widget.toneMatchCache;
    _toneMatch = ToneMatchController(
      coordinator: runner == null || cache == null
          ? null
          : ToneAnalysisCoordinator(runner: runner, cache: cache),
      knowledge: () async {
        await _session.ensureLoaded();
        final vault = _session.vault;
        return vault == null ? null : LocalToneKnowledgeProvider(vault);
      },
      captures: () => widget.tone3000Controller?.namCaptures ?? const [],
      device: _toneMatchDevice,
      guitar: () {
        final g = widget.recommendationController.selectedProfile;
        return g == null ? null : (name: g.name, pickups: g.pickupType.label);
      },
    );
  }

  /// Capabilities of the chosen target device, only if the user (or a connected device) chose one.
  ToneDeviceCapabilities? _toneMatchDevice() {
    final c = widget.recommendationController;
    if (!c.hasTargetDevice) return null;
    final a = toneDeviceAdapters.firstWhere(
      (a) => a.id == c.selectedTargetDevice,
    );
    return ToneDeviceCapabilities(
      name: a.shortName,
      namTransfer: a.capabilities.supportsNam,
      // A Tone Match plan is not wired into the preset pipeline yet: do not pretend otherwise.
      presetTransfer: false,
    );
  }

  @override
  void dispose() {
    _toneMatch.dispose();
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  void _findSound() => setState(() => index = 1);
  void _navigate(int value) => setState(() {
    index = value;
  });

  Widget _presetWorkshop(BuildContext _) => PresetWorkspacePage(
    controller: widget.recommendationController,
    library: widget.tone3000Controller,
  );

  void _openDeviceSettings(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DeviceSettingsPage(
        controller: widget.usbController,
        presetWorkshop: _presetWorkshop,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        usb: widget.usbController,
        recommendations: widget.recommendationController,
        library: widget.tone3000Controller,
        openDevice: () => _openDeviceSettings(context),
        openProfile: () => _navigate(4),
        openLibrary: () => _navigate(3),
        createSound: _findSound,
        sounds: _session,
        openSound: (context) => openYourSound(
          context,
          controller: widget.recommendationController,
          session: _session,
          usbController: widget.usbController,
          openProfile: () => _navigate(4),
        ),
      ),
      SoundsPage(
        controller: widget.recommendationController,
        session: _session,
        openProfile: () => _navigate(4),
      ),
      ToneMatchPage(
        controller: _toneMatch,
        usbController: widget.usbController,
        openLibrary: () => _navigate(3),
      ),
      LibraryPage(
        controller: widget.recommendationController,
        usbController: widget.usbController,
        tone3000: widget.tone3000Controller,
      ),
      GuitarsPage(
        controller: widget.recommendationController,
        usbController: widget.usbController,
        presetWorkshop: _presetWorkshop,
      ),
    ];
    return Scaffold(
      body: Column(
        children: [
          _GlobalDeviceStatusBar(
            controller: widget.usbController,
            onTap: () => _openDeviceSettings(context),
          ),
          Expanded(
            child: MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true,
              // The NavigationBar below already respects the system navigation inset; the tab
              // pages must not subtract it a second time (that left a dead band above the bar
              // and cut cards off mid-way).
              // Builder: the second MediaQuery must be derived from the context BELOW the first one.
              // With the outer context it re-introduced the keyboard inset, so every page's own Scaffold
              // shrank a second time and a page with a text field collapsed to a sliver (Tone Match on a
              // real phone: no button visible while typing).
              child: Builder(
                builder: (context) => MediaQuery.removePadding(
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
            icon: Icon(Icons.auto_fix_high),
            label: 'Tone Match',
          ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: WyrmTokens.space12,
                vertical: 6,
              ),
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
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: WyrmTokens.muted,
                  ),
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
