import '../controllers/tone3000_controller.dart';
import '../services/local_persistence.dart';
import 'local_ir_repository.dart';
import 'tone3000_api_client.dart';
import 'tone3000_browser.dart';
import 'tone3000_config.dart';
import 'tone3000_download_service.dart';
import 'tone3000_http.dart';
import 'tone3000_oauth.dart';
import 'tone3000_secure_store.dart';
import '../nam/nam_download_service.dart';
import '../nam/nam_repository.dart';
import '../nam/nam_import_service.dart';

Tone3000Controller createTone3000Controller() {
  final config = Tone3000Config.fromEnvironment();
  final browser = PlatformTone3000Browser();
  final secureStore = FlutterTone3000SecureStore();
  final transport = NetworkTone3000HttpTransport();
  final tokenClient = Tone3000TokenClient(
    config: config,
    transport: transport,
    clock: DateTime.now,
  );
  final sessionManager = Tone3000SessionManager(
    store: secureStore,
    tokenClient: tokenClient,
    clock: DateTime.now,
  );
  final localRepository = LocalIrRepository(SharedPreferencesStringStore());
  final namRepository = NamRepository(SharedPreferencesStringStore());
  return Tone3000Controller(
    config: config,
    browser: browser,
    oauth: Tone3000OAuthService(
      config: config,
      store: secureStore,
      browser: browser,
      tokenClient: tokenClient,
    ),
    sessionManager: sessionManager,
    api: NetworkTone3000Api(
      transport: transport,
      sessionManager: sessionManager,
    ),
    downloader: Tone3000DownloadService(
      transport: transport,
      directoryProvider: const AppIrStorageDirectoryProvider(),
      repository: localRepository,
    ),
    localRepository: localRepository,
    namRepository: namRepository,
    namDownloader: NamDownloadService(
      transport: transport,
      repository: namRepository,
    ),
    namImporter: NamImportService(repository: namRepository),
  );
}
