import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../devices/device_profile.dart';
import '../ui/wyrm_design.dart';
import 'ir_library_page.dart';
import 'nam_library_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({required this.controller, this.tone3000, super.key});
  final RecommendationController controller;
  final Tone3000Controller? tone3000;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Bibliothek'),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.speaker_outlined), text: 'IRs'),
            Tab(icon: Icon(Icons.memory), text: 'NAM'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          IrLibraryPage(
            controller: controller,
            tone3000: tone3000,
            embedded: true,
          ),
          if (tone3000 != null)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => NamLibraryPage(
                controller: tone3000!,
                embedded: true,
                targetSupportsNam:
                    controller.selectedTargetDevice ==
                    TargetDeviceId.matriboxOne,
              ),
            )
          else
            const Padding(
              padding: WyrmTokens.pagePadding,
              child: WyrmEmptyState(
                title: 'NAM-Bibliothek nicht eingerichtet',
                message: 'Die lokale Sound-Erstellung mit internen Amp-Modellen bleibt verfügbar.',
              ),
            ),
        ],
      ),
    ),
  );
}
