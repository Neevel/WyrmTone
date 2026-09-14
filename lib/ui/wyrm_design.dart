import 'package:flutter/material.dart';

import '../models/tone_target.dart';
import '../nam/local_nam_capture.dart';
import '../controllers/usb_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../midi/midi_capture_controller.dart';

abstract final class WyrmTokens {
  static const background = Color(0xff0d0f12);
  static const surface = Color(0xff191c21);
  static const raised = Color(0xff23272e);
  static const ember = Color(0xffe8a06c);
  static const text = Color(0xfff1eee9);
  static const muted = Color(0xffbbb7b0);
  static const outline = Color(0xff41454e);
  static const success = Color(0xff80cbb4);
  static const danger = Color(0xffffb4ab);
  static const gap = 16.0;
  static const radius = 18.0;
  static const maxWidth = 1040.0;
  static const pagePadding = EdgeInsets.all(gap);
  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: ember,
      onPrimary: Color(0xff24160d),
      primaryContainer: raised,
      onPrimaryContainer: text,
      secondary: ember,
      onSecondary: background,
      secondaryContainer: raised,
      onSecondaryContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: outline,
      outlineVariant: Color(0xff30343c),
      error: danger,
      onError: Color(0xff460c0c),
      errorContainer: Color(0xff4c171b),
      onErrorContainer: Color(0xffffdad6),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: Color(0xff30343c)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: raised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: raised,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: raised,
      side: const BorderSide(color: outline),
      padding: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(color: outline, space: 24),
  );
}

class WyrmScaffold extends StatelessWidget {
  const WyrmScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.embedded = false,
    super.key,
  });
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool embedded;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: embedded ? null : AppBar(title: Text(title), actions: actions),
    body: SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WyrmTokens.maxWidth),
          child: body,
        ),
      ),
    ),
    floatingActionButton: floatingActionButton,
  );
}

class WyrmCard extends StatelessWidget {
  const WyrmCard({required this.child, this.accent = false, super.key});
  final Widget child;
  final bool accent;
  @override
  Widget build(BuildContext context) => Card(
    shape: accent
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WyrmTokens.radius),
            side: const BorderSide(color: WyrmTokens.ember),
          )
        : null,
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: WyrmTokens.pagePadding, child: child),
    ),
  );
}

class WyrmSection extends StatelessWidget {
  const WyrmSection({
    required this.title,
    this.subtitle,
    required this.child,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null)
          Text(subtitle!, style: const TextStyle(color: WyrmTokens.muted)),
        const SizedBox(height: WyrmTokens.gap),
        child,
      ],
    ),
  );
}

class WyrmStatusBadge extends StatelessWidget {
  const WyrmStatusBadge(
    this.label, {
    this.positive = false,
    this.warning = false,
    super.key,
  });
  final String label;
  final bool positive, warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: WyrmTokens.raised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: positive
            ? WyrmTokens.success
            : warning
            ? WyrmTokens.danger
            : WyrmTokens.muted,
      ),
    ),
  );
}

class WyrmEmptyState extends StatelessWidget {
  const WyrmEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.library_music_outlined,
    this.action,
    super.key,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => WyrmCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: WyrmTokens.ember),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message),
        ?action,
      ],
    ),
  );
}

// Presentation only: no engine, data or wire changes.
String roleLabel(SoundRole role) => switch (role) {
  SoundRole.rhythm => 'Rhythmus',
  SoundRole.lead => 'Lead',
  SoundRole.clean => 'Clean',
};

String deviceStatusLabel(UsbController controller) {
  if (controller.midiConnection.isOpen) return 'MIDI-Verbindung geöffnet';
  if (controller.connection.isOpen) return 'USB-Verbindung geöffnet';
  final device = controller.supportedDevice;
  if (device == null) return 'Kein unterstütztes Gerät erkannt';
  final name = device.deviceAdapter?.displayName ?? 'Gerät';
  return device.hasPermission
      ? '$name erkannt'
      : '$name erkannt · USB-Zugriff noch nicht erlaubt';
}

String midiCaptureStatusLabel(MidiCaptureState state) => switch (state) {
  MidiCaptureState.disconnected => 'getrennt',
  MidiCaptureState.deviceDetected => 'Gerät erkannt',
  MidiCaptureState.deviceOpened => 'Gerät geöffnet',
  MidiCaptureState.monitoring => 'Empfang aktiv',
  MidiCaptureState.stopping => 'Empfang wird beendet',
  MidiCaptureState.error => 'Fehler',
};

// The controller may repeat the same configuration diagnosis during initialize.
// Suppress only that exact duplicate, never a distinct operation error.
String? tone3000VisibleMessage(Tone3000Controller controller) =>
    !controller.isConfigured &&
        controller.message == controller.config.validationMessage
    ? null
    : controller.message;

class WyrmTone3000Header extends StatelessWidget {
  const WyrmTone3000Header({required this.controller, super.key});
  final Tone3000Controller controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        controller.isConfigured ? 'TONE3000' : 'TONE3000 nicht eingerichtet',
        key: const Key('tone3000-missing-config'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      WyrmStatusBadge(
        !controller.isConfigured
            ? 'Nicht eingerichtet'
            : controller.isConnected
            ? 'Verbunden'
            : 'Anmeldung erforderlich',
        positive: controller.isConnected,
      ),
      if (!controller.isConfigured)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Online-Auswahl ist noch nicht eingerichtet. Deine lokale Bibliothek bleibt nutzbar.',
          ),
        ),
      ExpansionTile(
        key: const Key('tone3000-details'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Datenschutz & Einrichtung'),
        children: [
          const Text(
            'Anmeldung und Auswahl im Systembrowser. Tokens werden verschlüsselt gespeichert, nicht protokolliert und nicht an eigene Server übertragen. Nur ausgewählte Downloads.',
          ),
          if (!controller.isConfigured)
            Text(controller.config.validationMessage!),
        ],
      ),
    ],
  );
}

String profileKindLabel(SoundProfileKind kind) => switch (kind) {
  SoundProfileKind.song => 'Songprofil',
  SoundProfileKind.artist => 'Künstlerprofil',
  SoundProfileKind.genre => 'Genre-Fallback',
  SoundProfileKind.fallback => 'Allgemeines Fallback',
};
String compatibilityLabel(NamCompatibility status) => switch (status) {
  NamCompatibility.compatible => 'Kompatibel',
  NamCompatibility.conversionRequired => 'Konvertierung nötig',
  NamCompatibility.unsupported => 'Nicht unterstützt',
  NamCompatibility.unknown => 'Unbestätigt',
  NamCompatibility.invalid => 'Ungültig',
  NamCompatibility.missingLocalFile => 'Datei fehlt',
};
String toneLabel(ToneDimension dimension) => switch (dimension) {
  ToneDimension.gain => 'Gain',
  ToneDimension.saturation => 'Sättigung',
  ToneDimension.tightness => 'Straffheit',
  ToneDimension.attack => 'Anschlag',
  ToneDimension.sustain => 'Sustain',
  ToneDimension.bass => 'Bass',
  ToneDimension.lowMids => 'Tiefmitten',
  ToneDimension.mids => 'Mitten',
  ToneDimension.upperMids => 'Obere Mitten',
  ToneDimension.treble => 'Höhen',
  ToneDimension.presence => 'Presence',
  ToneDimension.compression => 'Kompression',
  ToneDimension.gateStrength => 'Gate-Stärke',
  ToneDimension.gateOpening => 'Gate-Öffnung',
  ToneDimension.space => 'Räumlichkeit',
  ToneDimension.delay => 'Delay',
  ToneDimension.reverb => 'Hall',
  ToneDimension.modulation => 'Modulation',
  ToneDimension.irBrightness => 'IR-Helligkeit',
};
