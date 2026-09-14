import 'package:flutter/material.dart';

import '../controllers/tone3000_controller.dart';
import '../nam/local_nam_capture.dart';
import '../tone3000/tone3000_models.dart';
import '../ui/wyrm_design.dart';

class NamLibraryPage extends StatefulWidget {
  const NamLibraryPage({
    required this.controller,
    this.embedded = false,
    this.targetSupportsNam = true,
    super.key,
  });
  final Tone3000Controller controller;
  final bool embedded, targetSupportsNam;
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
      return WyrmScaffold(
        title: 'NAM-Bibliothek',
        embedded: widget.embedded,
        body: ListView(
          key: const Key('nam-library-list'),
          padding: const EdgeInsets.all(16),
          children: [
            const WyrmSection(
              title: 'Neural Amp Models',
              subtitle: 'Amp-Captures · NAM · Keine Geräteübertragung',
              child: SizedBox.shrink(),
            ),
            if (!widget.targetSupportsNam)
              const WyrmStatusBadge(
                'Gewähltes Zielgerät unterstützt kein NAM',
                warning: true,
              ),
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
                SizedBox(
                  width: double.infinity,
                  child: DropdownButton<NamArchitecture?>(
                    isExpanded: true,
                    value: architecture,
                    hint: const Text('Architektur'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Alle Architekturen'),
                      ),
                      ...NamArchitecture.values.map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == NamArchitecture.unknown
                                ? 'Unbekannt'
                                : v.name.toUpperCase(),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => architecture = v),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: DropdownButton<NamCompatibility?>(
                    isExpanded: true,
                    value: compatibility,
                    hint: const Text('Kompatibilität'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Alle Status'),
                      ),
                      ...NamCompatibility.values.map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(compatibilityLabel(v)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => compatibility = v),
                  ),
                ),
              ],
            ),
            if (captures.isEmpty)
              const WyrmEmptyState(
                title: 'Noch keine lokalen NAM-Captures.',
                message: 'Importiere eine vorhandene .nam-Datei oder wähle bei TONE3000 gezielt ein A1-Modell.',
              )
            else
              for (final capture in captures)
                Card(
                  child: ListTile(
                    title: Text(capture.captureName),
                    subtitle: Text(
                      'NAM · ${capture.source == 'local' ? 'Lokaler Import' : capture.source} · ${capture.creatorName} · Lizenz: ${capture.license.isEmpty ? 'unbekannt' : capture.license}\n${capture.architecture.name.toUpperCase()} · ${widget.targetSupportsNam ? compatibilityLabel(capture.compatibility) : 'Zielgerät nicht unterstützt'} · ${capture.fileSize} Byte\nZiel: Matribox 1 · ${capture.compatibility == NamCompatibility.missingLocalFile ? 'lokale Datei fehlt' : 'lokal vorhanden'}\n${capture.attribution}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Lokales NAM löschen',
                      onPressed: () => _confirmDelete(context, capture),
                    ),
                  ),
                ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WyrmTone3000Header(controller: controller),
                    const Text(
                      'Matribox 1: NAM A1 kompatibel · A2 unbestätigt · Keine Geräteübertragung.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('tone3000-browse-nam'),
                      onPressed: controller.busy || !controller.isConfigured
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
            if (tone3000VisibleMessage(controller) != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(tone3000VisibleMessage(controller)!),
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
