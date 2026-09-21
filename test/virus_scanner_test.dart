import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:virus_download_manager/core/constants.dart';
import 'package:virus_download_manager/data/services/antivirus_service.dart';
import 'package:virus_download_manager/data/services/virus_total_service.dart';
import 'package:virus_download_manager/domain/models/virus_scan_result.dart';

void main() {
  group('AntivirusService tests', () {
    late AntivirusService avService;

    setUp(() {
      avService = AntivirusService();
    });

    test('shouldAutoScan returns true for <= 5GB and false for > 5GB', () {
      expect(avService.shouldAutoScan(1024), isTrue);
      expect(avService.shouldAutoScan(AppConstants.maxAutoScanFileSizeBytes), isTrue);
      expect(avService.shouldAutoScan(AppConstants.maxAutoScanFileSizeBytes + 1), isFalse);
      expect(avService.shouldAutoScan(6 * 1024 * 1024 * 1024), isFalse);
    });

    test('isQuarantineError identifies Windows error 225 and quarantine keywords', () {
      final osError = OSError('Operation did not complete successfully', 225);
      final fsException = FileSystemException('Quarantine error', 'test.exe', osError);

      expect(avService.isQuarantineError(fsException), isTrue);
      expect(avService.isQuarantineError('File contains a virus and was quarantined'), isTrue);
      expect(avService.isQuarantineError('General network failure'), isFalse);
    });

    test('performDesktopHandover skips auto-scan for files > 5GB unless forced', () async {
      final nonExistentPath = '/tmp/dummy_test_5gb_file.dat';
      final resSkipped = await avService.performDesktopHandover(
        nonExistentPath,
        fileSizeBytes: 6 * 1024 * 1024 * 1024,
        forceManualScan: false,
      );

      // On desktop, it skips because file > 5GB
      // On non-desktop, it reports non-desktop
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        expect(resSkipped.success, isFalse);
        expect(resSkipped.details, contains('exceeds 5 GB'));
      } else {
        expect(resSkipped.success, isFalse);
      }
    });
  });

  group('VirusTotalService tests', () {
    test('validateApiKey returns false for empty key', () async {
      final vtService = VirusTotalService();
      expect(await vtService.validateApiKey(''), isFalse);
      expect(await vtService.validateApiKey('   '), isFalse);
    });

    test('scanFileHash returns error when API key is empty', () async {
      final vtService = VirusTotalService();
      final result = await vtService.scanFileHash(
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        '',
      );

      expect(result.status, equals(VirusScanStatus.error));
      expect(result.errorMessage, contains('not configured'));
    });

    test('scanFileHash returns skippedTooLarge when file exceeds 5GB and not forced', () async {
      final vtService = VirusTotalService();
      final result = await vtService.scanFileHash(
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'valid_dummy_key',
        fileSizeBytes: 6 * 1024 * 1024 * 1024,
        forceManualScan: false,
      );

      expect(result.status, equals(VirusScanStatus.skippedTooLarge));
      expect(result.isSkippedTooLarge, isTrue);
      expect(result.errorMessage, contains('exceeds 5 GB'));
    });
  });

  group('VirusScanResult domain model tests', () {
    test('VirusScanResult.clean constructor sets appropriate flags', () {
      final result = VirusScanResult.clean(
        totalEngines: 72,
        undetectedCount: 72,
        permalink: 'https://virustotal.com/gui/file/test',
        desktopAntivirusHandedOver: true,
      );

      expect(result.isClean, isTrue);
      expect(result.isMalicious, isFalse);
      expect(result.totalEngines, 72);
      expect(result.desktopAntivirusHandedOver, isTrue);
    });

    test('VirusScanResult.malicious constructor captures threat counts and detections', () {
      final result = VirusScanResult.malicious(
        maliciousCount: 5,
        suspiciousCount: 1,
        totalEngines: 70,
        detectedThreats: {'Microsoft': 'Trojan:Win32/Wacatac', 'Kaspersky': 'Trojan.Generic'},
      );

      expect(result.isMalicious, isTrue);
      expect(result.isClean, isFalse);
      expect(result.maliciousCount, 5);
      expect(result.detectedThreats.length, 2);
    });

    test('VirusScanResult.skippedTooLarge sets correct status', () {
      final result = VirusScanResult.skippedTooLarge(
        fileSizeBytes: 5368709121,
      );

      expect(result.isSkippedTooLarge, isTrue);
      expect(result.status, equals(VirusScanStatus.skippedTooLarge));
      expect(result.fileSizeBytes, equals(5368709121));
    });
  });
}
