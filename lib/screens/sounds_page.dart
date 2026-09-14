import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../models/guitar_profile.dart';
import '../ui/wyrm_design.dart';

class SoundsPage extends StatelessWidget {
  const SoundsPage({required this.controller, this.createSound, super.key});
  final RecommendationController controller;
  final VoidCallback? createSound;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => WyrmScaffold(
        title: 'Sounds',
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: createSound,
              icon: const Icon(Icons.add),
              label: const Text('Neuen Sound erstellen'),
            ),
            if (controller.offlineDraft case final draft?)
              WyrmCard(
                accent: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.profile.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${roleLabel(draft.role)} · ${draft.tuning.label} · Lokaler Entwurf',
                    ),
                    TextButton(
                      onPressed: createSound,
                      child: const Text('Entwurf öffnen'),
                    ),
                  ],
                ),
              ),
            const WyrmSection(
              title: 'Referenz-Sounds',
              subtitle: 'Kuratierte Startpunkte · keine Studio-Rekonstruktion',
              child: SizedBox.shrink(),
            ),
            for (final sound in controller.sounds)
              Card(
                child: ListTile(
                  key: Key('sound-${sound.id}'),
                  onTap: () => controller.selectSound(sound.id),
                  leading: Icon(
                    controller.selectedSoundId == sound.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(sound.displayName),
                  subtitle: Text(
                    '${sound.style} · ${sound.referenceTuning.label}\n'
                    'Amp: ${sound.ampModel} · Referenz',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
