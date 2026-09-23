import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../midi/p01_read_probe_evaluator.dart';

const matriboxP01FullReadProbeEnabled =
    kDebugMode &&
    bool.fromEnvironment(
      'ENABLE_MATRIBOX_P01_FULL_READ_PROBE',
      defaultValue: false,
    );

/// Separate, single-purpose channel client for the ten-part sequential P01
/// full-read probe (V2). Deliberately NOT merged into
/// [VerifiedMatriboxProbePanel] or the single-request read-probe panel: it
/// never accepts a bank, a slot, a part number or a byte array. Native
/// Kotlin owns the ten immutable fixed requests and the step-by-step
/// send/wait/verify sequencing; this widget only calls the parameterless
/// native method and interprets the returned raw response bytes with the
/// same, unchanged, shared offline decoder/evaluator used by the V1 panel.
class VerifiedP01FullReadProbePanel extends StatefulWidget {
  const VerifiedP01FullReadProbePanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxP01FullReadProbeEnabled,
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;

  @override
  State<VerifiedP01FullReadProbePanel> createState() =>
      _P01FullReadProbePanelState();
}

class _P01FullReadProbePanelState extends State<VerifiedP01FullReadProbePanel>
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
  void didUpdateWidget(VerifiedP01FullReadProbePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionReady != widget.connectionReady ||
        oldWidget.monitoring != widget.monitoring ||
        oldWidget.enabled != widget.enabled) {
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
            'getVerifiedPresetP01FullReadProbeStatus',
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
          _message = 'Diagnose nicht verfügbar: $error. Nichts gesendet.';
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
    setState(() => _busy = true);
    try {
      if (!await _refresh() || !_checked || !mounted) return;
      final generation = _confirmationGeneration;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Jetzt einmalig den P01-Full-Read (10 Teile) senden?',
          ),
          content: const Text(
            'Sonicake Matribox 1 · experimenteller Full-Read-Test (V2)\n'
            'Sendet nacheinander genau die zehn fest einprogrammierten, aus '
            'dem Editor-Capture bestätigten Requests für User-Bank Slot 0 '
            '(P01) — Teil 0 bis Teil 9. Jeder nächste Request wird nur '
            'gesendet, wenn die vorherige Antwort vollständig und '
            'strukturell passend war.\n'
            'Kein Speichern, kein Auswählen, kein Parameterschreiben, keine '
            'Bank-/Slot-/Segmentwahl. Bricht bei Zeitüberschreitung oder '
            'unerwarteter Antwort sofort ab, ohne erneut zu senden.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('p01-full-read-probe-confirm'),
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
      // Intentionally parameterless. Kotlin owns the ten immutable fixed requests.
      final result =
          await _channel.invokeMapMethod<Object?, Object?>(
            'sendVerifiedPresetP01FullReadProbe',
          ) ??
          {};
      if (!mounted) return;
      final nativeSuccess = result['success'] == true;
      final completedParts = result['completedParts'] as int? ?? 0;
      final rawChunks = (result['chunks'] as List<Object?>? ?? [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (chunk) => (chunk['bytes'] as List<Object?>? ?? [])
                .whereType<int>()
                .toList(),
          )
          .toList();
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: nativeSuccess,
        chunks: rawChunks,
      );
      setState(() {
        _logs = (result['logs'] as List<Object?>? ?? [])
            .whereType<String>()
            .toList();
        _message = nativeSuccess
            ? '${_describeVerdict(verdict)}\n(Teile abgeschlossen: '
                  '$completedParts/10${result['stopReason'] != null ? ' — ${result['stopReason']}' : ''})'
            : '${result['error'] ?? 'Test fehlgeschlagen.'} Nichts erneut gesendet.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Test fehlgeschlagen: $error. Nichts erneut gesendet.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describeVerdict(P01ReadProbeVerdict verdict) {
    switch (verdict.outcome) {
      case P01ReadProbeOutcome.confirmed:
        return 'READBACK_CONFIRMED · Presetname und alle sechs Marker stimmen '
            'exakt mit der bestätigten Referenz überein.';
      case P01ReadProbeOutcome.receivedButMismatch:
        final decoded = verdict.decoded!;
        return 'READBACK_RECEIVED_BUT_MISMATCH · Presetname "${decoded.name}" '
            'passt, aber mindestens ein Wert weicht ab. Das heißt nicht, '
            'dass der Request falsch ist — P01 kann seither geändert worden '
            'sein. Dekodiert: Gain ${decoded.gain}, Presence '
            '${decoded.presence}, Volume ${decoded.volume}, Bass '
            '${decoded.bass}, Middle ${decoded.middle}, Treble '
            '${decoded.treble}.';
      case P01ReadProbeOutcome.incomplete:
        return 'READBACK_INCOMPLETE · Es kamen Gerätebytes an, aber kein '
            'vollständiger, namensgleicher Zyklus konnte rekonstruiert '
            'werden (${verdict.observationCount} vollständige SysEx-'
            'Nachrichten erkannt).';
      case P01ReadProbeOutcome.timeout:
        return 'READBACK_TIMEOUT · Innerhalb des Zeitfensters kam keine '
            'Geräteantwort an. Kein erneuter Sendeversuch.';
      case P01ReadProbeOutcome.parseError:
        return 'READBACK_PARSE_ERROR · Empfangene Bytes ließen sich nicht '
            'als vollständige SysEx-Nachricht(en) einordnen.';
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
        key: const Key('verified-p01-full-read-probe-panel'),
        initiallyExpanded: false,
        title: const Text('Experimenteller P01-Full-Read-Einmaltest (V2)'),
        leading: const Icon(Icons.warning_amber),
        onExpansionChanged: (expanded) {
          if (expanded) _refresh();
        },
        childrenPadding: const EdgeInsets.all(12),
        children: [
          const Text(
            'ENTWICKLER-TEST · Sonicake Matribox 1 · 0x84EF:0x0054\n'
            'Sendet nacheinander genau zehn fest einprogrammierte Requests '
            '(Teil 0–9 für User-Bank Slot 0 / P01) und wertet ausschließlich '
            'die Geräteantworten aus.\n'
            'Jeder nächste Request nur nach vollständiger, passender Antwort '
            'auf den vorherigen — kein Retry, sofortiger Abbruch bei '
            'Zeitüberschreitung oder unerwarteter Antwort.\n'
            'Kein Speichern, kein Auswählen, kein Parameterschreiben, keine '
            'Bank-/Slot-/Segmentwahl.',
          ),
          if (!widget.connectionReady)
            const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
          if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Teststatus prüfen'),
          ),
          CheckboxListTile(
            key: const Key('p01-full-read-probe-checkbox'),
            value: _checked,
            onChanged: available
                ? (value) => setState(() => _checked = value == true)
                : null,
            title: const Text(
              'Ich verstehe, dass dies ein experimenteller Lesetest ohne '
              'garantiertes Ergebnis ist.',
            ),
          ),
          FilledButton(
            key: const Key('p01-full-read-probe-send'),
            onPressed: available && _checked ? _confirmAndSend : null,
            child: Text(
              _attempted
                  ? 'Test in dieser Verbindung bereits ausgeführt'
                  : 'Einmalig P01-Full-Read (10 Teile) senden',
            ),
          ),
          if (_message.isNotEmpty) Text(_message),
          if (_logs.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _logs.join('\n'))),
              icon: const Icon(Icons.copy),
              label: const Text('Vollständiges Protokoll kopieren'),
            ),
            SelectableText(_logs.join('\n')),
          ],
        ],
      ),
    );
  }
}
