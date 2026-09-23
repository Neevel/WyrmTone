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

  // --- spacing / shape / size tokens (use these instead of ad-hoc numbers)
  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const gap = 16.0;
  static const space16 = gap;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const radius = 18.0;
  static const radiusSmall = 12.0;
  static const radiusChip = 10.0;
  static const iconSmall = 20.0;
  static const iconMedium = 24.0;
  static const minTouch = 48.0;
  static const maxWidth = 1040.0;

  /// Reading width of content pages: cards do not stretch across a whole foldable display.
  static const contentWidth = 720.0;
  static const pagePadding = EdgeInsets.all(gap);
  static const cardPadding = EdgeInsets.all(gap);

  static TextTheme _textTheme(TextTheme base) => base
      .copyWith(
        headlineSmall: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2),
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.4),
        bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
        bodySmall: const TextStyle(fontSize: 13, height: 1.35, color: muted),
        labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      )
      .apply(bodyColor: text, displayColor: text);

  static ThemeData theme() => _themeFrom(ThemeData(useMaterial3: true, brightness: Brightness.dark));

  static ThemeData _themeFrom(ThemeData base) => base.copyWith(
    textTheme: _textTheme(base.textTheme),
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

/// How strongly the amp-wall photo shows through on a given screen (see [WyrmScaffold.background]).
/// Not every screen should look equally dramatic: Start/Sounds are the "hero" screens, detail pages
/// are quieter, and forms/settings/transfer need the calmest, most legible background.
enum WyrmBackgroundIntensity { strong, medium, dim }

/// The dark amp-wall photo behind the whole app: atmosphere, never content. `BoxFit.cover` with a
/// top-center focus keeps the pedals/racks in frame on a phone; a gradient fades it into
/// [WyrmTokens.background] so every card and every line of text stays fully readable, and no card
/// needs its own extra scrim. No blur: a gradient overlay costs nothing extra per frame. Flutter's
/// image cache decodes the (single) asset once and reuses it across every screen that shows it.
class WyrmBackground extends StatelessWidget {
  const WyrmBackground({this.intensity = WyrmBackgroundIntensity.medium, super.key});

  static const assetPath = 'assets/images/wyrmtone_amp_wall.webp';

  final WyrmBackgroundIntensity intensity;

  static const _stops = {
    WyrmBackgroundIntensity.strong: [Color(0x700d0f12), Color(0xb80d0f12), WyrmTokens.background],
    WyrmBackgroundIntensity.medium: [Color(0x9d0d0f12), Color(0xd90d0f12), WyrmTokens.background],
    WyrmBackgroundIntensity.dim: [Color(0xc80d0f12), Color(0xec0d0f12), WyrmTokens.background],
  };

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: WyrmTokens.background),
      Image.asset(
        assetPath,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _stops[intensity]!,
            stops: const [0.0, 0.45, 0.85],
          ),
        ),
      ),
    ],
  );
}

class WyrmScaffold extends StatelessWidget {
  const WyrmScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.embedded = false,
    this.background = false,
    this.backgroundIntensity = WyrmBackgroundIntensity.medium,
    super.key,
  });
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool embedded;

  /// True on every screen that is part of the normal journey (see docs): shows the amp-wall
  /// atmosphere behind this page's own content, dosed by [backgroundIntensity].
  final bool background;
  final WyrmBackgroundIntensity backgroundIntensity;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: background ? Colors.transparent : null,
    appBar: embedded ? null : AppBar(title: Text(title), actions: actions, backgroundColor: background ? Colors.transparent : null),
    body: Stack(
      children: [
        if (background) Positioned.fill(child: WyrmBackground(intensity: backgroundIntensity)),
        SafeArea(
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
      ],
    ),
    floatingActionButton: floatingActionButton,
  );
}

class WyrmCard extends StatelessWidget {
  const WyrmCard({required this.child, this.accent = false, this.onTap, this.padding = WyrmTokens.cardPadding, super.key});
  final Widget child;
  final bool accent;

  /// Makes the whole card one touch target.
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: accent
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WyrmTokens.radius),
            side: const BorderSide(color: WyrmTokens.ember),
          )
        : null,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
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
