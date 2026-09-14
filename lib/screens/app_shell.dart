import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/usb_controller.dart';
import '../controllers/tone3000_controller.dart';
import 'guitars_page.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'recommendation_page.dart';
import 'sounds_page.dart';
import 'dashboard_page.dart';

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
  bool creating = false;

  void _createSound() => setState(() {
    index = 1;
    creating = true;
  });
  void _navigate(int value) => setState(() {
    index = value;
  });

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        usb: widget.usbController,
        recommendations: widget.recommendationController,
        library: widget.tone3000Controller,
        openDevice: () => _navigate(2),
        openProfile: () => _navigate(4),
        openLibrary: () => _navigate(3),
        createSound: _createSound,
      ),
      creating
          ? RecommendationPage(
              controller: widget.recommendationController,
              tone3000: widget.tone3000Controller,
              openProfile: () => _navigate(4),
              close: () => setState(() {
                creating = false;
              }),
            )
          : SoundsPage(
              controller: widget.recommendationController,
              createSound: _createSound,
            ),
      HomePage(controller: widget.usbController),
      LibraryPage(
        controller: widget.recommendationController,
        tone3000: widget.tone3000Controller,
      ),
      GuitarsPage(controller: widget.recommendationController),
    ];
    return Scaffold(
      body: MediaQuery.removeViewInsets(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Start',
          ),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Sounds'),
          NavigationDestination(icon: Icon(Icons.usb), label: 'Gerät'),
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
