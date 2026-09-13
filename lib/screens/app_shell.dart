import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/usb_controller.dart';
import '../controllers/tone3000_controller.dart';
import 'guitars_page.dart';
import 'home_page.dart';
import 'ir_library_page.dart';
import 'recommendation_page.dart';
import 'sounds_page.dart';
import 'nam_library_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.usbController,
    required this.recommendationController,
    this.tone3000Controller,
    super.key,
  });

  final UsbController usbController;
  final RecommendationController recommendationController;
  final Tone3000Controller? tone3000Controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(controller: widget.usbController),
      GuitarsPage(controller: widget.recommendationController),
      SoundsPage(controller: widget.recommendationController),
      IrLibraryPage(
        controller: widget.recommendationController,
        tone3000: widget.tone3000Controller,
      ),
      if (widget.tone3000Controller case final controller?)
        NamLibraryPage(controller: controller)
      else
        const Scaffold(body: Center(child: Text('NAM nicht verfügbar'))),
      RecommendationPage(
        controller: widget.recommendationController,
        tone3000: widget.tone3000Controller,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.usb), label: 'Verbindung'),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq),
            label: 'Gitarren',
          ),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Sounds'),
          NavigationDestination(
            icon: Icon(Icons.library_music),
            label: 'IR-Bibliothek',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory),
            label: 'NAM-Bibliothek',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Empfehlung'),
        ],
      ),
    );
  }
}
