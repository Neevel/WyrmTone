import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../midi/p01_read_probe_evaluator.dart';

const matriboxP01FullReadProbeV3AEnabled =
    kDebugMode &&
    bool.fromEnvironment(
      'ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A',
      defaultValue: false,
    );

/// Separate, single-purpose channel client for the V3A hypothesis test:
/// does the confirmed "Phase D" announce/acknowledge pair alone (no Ping,
/// no Capability query, no metadata enumeration) establish the context an
/// isolated ten-part P01 read needs? Deliberately NOT merged into the V2
/// panel or any other probe panel: it never accepts a bank, a slot, a part
/// number or a byte array. Native Kotlin owns the one fixed Phase-D
/// announce and the ten fixed part requests (already confirmed for V2);
/// this widget only calls the parameterless native method and interprets
/// the returned raw response bytes with the same, unchanged, shared
/// offline decoder/evaluator used by the V1 and V2 panels.
class VerifiedP01FullReadProbeV3APanel extends StatefulWidget {
  const VerifiedP01FullReadProbeV3APanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxP01FullReadProbeV3AEnabled,
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;

  @override
  State<VerifiedP01FullReadProbeV3APanel> createState() =>
      _P01FullReadProbeV3APanelState();
}

class _P01FullReadProbeV3APanelState
    extends State<VerifiedP01FullReadProbeV3APanel>
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
  void didUpdateWidget(VerifiedP01FullReadProbeV3APanel oldWidget) {
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
            'getVerifiedPresetP01FullReadProbeV3AStatus',
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
            'Jetzt einmalig Phase D + P01-Full-Read (V3A) senden?',
          ),
          content: const Text(
            'Sonicake Matribox 1 · experimenteller Hypothesentest (V3A)\n'
            'Sendet zuerst den bestätigten Phase-D-Announce für User-Bank '
            'Slot 0 (P01) und wartet auf eine vollständige, strukturell '
            'passende Bestätigung. Nur wenn diese ankommt, folgen '
            'nacheinander die zehn bereits bestätigten Teil-Requests (Teil '
            '0–9) — jeder nur nach passender Antwort auf den vorherigen.\n'
            'Kein Ping, keine Capability-Abfrage, keine Metadaten-'
            'Enumeration. Kein Speichern, kein Auswählen, kein '
            'Parameterschreiben, keine Bank-/Slot-/Segmentwahl. Bricht bei '
            'Zeitüberschreitung oder unerwarteter Antwort sofort ab, ohne '
            'erneut zu senden oder auf einen größeren Präambel-Kandidaten '
            'umzuschalten.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('p01-full-read-probe-v3a-confirm'),
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
      // Intentionally parameterless. Kotlin owns the fixed Phase-D announce
      // and the ten fixed part requests.
      final result =
          await _channel.invokeMapMethod<Object?, Object?>(
            'sendVerifiedPresetP01FullReadProbeV3A',
          ) ??
          {};
      if (!mounted) return;
      final nativeSuccess = result['success'] == true;
      final phaseDConfirmed = result['phaseDConfirmed'] == true;
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
            ? '${_describeVerdict(verdict, phaseDConfirmed)}\n'
                  '(Phase D bestätigt: $phaseDConfirmed · Teile abgeschlossen: '
                  '$completedParts/10'
                  '${result['stopReason'] != null ? ' — ${result['stopReason']}' : ''})'
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

  String _describeVerdict(P01ReadProbeVerdict verdict, bool phaseDConfirmed) {
    if (!phaseDConfirmed) {
      return 'READBACK_INCOMPLETE_PHASE_D · Phase D wurde nicht bestätigt — '
          'die Hypothese "Phase D allein reicht aus" ist damit für diesen '
          'Versuch widerlegt oder unentschieden (siehe Protokoll für '
          'Timeout vs. unerwartete Antwort).';
    }
    switch (verdict.outcome) {
      case P01ReadProbeOutcome.confirmed:
        return 'READBACK_CONFIRMED · Phase D hat den Kontext hergestellt: '
            'Presetname und alle sechs Marker stimmen exakt mit der '
            'bestätigten Referenz überein.';
      case P01ReadProbeOutcome.receivedButMismatch:
        final decoded = verdict.decoded!;
        return 'READBACK_RECEIVED_BUT_MISMATCH · Presetname "${decoded.name}" '
            'passt, aber mindestens ein Wert weicht ab. Das heißt nicht, '
            'dass Phase D oder der Request falsch ist — P01 kann seither '
            'geändert worden sein. Dekodiert: Gain ${decoded.gain}, '
            'Presence ${decoded.presence}, Volume ${decoded.volume}, Bass '
            '${decoded.bass}, Middle ${decoded.middle}, Treble '
            '${decoded.treble}.';
      case P01ReadProbeOutcome.incomplete:
        return 'READBACK_INCOMPLETE_PART_N · Phase D wurde bestätigt, aber '
            'nicht alle zehn Teile kamen strukturell passend an '
            '(${verdict.observationCount} vollständige SysEx-Nachrichten '
            'erkannt).';
      case P01ReadProbeOutcome.timeout:
        return 'READBACK_INCOMPLETE_PART_N · Phase D wurde bestätigt, aber '
            'danach kam keine Geräteantwort mehr an.';
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
        key: const Key('verified-p01-full-read-probe-v3a-panel'),
        initiallyExpanded: false,
        title: const Text('Experimenteller P01-Full-Read-Einmaltest (V3A)'),
        leading: const Icon(Icons.warning_amber),
        onExpansionChanged: (expanded) {
          if (expanded) _refresh();
        },
        childrenPadding: const EdgeInsets.all(12),
        children: [
          const Text(
            'ENTWICKLER-TEST · Sonicake Matribox 1 · 0x84EF:0x0054\n'
            'Testet die Hypothese: Der bestätigte Phase-D-Announce/Ack '
            '(Bank=User, Slot=0/P01) allein — ohne Ping, ohne Capability-'
            'Abfrage, ohne Metadaten-Enumeration — stellt den Kontext für '
            'einen isolierten Zehn-Teile-Read her.\n'
            'Erst nach bestätigtem Phase-D-Ack folgen die zehn bereits aus '
            'V2 bekannten Teil-Requests, jeder nur nach passender Antwort '
            'auf den vorherigen.\n'
            'Kein Speichern, kein Auswählen, kein Parameterschreiben, keine '
            'Bank-/Slot-/Segmentwahl. Kein automatischer Rückfall auf einen '
            'größeren Präambel-Kandidaten.',
          ),
          if (!widget.connectionReady)
            const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
          if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Teststatus prüfen'),
          ),
          CheckboxListTile(
            key: const Key('p01-full-read-probe-v3a-checkbox'),
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
            key: const Key('p01-full-read-probe-v3a-send'),
            onPressed: available && _checked ? _confirmAndSend : null,
            child: Text(
              _attempted
                  ? 'Test in dieser Verbindung bereits ausgeführt'
                  : 'Einmalig Phase D + P01-Full-Read (V3A) senden',
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
