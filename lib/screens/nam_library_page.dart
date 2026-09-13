import 'package:flutter/material.dart';

import '../controllers/tone3000_controller.dart';
import '../nam/local_nam_capture.dart';
import '../tone3000/tone3000_models.dart';

class NamLibraryPage extends StatefulWidget {
  const NamLibraryPage({required this.controller, super.key});
  final Tone3000Controller controller;
  @override
  State<NamLibraryPage> createState() => _NamLibraryPageState();
}

class _NamLibraryPageState extends State<NamLibraryPage> {
  String query = '';
  NamArchitecture? architecture;
  NamCompatibility? compatibility;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final selection = controller.namSelection;
      final captures = controller.namCaptures.where((c) {
        final text =
            '${c.captureName} ${c.creatorName} ${c.make ?? ''} ${c.tags.join(' ')}'
                .toLowerCase();
        return text.contains(query.toLowerCase()) &&
            (architecture == null || c.architecture == architecture) &&
            (compatibility == null || c.compatibility == compatibility);
      }).toList();
      return Scaffold(
        appBar: AppBar(title: const Text('NAM-Bibliothek')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sonicake Matribox 1',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'NAM A1: kompatibel\nNAM A2/A2-Lite: Geräteunterstützung noch nicht bestätigt\nÜbertragung zur Matribox: noch nicht verfügbar\nUSB-Protokoll: unbestätigt',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('tone3000-browse-nam'),
                      onPressed: controller.busy
                          ? null
                          : () => controller.connectOrBrowse(
                              mode: Tone3000SelectionMode.namA1,
                            ),
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('NAM-A1 bei TONE3000 auswählen'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('import-nam-file'),
                      onPressed: controller.busy ? null : controller.importNam,
                      icon: const Icon(Icons.file_open),
                      label: const Text('Lokale .nam-Datei importieren'),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.message != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(controller.message!),
              ),
            if (selection != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selection.tone.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            key: const Key('tone3000-close-nam-selection'),
                            onPressed: controller.closeNamSelection,
                            tooltip: 'NAM-Auswahl schließen',
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Text(
                        '${selection.tone.creatorName} · Lizenz: ${selection.tone.license}',
                      ),
                      for (final model in selection.models)
                        _NamModelTile(controller: controller, model: model),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'NAM durchsuchen',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            Wrap(
              spacing: 8,
              children: [
                DropdownButton<NamArchitecture?>(
                  value: architecture,
                  hint: const Text('Architektur'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Alle Architekturen'),
                    ),
                    ...NamArchitecture.values.map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.name)),
                    ),
                  ],
                  onChanged: (v) => setState(() => architecture = v),
                ),
                DropdownButton<NamCompatibility?>(
                  value: compatibility,
                  hint: const Text('Kompatibilität'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Alle Status'),
                    ),
                    ...NamCompatibility.values.map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.name)),
                    ),
                  ],
                  onChanged: (v) => setState(() => compatibility = v),
                ),
              ],
            ),
            if (captures.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Noch keine lokalen NAM-Captures.'),
                ),
              )
            else
              for (final capture in captures)
                Card(
                  child: ListTile(
                    title: Text(capture.captureName),
                    subtitle: Text(
                      '${capture.creatorName} · Lizenz: ${capture.license}\n${capture.architecture.name.toUpperCase()} · ${capture.compatibility.name} · ${capture.fileSize} Byte\nZiel: Matribox 1 · ${capture.compatibility == NamCompatibility.missingLocalFile ? 'lokale Datei fehlt' : 'lokal vorhanden'}\n${capture.attribution}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Lokales NAM löschen',
                      onPressed: () => _confirmDelete(context, capture),
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );

  Future<void> _confirmDelete(
    BuildContext context,
    LocalNamCapture capture,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('NAM-Capture löschen?'),
        content: Text('${capture.captureName} wird nur lokal gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.controller.deleteNam(capture);
  }
}

class _NamModelTile extends StatelessWidget {
  const _NamModelTile({required this.controller, required this.model});
  final Tone3000Controller controller;
  final Tone3000Model model;
  @override
  Widget build(BuildContext context) {
    final busy = controller.downloadingModelId == model.id;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.name),
            Text(
              'Architektur: ${model.architectureVersion ?? 'unbekannt'} · nur A1 wird angeboten',
            ),
            if (busy) ...[
              LinearProgressIndicator(value: controller.downloadProgress),
              TextButton(
                onPressed: controller.cancelDownload,
                child: const Text('Download abbrechen'),
              ),
            ] else
              FilledButton.tonalIcon(
                key: Key('nam-download-${model.id}'),
                onPressed: () => _download(context),
                icon: const Icon(Icons.download),
                label: const Text('NAM herunterladen'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final ok = await controller.downloadNam(model);
    if (ok ||
        !context.mounted ||
        !(controller.message?.startsWith('NAM_EXISTS:') ?? false)) {
      return;
    }
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Datei vorhanden'),
        content: const Text('Vorhandenes NAM-Capture ersetzen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ersetzen'),
          ),
        ],
      ),
    );
    if (replace == true) {
      await controller.downloadNam(model, replaceExisting: true);
    }
  }
}
