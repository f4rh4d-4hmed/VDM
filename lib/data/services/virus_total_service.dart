import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/constants.dart';
import '../../domain/models/virus_scan_result.dart';

class VirusTotalService {
  final Dio _dio;

  VirusTotalService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://www.virustotal.com/api/v3',
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 30),
              ),
            );

  /// Validates whether the user-provided VirusTotal API key is active and authorized.
  Future<bool> validateApiKey(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;

    try {
      // Querying a dummy hash:
      // 404 = key is valid and authenticated (resource just not found)
      // 200 = authenticated
      // 401 / 403 = invalid key
      final response = await _dio.get(
        '/files/0000000000000000000000000000000000000000000000000000000000000000',
        options: Options(
          headers: {'x-apikey': key},
          validateStatus: (status) => status != null && (status < 500),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 429) {
        return true;
      }
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 429) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Scans a file by its SHA-256 hash using VirusTotal v3 API.
  /// Works across all platforms.
  Future<VirusScanResult> scanFileHash(
    String sha256Hash,
    String apiKey, {
    int? fileSizeBytes,
    bool desktopAntivirusHandedOver = false,
    String? desktopAntivirusDetails,
    bool forceManualScan = false,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return VirusScanResult.error(
        message: 'VirusTotal API key is not configured. Please set your key in Settings.',
        desktopAntivirusHandedOver: desktopAntivirusHandedOver,
        desktopAntivirusDetails: desktopAntivirusDetails,
      );
    }

    // Check size limit: Files > 5 GB skip standard auto-detection
    if (!forceManualScan &&
        fileSizeBytes != null &&
        fileSizeBytes > AppConstants.maxAutoScanFileSizeBytes) {
      return VirusScanResult.skippedTooLarge(
        fileSizeBytes: fileSizeBytes,
        desktopAntivirusHandedOver: desktopAntivirusHandedOver,
        desktopAntivirusDetails: desktopAntivirusDetails,
      );
    }

    try {
      final response = await _dio.get(
        '/files/$sha256Hash',
        options: Options(
          headers: {'x-apikey': key},
          validateStatus: (status) => status != null,
        ),
      );

      if (response.statusCode == 404) {
        return VirusScanResult.notFound(
          fileSha256: sha256Hash,
          fileSizeBytes: fileSizeBytes,
          desktopAntivirusHandedOver: desktopAntivirusHandedOver,
          desktopAntivirusDetails: desktopAntivirusDetails,
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return VirusScanResult.error(
          message: 'Invalid VirusTotal API key. Please check your credentials in Settings.',
          desktopAntivirusHandedOver: desktopAntivirusHandedOver,
          desktopAntivirusDetails: desktopAntivirusDetails,
        );
      }

      if (response.statusCode == 429) {
        return VirusScanResult.error(
          message: 'VirusTotal API rate limit exceeded. Please try again in a few minutes.',
          desktopAntivirusHandedOver: desktopAntivirusHandedOver,
          desktopAntivirusDetails: desktopAntivirusDetails,
        );
      }

      if (response.statusCode != 200 || response.data == null) {
        return VirusScanResult.error(
          message: 'VirusTotal request failed (HTTP ${response.statusCode}).',
          desktopAntivirusHandedOver: desktopAntivirusHandedOver,
          desktopAntivirusDetails: desktopAntivirusDetails,
        );
      }

      final data = response.data['data'] as Map<String, dynamic>?;
      final attributes = data?['attributes'] as Map<String, dynamic>?;
      if (attributes == null) {
        return VirusScanResult.error(
          message: 'Unexpected response structure from VirusTotal.',
          desktopAntivirusHandedOver: desktopAntivirusHandedOver,
          desktopAntivirusDetails: desktopAntivirusDetails,
        );
      }

      final stats = attributes['last_analysis_stats'] as Map<String, dynamic>? ?? {};
      final malicious = (stats['malicious'] as num?)?.toInt() ?? 0;
      final suspicious = (stats['suspicious'] as num?)?.toInt() ?? 0;
      final undetected = (stats['undetected'] as num?)?.toInt() ?? 0;
      final harmless = (stats['harmless'] as num?)?.toInt() ?? 0;
      final totalEngines = malicious + suspicious + undetected + harmless;

      final results = attributes['last_analysis_results'] as Map<String, dynamic>? ?? {};
      final Map<String, String> detectedThreats = {};
      for (final entry in results.entries) {
        if (entry.value is Map) {
          final cat = entry.value['category']?.toString().toLowerCase();
          if (cat == 'malicious' || cat == 'suspicious') {
            final threat = entry.value['result']?.toString() ?? 'Threat detected';
            detectedThreats[entry.key] = threat;
          }
        }
      }

      final permalink = 'https://www.virustotal.com/gui/file/$sha256Hash';
      final status = malicious > 0
          ? VirusScanStatus.malicious
          : (suspicious > 0 ? VirusScanStatus.suspicious : VirusScanStatus.clean);

      return VirusScanResult(
        status: status,
        maliciousCount: malicious,
        suspiciousCount: suspicious,
        undetectedCount: undetected,
        harmlessCount: harmless,
        totalEngines: totalEngines,
        permalink: permalink,
        scanDate: DateTime.now(),
        detectedThreats: detectedThreats,
        desktopAntivirusHandedOver: desktopAntivirusHandedOver,
        desktopAntivirusDetails: desktopAntivirusDetails,
        fileSizeBytes: fileSizeBytes,
        fileSha256: sha256Hash,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return VirusScanResult.notFound(
          fileSha256: sha256Hash,
          fileSizeBytes: fileSizeBytes,
          desktopAntivirusHandedOver: desktopAntivirusHandedOver,
          desktopAntivirusDetails: desktopAntivirusDetails,
        );
      }
      return VirusScanResult.error(
        message: 'VirusTotal connection failed: ${e.message ?? e.toString()}',
        desktopAntivirusHandedOver: desktopAntivirusHandedOver,
        desktopAntivirusDetails: desktopAntivirusDetails,
      );
    } catch (e) {
      return VirusScanResult.error(
        message: 'Scan error: $e',
        desktopAntivirusHandedOver: desktopAntivirusHandedOver,
        desktopAntivirusDetails: desktopAntivirusDetails,
      );
    }
  }

  /// Uploads a file under 32 MB to VirusTotal for analysis.
  Future<VirusScanResult> uploadAndScanFile(
    String filePath,
    String apiKey, {
    String? sha256Hash,
    void Function(double progress)? onProgress,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return VirusScanResult.error(message: 'VirusTotal API key is required.');
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return VirusScanResult.error(message: 'File not found on disk.');
      }

      final length = await file.length();
      // VirusTotal standard direct upload endpoint allows up to 32 MB
      const int maxDirectUploadBytes = 32 * 1024 * 1024;
      if (length > maxDirectUploadBytes) {
        return VirusScanResult.error(
          message: 'Direct file upload exceeds VirusTotal limit (32 MB). Hash lookup is recommended.',
        );
      }

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await _dio.post(
        '/files',
        data: formData,
        options: Options(headers: {'x-apikey': key}),
        onSendProgress: (sent, total) {
          if (total > 0) {
            onProgress?.call(sent / total);
          }
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final permalink = sha256Hash != null
            ? 'https://www.virustotal.com/gui/file/$sha256Hash'
            : null;
        return VirusScanResult(
          status: VirusScanStatus.scanning,
          permalink: permalink,
          errorMessage: 'File submitted to VirusTotal queue for analysis.',
          fileSizeBytes: length,
          fileSha256: sha256Hash,
        );
      }

      return VirusScanResult.error(message: 'Upload failed with status ${response.statusCode}');
    } catch (e) {
      return VirusScanResult.error(message: 'Upload error: $e');
    }
  }
}
