import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virus_download_manager/core/enums.dart';
import 'package:virus_download_manager/core/utils.dart';
import 'package:virus_download_manager/data/repositories/download_repository.dart';
import 'package:virus_download_manager/data/repositories/settings_repository.dart';
import 'package:virus_download_manager/data/services/antivirus_service.dart';
import 'package:virus_download_manager/data/services/file_service.dart';
import 'package:virus_download_manager/data/services/http_download_service.dart';
import 'package:virus_download_manager/data/services/integration_server_service.dart';
import 'package:virus_download_manager/data/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late SettingsRepository settingsRepo;
  late DownloadRepository downloadRepo;
  late IntegrationServerService server;
  late HttpClient httpClient;

  setUp(() async {
    HttpOverrides.global = null;
    httpClient = HttpClient();
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();

    settingsRepo = SettingsRepository(storageService: storageService);
    await settingsRepo.init();
    await settingsRepo.updateSettings(
      settingsRepo.currentSettings.copyWith(
        confirmDownloads: false, // Default to false in tests to test queueing directly
      ),
    );

    final fileService = FileService();
    final httpService = HttpDownloadService();

    downloadRepo = DownloadRepository(
      httpService: httpService,
      storageService: storageService,
      fileService: fileService,
      settingsRepo: settingsRepo,
    );
    await downloadRepo.init();

    // Use test port to avoid collision
    server = IntegrationServerService(
      downloadRepository: downloadRepo,
      fileService: fileService,
      port: 9890,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    httpClient.close(force: true);
  });

  test('Integration server responds to GET /health with extension CORS headers', () async {
    final request = await httpClient.getUrl(Uri.parse('http://127.0.0.1:9890/health'));
    request.headers.set('Origin', 'chrome-extension://abcdefghijklmnopqrstuvwxyz');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('access-control-allow-origin'), 'chrome-extension://abcdefghijklmnopqrstuvwxyz');

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['status'], 'ok');
    expect(json['app'], 'VirusDownloader');
  });

  test('Integration server strictly rejects requests from external web origins (anti-CSRF)', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.set('Origin', 'https://malicious-website.com');
    request.headers.contentType = ContentType.json;

    request.write(jsonEncode({
      'url': 'https://example.com/malware.exe',
      'fileName': 'malware.exe',
    }));

    final response = await request.close();
    expect(response.statusCode, HttpStatus.forbidden);

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['error'], contains('Web page origins are blocked'));
  });

  test('Integration server rejects invalid or non-HTTP URL with 400', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    request.write(jsonEncode({
      'url': 'not_a_valid_url',
      'fileName': 'file.zip',
    }));

    final response = await request.close();
    expect(response.statusCode, HttpStatus.badRequest);

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['error'], contains('Invalid URL'));
  });

  test('Integration server handles POST /add and queues task', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    final payload = {
      'url': 'https://example.com/stream/video.m3u8',
      'fileName': 'custom_video.m3u8',
      'category': 'video',
      'headers': {
        'Referer': 'https://example.com/watch?v=123',
        'User-Agent': 'CustomBrowser/1.0',
        'Cookie': 'auth=token999',
      },
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    expect(json['success'], isTrue);
    expect(json['taskId'], isNotNull);

    // Verify task in repository
    expect(downloadRepo.tasks.length, 1);
    final task = downloadRepo.tasks.first;
    expect(task.url, 'https://example.com/stream/video.m3u8');
    expect(task.fileName, 'custom_video.mkv');
    expect(task.category, DownloadCategory.videos);
    expect(task.headers?['Referer'], 'https://example.com/watch?v=123');
    expect(task.headers?['Cookie'], 'auth=token999');
    expect(task.headers?['User-Agent'], 'CustomBrowser/1.0');
  });

  test('Integration server returns confirmation_requested when confirmDownloads is enabled', () async {
    await settingsRepo.updateSettings(
      settingsRepo.currentSettings.copyWith(confirmDownloads: true),
    );

    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    final payload = {
      'url': 'https://example.com/app.exe',
      'fileName': 'app.exe',
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    // When confirmation is enabled, it requests confirmation instead of direct adding
    expect(json['success'], isTrue);
    expect(json['status'], 'confirmation_requested');
  });

  test('Suspicious format detection identifies high-risk file types', () {
    expect(AppUtils.isSuspiciousFormat('installer.exe'), isTrue);
    expect(AppUtils.isSuspiciousFormat('script.bat'), isTrue);
    expect(AppUtils.isSuspiciousFormat('payload.vbs'), isTrue);
    expect(AppUtils.isSuspiciousFormat('setup.msi'), isTrue);
    expect(AppUtils.isSuspiciousFormat('archive.iso'), isTrue);

    expect(AppUtils.isSuspiciousFormat('video.mp4'), isFalse);
    expect(AppUtils.isSuspiciousFormat('song.mp3'), isFalse);
    expect(AppUtils.isSuspiciousFormat('document.pdf'), isFalse);
    expect(AppUtils.isSuspiciousFormat('photo.png'), isFalse);
  });

  test('Antivirus detection identifies Windows error 225 and deflecting message', () {
    final avService = AntivirusService();
    const osError = OSError('Operation did not complete successfully because the file contains a virus or potentially unwanted software.', 225);
    const fsError = FileSystemException('Cannot write file', 'test.exe', osError);

    expect(avService.isQuarantineError(fsError), isTrue);

    final humanError = AppUtils.getHumanReadableError(fsError);
    expect(humanError, contains('Quarantined by Antivirus'));
    expect(humanError, contains('VirusDownloader did not fail'));
  });

  test('Integration server rejects blob URLs with 400 and clear error message', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    final payload = {
      'url': 'blob:https://example.com/123-456',
      'fileName': 'blob_video.mp4',
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.badRequest);
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['error'], contains('Browser-internal blob stream cannot be downloaded directly'));
  });
}
