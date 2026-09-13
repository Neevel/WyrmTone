import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tone3000/local_ir_record.dart';
import '../tone3000/local_ir_file_actions.dart';
import '../tone3000/local_ir_repository.dart';
import '../tone3000/tone3000_api_client.dart';
import '../tone3000/tone3000_browser.dart';
import '../tone3000/tone3000_config.dart';
import '../tone3000/tone3000_download_service.dart';
import '../tone3000/tone3000_http.dart';
import '../tone3000/tone3000_models.dart';
import '../tone3000/tone3000_oauth.dart';
import '../tone3000/wav_validator.dart';
import '../nam/local_nam_capture.dart';
import '../nam/nam_download_service.dart';
import '../nam/nam_repository.dart';
import '../nam/nam_import_service.dart';

class Tone3000Controller extends ChangeNotifier {
  Tone3000Controller({
    required this.config,
    required this.browser,
    required this.oauth,
    required this.sessionManager,
    required this.api,
    required this.downloader,
    required this.localRepository,
    LocalIrFileActions? fileActions,
    this.namDownloader,
    this.namRepository,
    this.namImporter,
  }) : fileActions = fileActions ?? const PlatformLocalIrFileActions();

  final Tone3000Config config;
  final Tone3000Browser browser;
  final Tone3000OAuthService oauth;
  final Tone3000SessionManager sessionManager;
  final Tone3000Api api;
  final Tone3000Downloader downloader;
  final LocalIrRepository localRepository;
  final LocalIrFileActions fileActions;
  final NamDownloader? namDownloader;
  final NamRepository? namRepository;
  final NamImportService? namImporter;

  StreamSubscription<Uri>? _callbackSubscription;
  Tone3000User? user;
  Tone3000Selection? selection;
  Tone3000Selection? namSelection;
  List<LocalIrRecord> localRecords = const [];
  List<LocalNamCapture> namCaptures = const [];
  bool busy = false;
  String? message;
  int? downloadingModelId;
  double? downloadProgress;
  Tone3000CancellationToken? _cancellationToken;

  bool get isConfigured => config.isConfigured;
  bool get isConnected => user != null;

  Future<void> initialize() async {
    _callbackSubscription = browser.callbacks.listen(
      (callback) => unawaited(handleCallback(callback)),
    );
    localRecords = await localRepository.load();
    await _reloadNamCaptures();
    if (!config.isConfigured) {
      message = config.validationMessage;
      notifyListeners();
      return;
    }
    try {
      if (await sessionManager.hasSession) user = await api.getCurrentUser();
    } on Tone3000ReauthenticationRequired {
      await sessionManager.disconnect();
      message = 'Die TONE3000-Anmeldung ist abgelaufen.';
    } catch (_) {
      message = 'TONE3000-Status konnte nicht geprüft werden.';
    }
    notifyListeners();
  }

  Future<void> connectOrBrowse({
    Tone3000SelectionMode mode = Tone3000SelectionMode.ir,
  }) async {
    if (busy) return;
    try {
      message = null;
      await oauth.startSelectTone(mode: mode);
      message = 'TONE3000 wurde im Systembrowser geöffnet.';
    } catch (error) {
      message = _safeMessage(error);
    }
    notifyListeners();
  }

  Future<void> handleCallback(Uri callback) async {
    if (busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final result = await _stage(
        'AUTH-CALLBACK',
        'Der TONE3000-Rücksprung konnte nicht verarbeitet werden.',
        () => oauth.handleCallback(callback),
      );
      if (result.canceled) {
        message = 'TONE3000-Auswahl abgebrochen.';
        return;
      }
      user = await _stage(
        'USER',
        'Das TONE3000-Konto konnte nicht geladen werden.',
        api.getCurrentUser,
      );
      final tone = await _stage(
        'TONE',
        'Der ausgewählte TONE3000-Tone konnte nicht geladen werden.',
        () => api.getTone(result.toneId!),
      );
      final expectedNam = result.selectionMode == Tone3000SelectionMode.namA1;
      if ((!expectedNam && !tone.isImpulseResponse) ||
          (expectedNam && !tone.isNam)) {
        throw const Tone3000ApiException(
          'Die Auswahl ist kein IR-Tone und wird nicht angezeigt.',
        );
      }
      final models = await _stage(
        'MODELS',
        'Die TONE3000-Modelle konnten nicht geladen werden.',
        () => api.listModels(tone.id),
      );
      final compatibleModels = expectedNam
          ? models
                .where(
                  (model) =>
                      namArchitectureFromApi(model.architectureVersion) ==
                      NamArchitecture.a1,
                )
                .toList()
          : models;
      if (expectedNam) {
        namSelection = Tone3000Selection(tone: tone, models: compatibleModels);
      } else {
        selection = Tone3000Selection(tone: tone, models: compatibleModels);
      }
      message = compatibleModels.isEmpty
          ? 'Der ausgewählte IR-Tone enthält keine kompatiblen Modelle.'
          : '${compatibleModels.length} ${expectedNam ? 'NAM-A1-Capture(s)' : 'IR-Modell(e)'} von TONE3000 geladen.';
    } catch (error) {
      message = _safeMessage(error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await sessionManager.disconnect();
    user = null;
    selection = null;
    namSelection = null;
    message = 'TONE3000-Verbindung getrennt.';
    notifyListeners();
  }

  Future<bool> downloadModel(
    Tone3000Model model, {
    bool replaceExisting = false,
  }) async {
    final tone = selection?.tone;
    if (tone == null || downloadingModelId != null) return false;
    downloadingModelId = model.id;
    downloadProgress = 0;
    message = null;
    final cancellation = Tone3000CancellationToken();
    _cancellationToken = cancellation;
    notifyListeners();
    try {
      final accessToken = await sessionManager.accessToken();
      final result = await downloader.download(
        tone: tone,
        model: model,
        accessToken: accessToken,
        replaceExisting: replaceExisting,
        cancellationToken: cancellation,
        onProgress: (received, total) {
          downloadProgress = total == null || total == 0
              ? null
              : received / total;
          notifyListeners();
        },
      );
      localRecords = await localRepository.load();
      message = result.isDuplicate
          ? 'IR gespeichert und als inhaltliches Duplikat markiert.'
          : 'IR sicher gespeichert. Creator und Lizenz wurden übernommen.';
      return true;
    } on ExistingIrFileException catch (error) {
      message = 'EXISTS:${error.fileName}';
      return false;
    } on Tone3000Canceled {
      message = 'Download abgebrochen; unvollständige Datei entfernt.';
      return false;
    } catch (error) {
      message = _safeMessage(error);
      return false;
    } finally {
      downloadingModelId = null;
      downloadProgress = null;
      _cancellationToken = null;
      notifyListeners();
    }
  }

  void cancelDownload() => _cancellationToken?.cancel();

  void closeSelection() {
    if (downloadingModelId != null) return;
    selection = null;
    message = null;
    notifyListeners();
  }

  void closeNamSelection() {
    if (downloadingModelId != null) return;
    namSelection = null;
    message = null;
    notifyListeners();
  }

  Future<bool> downloadNam(
    Tone3000Model model, {
    bool replaceExisting = false,
  }) async {
    final tone = namSelection?.tone;
    final service = namDownloader;
    if (tone == null || service == null || downloadingModelId != null) {
      return false;
    }
    downloadingModelId = model.id;
    downloadProgress = 0;
    message = null;
    final cancellation = Tone3000CancellationToken();
    _cancellationToken = cancellation;
    notifyListeners();
    try {
      await service.download(
        tone: tone,
        model: model,
        accessToken: await sessionManager.accessToken(),
        replaceExisting: replaceExisting,
        cancellationToken: cancellation,
        onProgress: (received, total) {
          downloadProgress = total == null || total == 0
              ? null
              : received / total;
          notifyListeners();
        },
      );
      await _reloadNamCaptures();
      message =
          'NAM-A1-Capture lokal gespeichert und für Matribox 1 vorgemerkt.';
      return true;
    } on ExistingNamFileException catch (error) {
      message = 'NAM_EXISTS:${error.fileName}';
      return false;
    } on Tone3000Canceled {
      message = 'NAM-Download abgebrochen; unvollständige Datei entfernt.';
      return false;
    } on NamValidationException catch (error) {
      message = 'NAM ungültig: ${error.message}';
      return false;
    } catch (error) {
      message = _safeMessage(error);
      return false;
    } finally {
      downloadingModelId = null;
      downloadProgress = null;
      _cancellationToken = null;
      notifyListeners();
    }
  }

  Future<void> deleteNam(LocalNamCapture capture) async {
    final uri = Uri.parse(capture.localUri);
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (await file.exists()) await file.delete();
    }
    await namRepository?.remove(capture.localId);
    await _reloadNamCaptures();
    message = 'Lokales NAM-Capture gelöscht.';
    notifyListeners();
  }

  Future<void> importNam() async {
    final importer = namImporter;
    if (importer == null || busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final capture = await importer.import();
      await _reloadNamCaptures();
      message = capture == null ? 'NAM-Import abgebrochen.' : 'NAM-Datei lokal importiert; Architektur und Kompatibilität bleiben unbekannt.';
    } on NamValidationException catch (error) {
      message = 'NAM ungültig: ${error.message}';
    } catch (_) {
      message = 'NAM-Datei konnte nicht importiert werden.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> openLocalIr(LocalIrRecord record) async {
    try {
      await fileActions.open(record.localUri);
    } catch (_) {
      message = 'Die lokale IR-Datei konnte nicht geöffnet werden.';
      notifyListeners();
    }
  }

  Future<void> _reloadNamCaptures() async {
    final repository = namRepository;
    if (repository == null) {
      namCaptures = const [];
      return;
    }
    final loaded = await repository.load();
    final checked = <LocalNamCapture>[];
    var changed = false;
    for (final capture in loaded) {
      final uri = Uri.tryParse(capture.localUri);
      final exists = uri?.scheme == 'file' && await File.fromUri(uri!).exists();
      final expected = exists
          ? matriboxCompatibility(capture.architecture)
          : NamCompatibility.missingLocalFile;
      if (capture.compatibility != expected) changed = true;
      checked.add(
        capture.compatibility == expected
            ? capture
            : capture.withCompatibility(expected),
      );
    }
    namCaptures = checked;
    if (changed) await repository.save(checked);
  }

  Future<void> exportLocalIr(LocalIrRecord record) async {
    try {
      final exported = await fileActions.export(
        record.localUri,
        record.fileName,
      );
      message = exported
          ? 'IR-Datei wurde in den ausgewählten Ordner exportiert.'
          : 'Export abgebrochen.';
    } catch (_) {
      message = 'Die lokale IR-Datei konnte nicht exportiert werden.';
    }
    notifyListeners();
  }

  Future<T> _stage<T>(
    String code,
    String fallbackMessage,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on Tone3000AuthException {
      rethrow;
    } on Tone3000ApiException {
      rethrow;
    } catch (error) {
      // Only the exception type is logged. OAuth codes, tokens and response
      // payloads must never reach logs or user-visible diagnostics.
      debugPrint('TONE3000 $code failed: ${error.runtimeType}');
      throw Tone3000ApiException('$fallbackMessage ($code)');
    }
  }

  String _safeMessage(Object error) => switch (error) {
    Tone3000AuthException(:final message) => message,
    Tone3000ApiException(:final message) => message,
    WavValidationException(:final message) => 'Ungültig/inkompatibel: $message',
    StateError(:final message) => message,
    _ => 'TONE3000-Vorgang fehlgeschlagen.',
  };

  @override
  void dispose() {
    _cancellationToken?.cancel();
    unawaited(_callbackSubscription?.cancel());
    super.dispose();
  }
}
