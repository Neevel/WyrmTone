import 'package:flutter/material.dart';

import 'controllers/usb_controller.dart';
import 'controllers/recommendation_controller.dart';
import 'controllers/tone3000_controller.dart';
import 'screens/app_shell.dart';
import 'services/ir_file_picker_service.dart';
import 'services/ir_reference_catalog_service.dart';
import 'services/local_persistence.dart';
import 'services/usb_service.dart';
import 'sounds/sound_selection.dart';
import 'sounds/sound_session.dart';
import 'ui/wyrm_design.dart';

class WyrmToneApp extends StatefulWidget {
  const WyrmToneApp({
    required this.usbService,
    this.irReferenceCatalogService = const EmptyIrReferenceCatalogService(),
    this.irFilePickerService = const EmptyIrFilePickerService(),
    this.tone3000Controller,
    super.key,
  });

  final UsbService usbService;
  final IrReferenceCatalogService irReferenceCatalogService;
  final IrFilePickerService irFilePickerService;
  final Tone3000Controller? tone3000Controller;

  @override
  State<WyrmToneApp> createState() => _WyrmToneAppState();
}

class _WyrmToneAppState extends State<WyrmToneApp> with WidgetsBindingObserver {
  late final UsbController controller;
  late final RecommendationController recommendationController;
  late final SoundSession soundSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = UsbController(widget.usbService)..initialize();
    final store = SharedPreferencesStringStore();
    recommendationController = RecommendationController(
      profileRepository: ProfileRepository(store),
      irRepository: IrCatalogRepository(store),
      filePicker: widget.irFilePickerService,
      referenceCatalogService: widget.irReferenceCatalogService,
    )..initialize();
    soundSession = SoundSession(
      controller: recommendationController,
      repository: SoundSelectionRepository(store),
      tone3000: widget.tone3000Controller,
    )..ensureLoaded();
    widget.tone3000Controller?.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    soundSession.dispose();
    recommendationController.dispose();
    widget.tone3000Controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      controller.pauseMidi().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WyrmTone',
      debugShowCheckedModeBanner: false,
      theme: WyrmTokens.theme(),
      home: AppShell(
        usbController: controller,
        recommendationController: recommendationController,
        tone3000Controller: widget.tone3000Controller,
        soundSession: soundSession,
      ),
    );
  }
}
