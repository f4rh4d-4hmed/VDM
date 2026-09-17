import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../repositories/download_repository.dart';
import 'file_service.dart';

class IntegrationServerService extends ChangeNotifier {
  final DownloadRepository downloadRepository;
  final FileService fileService;
  final int port;

  HttpServer? _server;
  bool _isRunning = false;
  DateTime? _lastConnectedTime;
  int _receivedTasksCount = 0;

  // Rate limiting tracker: list of request timestamps within rolling window
  final List<DateTime> _recentRequestTimes = [];
  static const int _maxRequestsPerWindow = 30;
  static const Duration _rateLimitWindow = Duration(seconds: 10);
  static const int _maxPayloadBytes = 65536; // 64 KB

  IntegrationServerService({
    required this.downloadRepository,
    required this.fileService,
    this.port = AppConstants.defaultServerPort,
  });

  bool get isRunning => _isRunning;
  DateTime? get lastConnectedTime => _lastConnectedTime;
  int get receivedTasksCount => _receivedTasksCount;
  int get serverPort => _server?.port ?? port;

  /// Starts the local HTTP bridge server
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _isRunning = true;
      notifyListeners();

      _server!.listen(
        _handleRequest,
        onError: (e) {
          debugPrint('IntegrationServer error: $e');
        },
      );
      debugPrint('VirusDownloader Integration Server listening on port ${_server!.port}');
    } catch (e) {
      debugPrint('Failed to bind IntegrationServer on port $port: $e');
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stops the local HTTP bridge server
  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    notifyListeners();
  }

  bool _isAllowedExtensionOrigin(String origin) {
    if (origin.isEmpty) return true; // Native callers without Origin header
    final lower = origin.toLowerCase();
    if (lower.startsWith('chrome-extension://') ||
        lower.startsWith('moz-extension://') ||
        lower.startsWith('edge-extension://') ||
        lower.startsWith('extension://')) {
      return true;
    }
    // Allow local tools on loopback
    if (lower.startsWith('http://127.0.0.1') || lower.startsWith('http://localhost')) {
      return true;
    }
    return false;
  }

  bool _isWebOrigin(String origin) {
    if (origin.isEmpty) return false;
    final lower = origin.toLowerCase();
    if ((lower.startsWith('http://') || lower.startsWith('https://')) &&
        !lower.startsWith('http://127.0.0.1') &&
        !lower.startsWith('http://localhost')) {
      return true;
    }
    return false;
  }

  String? _extractToken(HttpRequest request) {
    // 1. Check custom header x-virusdownloader-token or x-vd-token
    final headerVal = request.headers.value(AppConstants.extensionTokenHeader) ??
        request.headers.value('x-vd-token');
    if (headerVal != null && headerVal.trim().isNotEmpty) {
      return headerVal.trim();
    }

    // 2. Check Authorization: Bearer <token>
    final auth = request.headers.value('authorization');
    if (auth != null && auth.startsWith('Bearer ')) {
      final token = auth.substring(7).trim();
      if (token.isNotEmpty) return token;
    }

    // 3. Check query param ?token=
    final queryToken = request.uri.queryParameters['token'];
    if (queryToken != null && queryToken.trim().isNotEmpty) {
      return queryToken.trim();
    }

    return null;
  }

  bool _isRateLimited() {
    final now = DateTime.now();
    _recentRequestTimes.removeWhere((t) => now.difference(t) > _rateLimitWindow);
    if (_recentRequestTimes.length >= _maxRequestsPerWindow) {
      return true;
    }
    _recentRequestTimes.add(now);
    return false;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final origin = request.headers.value('origin') ?? '';
    final referer = request.headers.value('referer') ?? '';

    // 1. Origin & Referer Verification (Anti-CSRF from web pages)
    if (_isWebOrigin(origin) || _isWebOrigin(referer)) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': 'Forbidden: Web page origins are blocked by security policy.',
      }));
      await request.response.close();
      return;
    }

    // 2. Set restricted CORS headers only for verified extension origins
    if (origin.isNotEmpty && _isAllowedExtensionOrigin(origin)) {
      request.response.headers.set('Access-Control-Allow-Origin', origin);
      request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-virusdownloader-token, x-vd-token');
      request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    }

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // 3. Rate limiting check
    if (_isRateLimited()) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': 'Too many requests. Please wait a moment.',
      }));
      await request.response.close();
      return;
    }

    // 4. Payload size check
    if (request.contentLength > _maxPayloadBytes) {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': 'Payload exceeds 64 KB limit.',
      }));
      await request.response.close();
      return;
    }

    _lastConnectedTime = DateTime.now();
    notifyListeners();

    final path = request.uri.path;
    final expectedToken = downloadRepository.settingsRepo.currentSettings.extensionAuthToken;
    final incomingToken = _extractToken(request);

    // 5. Health endpoint
    if (request.method == 'GET' && (path == '/health' || path == '/status')) {
      final isAuthenticated = expectedToken.isEmpty || (incomingToken != null && incomingToken == expectedToken);

      // If token provided but mismatch, reject
      if (incomingToken != null && incomingToken != expectedToken) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': 'Unauthorized: Invalid extension security token.',
        }));
        await request.response.close();
        return;
      }

      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'status': 'ok',
        'app': 'VirusDownloader',
        'version': '1.0.0',
        'authenticated': isAuthenticated,
        'port': _server?.port ?? port,
        'uptime': DateTime.now().toIso8601String(),
      }));
      await request.response.close();
      return;
    }

    // 6. Add Download Task
    if (request.method == 'POST' && path == '/add') {
      // Validate security token
      if (expectedToken.isNotEmpty && (incomingToken == null || incomingToken != expectedToken)) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': 'Unauthorized: Invalid or missing security token.',
        }));
        await request.response.close();
        return;
      }

      try {
        final content = await utf8.decoder.bind(request).join();
        final data = jsonDecode(content) as Map<String, dynamic>;

        var url = (data['url'] as String? ?? '').trim();

        // Check for browser-internal memory URLs (blob / data)
        if (url.startsWith('blob:') || url.startsWith('data:')) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error': 'Browser-internal blob stream cannot be downloaded directly. Please select the captured stream from the toolbar.',
          }));
          await request.response.close();
          return;
        }

        // Normalize protocol-relative and missing scheme URLs
        if (url.startsWith('//')) {
          url = 'https:$url';
        } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
          if (url.contains('.') || url.contains('/')) {
            url = 'https://${url.replaceFirst(RegExp(r'^/+'), '')}';
          }
        }

        if (url.contains(' ')) {
          url = Uri.encodeFull(url);
        }

        final parsedUri = Uri.tryParse(url);
        if (url.isEmpty ||
            parsedUri == null ||
            (!url.startsWith('http://') && !url.startsWith('https://')) ||
            parsedUri.host.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error': 'Invalid URL: "$url". A valid HTTP or HTTPS URL is required.',
          }));
          await request.response.close();
          return;
        }

        var fileName = (data['fileName'] as String? ?? '').trim();
        if (fileName.isEmpty) {
          fileName = AppUtils.extractFileName(url);
        }

        // Parse category
        final extCategory = AppUtils.categoryFromExtension(fileName);
        DownloadCategory category = extCategory;

        final catStr = (data['category'] as String?)?.toLowerCase().trim();
        final isExplicitStream = catStr == 'hls_stream' || catStr == 'dash_stream';

        if (isExplicitStream) {
          category = DownloadCategory.videos;
        } else if (category == DownloadCategory.other && catStr != null && catStr.isNotEmpty && catStr != 'other') {
          if (catStr == 'video' || catStr == 'videos') {
            category = DownloadCategory.videos;
          } else if (catStr == 'audio') {
            category = DownloadCategory.audio;
          } else if (catStr == 'image' || catStr == 'images') {
            category = DownloadCategory.images;
          } else if (catStr == 'document' || catStr == 'documents') {
            category = DownloadCategory.documents;
          } else if (catStr == 'archive' || catStr == 'archives' || catStr == 'compressed') {
            category = DownloadCategory.compressed;
          } else if (catStr == 'program' || catStr == 'programs') {
            category = DownloadCategory.programs;
          } else {
            category = DownloadCategory.values.firstWhere(
              (c) => c.name.toLowerCase() == catStr,
              orElse: () => DownloadCategory.other,
            );
          }
        }

        // Parse custom headers
        Map<String, String>? headers;
        if (data['headers'] != null && data['headers'] is Map) {
          headers = <String, String>{};
          for (final entry in (data['headers'] as Map).entries) {
            final key = entry.key.toString().trim();
            final value = entry.value.toString();
            if (key.toLowerCase() == 'range') continue;
            headers[key] = value;
          }
          if (headers.isEmpty) headers = null;
        }

        final isForced = data['force'] == true || request.uri.queryParameters['force'] == 'true';
        final confirmEnabled = downloadRepository.settingsRepo.currentSettings.confirmDownloads;

        // Desktop confirmation flow: If confirmation is enabled and not forced, spawn separate compact window!
        // This ensures the main app window does not pop up into the user's face.
        if (confirmEnabled && !isForced && AppUtils.isDesktop) {
          try {
            final exePath = Platform.resolvedExecutable;
            final processArgs = <String>[
              '--confirm-download',
              '--url=$url',
              '--filename=$fileName',
              '--category=${category.name}',
              '--token=$expectedToken',
            ];
            if (headers != null && headers.isNotEmpty) {
              processArgs.add('--headers=${jsonEncode(headers)}');
            }

            await Process.start(
              exePath,
              processArgs,
              mode: ProcessStartMode.detached,
            );

            request.response.headers.contentType = ContentType.json;
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({
              'success': true,
              'status': 'confirmation_requested',
              'fileName': fileName,
            }));
            await request.response.close();
            return;
          } catch (spawnErr) {
            debugPrint('Failed to spawn separate confirmation window, falling back to direct add: $spawnErr');
          }
        }

        // Determine save directory
        final targetDir = downloadRepository.settingsRepo.currentSettings.defaultSavePath.isNotEmpty
            ? downloadRepository.settingsRepo.currentSettings.defaultSavePath
            : await fileService.getDefaultDownloadDirectory();

        // Add task to repository
        final task = await downloadRepository.addTask(
          url: url,
          fileName: fileName,
          targetDirectory: targetDir,
          category: category,
          headers: headers,
        );

        _receivedTasksCount++;
        notifyListeners();

        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({
          'success': true,
          'taskId': task.id,
          'fileName': task.fileName,
          'savePath': task.savePath,
        }));
        await request.response.close();
      } catch (err) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': err.toString()}));
        await request.response.close();
      }
      return;
    }

    // Default 404
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': 'Endpoint not found'}));
    await request.response.close();
  }
}
