import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/usb_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../models/guitar_profile.dart';
import '../sounds/sound_labels.dart';
import '../sounds/sound_session.dart';
import '../ui/wyrm_design.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.usb,
    required this.recommendations,
    this.library,
    required this.openDevice,
    required this.openProfile,
    required this.openLibrary,
    required this.createSound,
    this.sounds,
    this.openSound,
    super.key,
  });
  final UsbController usb;
  final RecommendationController recommendations;
  final Tone3000Controller? library;
  final VoidCallback openDevice, openProfile, openLibrary, createSound;

  /// Sound flow state and the action that opens the current sound ("Dein Sound").
  final SoundSession? sounds;
  final void Function(BuildContext context)? openSound;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([usb, recommendations, ?library, ?sounds]),
    builder: (context, _) {
      final guitar = recommendations.selectedProfile;
      final current = sounds?.current;
      final currentDefinition = current == null ? null : sounds!.definitionOf(current);
      final connected = usb.connection.isOpen || usb.midiConnection.isOpen;
      final rigCards = [
        WyrmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.speaker_outlined, color: WyrmTokens.ember),
              const SizedBox(height: 12),
              Text('Dein Rig', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                usb.supportedDevice?.deviceAdapter?.displayName ??
                    'Noch kein Gerät erkannt',
              ),
              const SizedBox(height: 10),
              WyrmStatusBadge(deviceStatusLabel(usb), positive: connected),
              const SizedBox(height: 8),
              const Text(
                'Soundentwürfe funktionieren auch ohne Gerät. Keine allgemeine Presetübertragung.',
              ),
              TextButton.icon(
                onPressed: openDevice,
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  connected ? 'Verbindung anzeigen' : 'Gerät verbinden',
                ),
              ),
            ],
          ),
        ),
        WyrmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.graphic_eq, color: WyrmTokens.ember),
              const SizedBox(height: 12),
              Text(
                guitar?.name ?? 'Deine Gitarre',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                guitar == null
                    ? 'Wähle eine Gitarre für passende Startwerte.'
                    : '${guitar.pickupType.label}\n${guitar.tuning.label} · ${guitar.playbackPath.label}',
              ),
              TextButton.icon(
                onPressed: openProfile,
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  guitar == null
                      ? 'Gitarrenprofil anlegen'
                      : 'Gitarre wechseln / bearbeiten',
                ),
              ),
            ],
          ),
        ),
      ];
      return WyrmScaffold(
        title: 'WyrmTone',
        background: true,
        backgroundIntensity: WyrmBackgroundIntensity.strong,
        body: ListView(
          key: const PageStorageKey('dashboard'),
          padding: WyrmTokens.pagePadding,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hexagon_outlined,
                  color: WyrmTokens.ember,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dein Sound. Deine Gitarre. Dein Rig.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('dashboard-create'),
              onPressed: createSound,
              icon: const Icon(Icons.add),
              label: const Text('Sound finden'),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 700
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: rigCards[0]),
                        const SizedBox(width: 16),
                        Expanded(child: rigCards[1]),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rigCards,
                    ),
            ),
            WyrmSection(
              title: 'Dein Sound',
              child: currentDefinition == null || current == null
                  ? const Text('Noch kein Sound. Tippe oben auf „Sound finden“.')
                  : WyrmCard(
                      key: const Key('dashboard-current-sound'),
                      accent: true,
                      onTap: openSound == null ? null : () => openSound!(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entryDisplayTitle(currentDefinition.entry),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            [
                              if (current.variant != null) variantLabel(current.variant!),
                              current.tuning.label,
                            ].join(' · '),
                          ),
                          const SizedBox(height: WyrmTokens.space8),
                          const WyrmStatusBadge('Vorbereitet · nicht übertragen'),
                        ],
                      ),
                    ),
            ),
            WyrmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deine Bibliothek',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${recommendations.folderFiles.length + (library?.localRecords.length ?? 0)} lokale IR-Dateien · ${library?.namCaptures.length ?? 0} NAM-Captures',
                  ),
                  TextButton.icon(
                    onPressed: openLibrary,
                    icon: const Icon(Icons.library_music_outlined),
                    label: const Text('Bibliothek öffnen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
