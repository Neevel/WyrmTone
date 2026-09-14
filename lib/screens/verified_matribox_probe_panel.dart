import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const matriboxWriteProbeEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_MATRIBOX_WRITE_PROBE', defaultValue: false);

/// Separate fixed-operation channel client; never accepts a payload or target value.
class VerifiedMatriboxProbePanel extends StatefulWidget {
  const VerifiedMatriboxProbePanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxWriteProbeEnabled,
    super.key,
  });
  final bool connectionReady;
  final bool monitoring;
  final bool enabled;

  @override
  State<VerifiedMatriboxProbePanel> createState() => _ProbePanelState();
}

class _ProbePanelState extends State<VerifiedMatriboxProbePanel>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  bool _checked = false;
  bool _busy = false;
  bool _attempted = false;
  bool _nativeReady = false;
  Object? _connection;
  Object? _sessionToken;
  String _message = '';
  List<String> _logs = [];
  int _confirmationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(VerifiedMatriboxProbePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionReady != widget.connectionReady ||
        oldWidget.monitoring != widget.monitoring) {
      _checked = false;
      _nativeReady = false;
      ++_confirmationGeneration;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ++_confirmationGeneration;
      if (mounted) {
        setState(() {
          _checked = false;
          _nativeReady = false;
        });
      }
    }
  }

  Future<bool> _refresh() async {
    try {
      final status =
          await _channel.invokeMapMethod<Object?, Object?>(
            'getVerifiedMatriboxProbeStatus',
          ) ??
          {};
      if (!mounted) return false;
      setState(() {
        if (_connection != status['connection'] ||
            _sessionToken != status['sessionToken']) {
          _checked = false;
          ++_confirmationGeneration;
        }
        _connection = status['connection'];
        _sessionToken = status['sessionToken'];
        _attempted = status['attempted'] == true;
        _nativeReady = status['enabled'] == true && status['ready'] == true;
        _logs = (status['logs'] as List<Object?>? ?? [])
            .whereType<String>()
            .toList();
      });
      return _nativeReady && !_attempted;
    } catch (error) {
      if (mounted) {
        setState(() {
          _nativeReady = false;
          _message =
              'Diagnose nicht verfügbar: $error. Es wurde kein weiterer Sendeversuch durchgeführt.';
        });
      }
      return false;
    }
  }

  Future<void> _confirmAndSend() async {
    if (_busy ||
        !_checked ||
        _attempted ||
        !widget.connectionReady ||
        widget.monitoring) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      if (!await _refresh() || !_checked || !mounted) return;
      final generation = _confirmationGeneration;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Jetzt einmalig Gain 41 an die Matribox senden?'),
          content: const Text(
            'Sonicake Matribox 1 · Sol 100 OD · Gain-Index 0\n'
            'Manuell bestätigter Ausgangswert 40 → Zielwert 41.\n'
            'Genau eine Nachricht. Kein Speichern, kein automatisches Zurücksetzen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('probe-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bewusst einmalig senden'),
            ),
          ],
        ),
      );
      if (accepted != true ||
          !mounted ||
          generation != _confirmationGeneration) {
        return;
      }
      if (!await _refresh() ||
          !mounted ||
          generation != _confirmationGeneration ||
          !_checked ||
          !widget.connectionReady ||
          widget.monitoring) {
        return;
      }
      setState(() {
        _attempted = true;
        _checked = false;
      });
      // Intentionally parameterless. Kotlin owns the immutable verified message.
      final result =
          await _channel.invokeMapMethod<Object?, Object?>(
            'sendVerifiedSol100OdGain41Probe',
          ) ??
          {};
      if (!mounted) return;
      setState(() {
        _logs = (result['logs'] as List<Object?>? ?? [])
            .whereType<String>()
            .toList();
        _message = result['success'] == true
            ? 'Android hat die Bytes angenommen. Gain 41 jetzt am Matribox-Display manuell prüfen.'
            : '${result['error'] ?? 'Test fehlgeschlagen.'} Es wurde kein weiterer Sendeversuch durchgeführt.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message =
              'Test fehlgeschlagen: $error. Es wurde kein weiterer Sendeversuch durchgeführt.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final available =
        widget.connectionReady &&
        !widget.monitoring &&
        _nativeReady &&
        !_attempted &&
        !_busy;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ExpansionTile(
        key: const Key('verified-probe-panel'),
        initiallyExpanded: false,
        title: const Text('Verifizierter Matribox-Schreibtest'),
        leading: const Icon(Icons.warning_amber),
        onExpansionChanged: (expanded) {
          if (expanded) _refresh();
        },
        childrenPadding: const EdgeInsets.all(12),
        children: [
          const Text(
            'ENTWICKLER-TEST · Sonicake Matribox 1 · 0x84EF:0x0054\n'
            'Sol 100 OD · Gain-Index 0 · 40 → 41\n'
            'Ändert den aktuellen Geräteparameter einmalig und speichert kein Preset.\n'
            'Vorher ein unwichtiges Testpreset wählen und Sol 100 OD mit Gain 40 einstellen.\n'
            'Der aktuelle Gerätezustand kann von WyrmTone noch nicht verifiziert werden.',
          ),
          if (!widget.connectionReady)
            const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
          if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Teststatus prüfen'),
          ),
          CheckboxListTile(
            key: const Key('probe-checkbox'),
            value: _checked,
            onChanged: available
                ? (value) => setState(() {
                    _checked = value == true;
                  })
                : null,
            title: const Text(
              'Ich habe ein unwichtiges Testpreset gewählt und Sol 100 OD mit Gain 40 eingestellt.',
            ),
          ),
          FilledButton(
            key: const Key('probe-send'),
            onPressed: available && _checked ? _confirmAndSend : null,
            child: Text(
              _attempted
                  ? 'Test in dieser Verbindung bereits ausgeführt'
                  : 'Einmalig Gain 41 senden',
            ),
          ),
          if (_message.isNotEmpty) Text(_message),
          if (_logs.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _logs.join('\n'))),
              icon: const Icon(Icons.copy),
              label: const Text('Schreibtest-Protokoll kopieren'),
            ),
            SelectableText(_logs.join('\n')),
          ],
        ],
      ),
    );
  }
}
