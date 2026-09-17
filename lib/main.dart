import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/utils.dart';
import 'data/repositories/download_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/background_service.dart';
import 'data/services/browser_integration_service.dart';
import 'data/services/ffmpeg_service.dart';
import 'data/services/file_service.dart';
import 'data/services/http_download_service.dart';
import 'data/services/integrity_service.dart';
import 'data/services/integration_server_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/permission_service.dart';
import 'data/services/proxy_service.dart';
import 'data/services/segmented_download_service.dart';
import 'data/services/storage_service.dart';
import 'ui/view_models/downloads_view_model.dart';
import 'ui/view_models/settings_view_model.dart';
import 'ui/views/confirmation_window_app.dart';

Future<bool> _forwardToRunningServer({
  required int port,
  required String url,
  required String fileName,
  required String category,
  required String token,
}) async {
  final client = HttpClient();
  try {
    final req = await client.post('127.0.0.1', port, '/add').timeout(const Duration(seconds: 2));
    req.headers.contentType = ContentType.json;
    if (token.isNotEmpty) {
      req.headers.set(AppConstants.extensionTokenHeader, token);
    }
    req.write(jsonEncode({
      'url': url,
      'fileName': fileName,
      'category': category,
    }));
    final resp = await req.close();
    await resp.drain();
    return resp.statusCode == HttpStatus.ok;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

void main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Check if running as dedicated confirmation popup window
  if (args.any((a) => a.startsWith('--confirm-download'))) {
    String url = '';
    String fileName = '';
    String category = 'other';
    String token = '';
    Map<String, String>? headers;

    for (final arg in args) {
      if (arg.startsWith('--url=')) url = arg.substring(6);
      if (arg.startsWith('--filename=')) fileName = arg.substring(11);
      if (arg.startsWith('--category=')) category = arg.substring(11);
      if (arg.startsWith('--token=')) token = arg.substring(8);
      if (arg.startsWith('--headers=')) {
        try {
          final decoded = jsonDecode(arg.substring(10));
          if (decoded is Map) {
            headers = Map<String, String>.from(decoded);
          }
        } catch (_) {}
      }
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        await windowManager.ensureInitialized();
        const confirmOptions = WindowOptions(
          size: Size(440, 220),
          minimumSize: Size(440, 220),
          maximumSize: Size(440, 220),
          center: true,
          alwaysOnTop: true,
          title: 'Confirm Download',
        );
        windowManager.waitUntilReadyToShow(confirmOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      } catch (e) {
        debugPrint('Window manager init failed for confirmation popup: $e');
      }
    }

    runApp(ConfirmationWindowApp(
      url: url,
      fileName: fileName,
      category: category,
      token: token,
      headers: headers,
    ));
    return;
  }

  // 2. Check if launched via custom URI protocol (virusdownloader://add?...)
  Map<String, String>? pendingProtocolTask;
  final uriArg = args.firstWhere(
    (a) => a.startsWith('${AppConstants.protocolScheme}://'),
    orElse: () => '',
  );

  if (uriArg.isNotEmpty) {
    try {
      final parsed = Uri.parse(uriArg);
      final url = parsed.queryParameters['url'] ?? '';
      final fileName = parsed.queryParameters['fileName'] ?? parsed.queryParameters['filename'] ?? '';
      final category = parsed.queryParameters['category'] ?? 'other';
      final token = parsed.queryParameters['token'] ?? '';

      // If an existing instance is running on loopback, forward and exit
      final forwarded = await _forwardToRunningServer(
        port: AppConstants.defaultServerPort,
        url: url,
        fileName: fileName,
        category: category,
        token: token,
      );

      if (forwarded) {
        exit(0);
      }

      pendingProtocolTask = {
        'url': url,
        'fileName': fileName,
        'category': category,
        'token': token,
      };
    } catch (e) {
      debugPrint('Error parsing protocol URI argument: $e');
    }
  }

  // Desktop Main Window Configuration
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1080, 720),
        minimumSize: Size(820, 560),
        center: true,
        title: AppConstants.appName,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Window manager initialization failed: $e');
    }
  }

  // Initialize Core Services & Startup Permissions
  final permissionService = PermissionService();
  await permissionService.checkAndRequestAllPermissions();

  final notificationService = NotificationService();
  await notificationService.init();

  final storageService = StorageService();
  await storageService.init();

  final fileService = FileService();
  final httpService = HttpDownloadService();
  final ffmpegService = FfmpegService();
  final proxyService = ProxyService();
  final integrityService = IntegrityService();

  final segmentedService = SegmentedDownloadService(
    proxyService: proxyService,
    fileService: fileService,
  );

  final backgroundService = BackgroundService();

  final settingsRepository = SettingsRepository(storageService: storageService);
  await settingsRepository.init();

  if (settingsRepository.currentSettings.runInBackground) {
    await backgroundService.startBackgroundService();
  }

  final downloadRepository = DownloadRepository(
    httpService: httpService,
    segmentedService: segmentedService,
    storageService: storageService,
    fileService: fileService,
    settingsRepo: settingsRepository,
    ffmpegService: ffmpegService,
    notificationService: notificationService,
    integrityService: integrityService,
  );
  await downloadRepository.init();

  // Initialize Browser Integration & Start Local Server
  final browserIntegrationService = BrowserIntegrationService();
  final integrationServer = IntegrationServerService(
    downloadRepository: downloadRepository,
    fileService: fileService,
  );
  if (!AppUtils.isMobile) {
    await integrationServer.start();
    // Auto-sync token and server port to extension directory
    await browserIntegrationService.syncExtensionSecurityConfig(
      token: settingsRepository.currentSettings.extensionAuthToken,
      port: integrationServer.serverPort,
    );
  }

  // Handle pending protocol task on cold start
  if (pendingProtocolTask != null && pendingProtocolTask['url']!.isNotEmpty) {
    final taskUrl = pendingProtocolTask['url']!;
    final taskFile = pendingProtocolTask['fileName']!.isNotEmpty
        ? pendingProtocolTask['fileName']!
        : AppUtils.extractFileName(taskUrl);
    final targetDir = settingsRepository.currentSettings.defaultSavePath.isNotEmpty
        ? settingsRepository.currentSettings.defaultSavePath
        : await fileService.getDefaultDownloadDirectory();

    if (settingsRepository.currentSettings.confirmDownloads && AppUtils.isDesktop) {
      try {
        await Process.start(
          Platform.resolvedExecutable,
          [
            '--confirm-download',
            '--url=$taskUrl',
            '--filename=$taskFile',
            '--category=${pendingProtocolTask['category'] ?? 'other'}',
            '--token=${settingsRepository.currentSettings.extensionAuthToken}',
          ],
          mode: ProcessStartMode.detached,
        );
      } catch (_) {}
    } else {
      await downloadRepository.addTask(
        url: taskUrl,
        fileName: taskFile,
        targetDirectory: targetDir,
        category: AppUtils.categoryFromExtension(taskFile),
      );
    }
  }

  runApp(
    MultiProvider(
      providers: [
        // Services
        Provider<PermissionService>.value(value: permissionService),
        Provider<NotificationService>.value(value: notificationService),
        Provider<StorageService>.value(value: storageService),
        Provider<FileService>.value(value: fileService),
        Provider<HttpDownloadService>.value(value: httpService),
        Provider<FfmpegService>.value(value: ffmpegService),
        Provider<ProxyService>.value(value: proxyService),
        Provider<IntegrityService>.value(value: integrityService),
        Provider<SegmentedDownloadService>.value(value: segmentedService),
        Provider<BackgroundService>.value(value: backgroundService),
        Provider<BrowserIntegrationService>.value(value: browserIntegrationService),
        ChangeNotifierProvider<IntegrationServerService>.value(value: integrationServer),

        // Repositories
        ChangeNotifierProvider<DownloadRepository>.value(value: downloadRepository),
        Provider<SettingsRepository>.value(value: settingsRepository),

        // ViewModels
        ChangeNotifierProvider<DownloadsViewModel>(
          create: (_) => DownloadsViewModel(repository: downloadRepository),
        ),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(
            repository: settingsRepository,
            browserService: browserIntegrationService,
            integrationServer: integrationServer,
            proxyService: proxyService,
            backgroundService: backgroundService,
          ),
        ),
      ],
      child: const VirusDownloaderApp(),
    ),
  );
}
