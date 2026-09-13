import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../models/guitar_profile.dart';

class SoundsPage extends StatelessWidget {
  const SoundsPage({required this.controller, super.key});
  final RecommendationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Ziel-Sounds')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                    'Amp: ${sound.ampModel}\n${sound.approximations.join(' ')}',
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
