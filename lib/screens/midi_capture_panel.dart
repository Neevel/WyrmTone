import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../midi/midi_capture_controller.dart';
import '../midi/midi_receive_source.dart';
import '../ui/wyrm_design.dart';

class MidiCapturePanel extends StatelessWidget {
  const MidiCapturePanel({required this.controller, this.exporter, super.key});
  final MidiCaptureController controller;
  final MidiCaptureExporter? exporter;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      final active = c.state == MidiCaptureState.monitoring;
      final stopping = c.state == MidiCaptureState.stopping;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Passive MIDI-Diagnose',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(c.deviceName ?? 'Keine eindeutig zugeordnete Matribox'),
              Text(
                'Status: ${midiCaptureStatusLabel(c.state)} · Output-Port: ${c.outputPort ?? 'geschlossen'}',
              ),
              if (c.error != null) Text(c.error!),
              const Text('Nur Empfang – WyrmTone sendet keine MIDI-Daten'),
              if (kDebugMode) ...[
                SwitchListTile(
                  key: const Key('capture-debug-log'),
                  title: const Text('Live-Debug-Log über ADB'),
                  subtitle: const Text(
                    'Optional: empfangene Rohdaten im Android-Debug-Log. '
                    'Für verbundene Debugging-Werkzeuge sichtbar; unbekannte SysEx können sensible Geräteinformationen enthalten. '
                    'Max. 20 Zeilen/s und 256 Byte je Nachricht. Stop/Pause schaltet es aus.',
                  ),
                  value: c.debugLogging,
                  onChanged: active ? c.setDebugLogging : null,
                ),
                if (c.debugLogDropped > 0)
                  Text(
                    'Nur Debug-Log: ${c.debugLogDropped} Zeilen unterdrückt; JSON-Export bleibt unabhängig.',
                  ),
              ],
              Text(
                'Empfangene Chunks: ${c.chunkCount} · Bytes: ${c.byteCount}',
              ),
              Text(
                'Vollständige SysEx: ${c.completeSysExCount} · Unvollständig/verworfen: ${c.incompleteCount} · Noch offen: ${c.pendingMessageCount}',
              ),
              Text('Lokal klassifizierte Nachrichten: ${c.messageCount}'),
              Text(
                'Startzeit: ${c.startedAt?.toLocal().toIso8601String() ?? 'Noch nicht gestartet'}',
              ),
              if (c.droppedEntries > 0 || c.droppedChunks > 0)
                Text(
                  'Begrenzt: ${c.droppedEntries} alte Einträge und ${c.droppedChunks} Empfangs-Chunks verworfen.',
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('capture-start'),
                    onPressed: c.state == MidiCaptureState.deviceOpened
                        ? c.start
                        : null,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Passive MIDI-Beobachtung starten'),
                  ),
                  OutlinedButton(
                    key: const Key('capture-stop'),
                    onPressed: active || c.state == MidiCaptureState.error
                        ? c.stop
                        : null,
                    child: const Text('Passive MIDI-Beobachtung stoppen'),
                  ),
                  OutlinedButton(
                    key: const Key('capture-marker'),
                    onPressed: stopping ? null : () => _marker(context),
                    child: const Text('Markierung setzen'),
                  ),
                  TextButton(
                    key: const Key('capture-clear'),
                    onPressed: stopping ? null : c.clear,
                    child: const Text('Anzeige leeren'),
                  ),
                  OutlinedButton(
                    key: const Key('capture-export'),
                    onPressed: c.entries.isEmpty || stopping
                        ? null
                        : () => _export(context),
                    child: const Text('Diagnose exportieren (JSON)'),
                  ),
                ],
              ),
              const Text(
                'Export stoppt die Beobachtung. Androids Dateiauswahl kann das MIDI-Gerät schließen; danach ausdrücklich neu öffnen/starten.',
              ),
              _log(
                'Empfangene Chunks (RX)',
                c.entries.where((e) => e.kind == 'chunk').toList(),
              ),
              _log(
                'Lokal klassifizierte Nachrichten / zusammengesetzte SysEx',
                c.entries.where((e) => e.kind == 'message').toList(),
              ),
              _log(
                'Markierungen und Empfangslücken',
                c.entries
                    .where((e) => e.kind == 'marker' || e.kind == 'loss')
                    .toList(),
              ),
              const Text(
                'Live-Ansicht: höchstens 25 Einträge je Bereich, Hexvorschau höchstens 256 Byte. JSON enthält den gesamten verbliebenen Ringpuffer.',
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _log(String title, List<MidiCaptureEntry> entries) => ExpansionTile(
    title: Text('$title (${entries.length})'),
    children: entries.reversed
        .take(25)
        .toList()
        .reversed
        .map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                '#${e.sequence} · ${e.at.toLocal().toIso8601String()} · ${e.bytes.length} Byte\n'
                '${e.type} · ${e.status}'
                '${e.marker == null ? '' : '\nMARKER: ${e.marker}'}'
                '${e.bytes.isEmpty ? '' : '\n${e.bytes.take(256).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}${e.bytes.length > 256 ? ' …' : ''}'}',
              ),
            ),
          ),
        )
        .toList(),
  );
  Future<void> _marker(BuildContext context) async {
    final field = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lokale Testmarkierung'),
        content: TextField(
          controller: field,
          maxLength: 120,
          maxLines: 1,
          decoration: const InputDecoration(hintText: 'z. B. Gain 40 → 41'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Setzen'),
          ),
        ],
      ),
    );
    // Allow the dialog route's exit animation to release its TextField first.
    if (text != null) controller.addMarker(text);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    field.dispose();
  }

  Future<void> _export(BuildContext context) async {
    await controller.stop();
    final json = controller.exportJson();
    try {
      final saved = await (exporter ?? AndroidMidiCaptureExporter()).exportJson(
        json,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved ? 'JSON-Diagnose gespeichert.' : 'Export abgebrochen.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnoseexport fehlgeschlagen.')),
        );
      }
    }
  }
}
