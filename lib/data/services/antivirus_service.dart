import 'dart:io';
import 'package:flutter/foundation.dart';

class AntivirusService {
  /// Attaches Windows Zone.Identifier (Mark of the Web) to downloaded files on Windows NTFS.
  /// This signals Windows Defender and any active antivirus software that the file originated
  /// from the Internet Zone (ZoneId=3) and must be actively scanned and monitored.
  Future<bool> attachMarkOfTheWeb(
    String filePath, {
    String? sourceUrl,
    String? referrerUrl,
  }) async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      final targetFile = File(filePath);
      if (!await targetFile.exists()) return false;

      // On Windows NTFS, writing to <path>:Zone.Identifier attaches an alternate data stream
      final adsPath = '$filePath:Zone.Identifier';
      final adsFile = File(adsPath);

      final buffer = StringBuffer();
      buffer.writeln('[ZoneTransfer]');
      buffer.writeln('ZoneId=3');
      if (referrerUrl != null && referrerUrl.isNotEmpty) {
        buffer.writeln('ReferrerUrl=$referrerUrl');
      }
      if (sourceUrl != null && sourceUrl.isNotEmpty) {
        buffer.writeln('HostUrl=$sourceUrl');
      }

      await adsFile.writeAsString(buffer.toString(), flush: true);
      return true;
    } catch (e) {
      // Non-NTFS drives (e.g. FAT32) or restricted permissions may silently fail ADS writing
      debugPrint('Note: Could not attach Zone.Identifier on $filePath: $e');
      return false;
    }
  }

  /// Checks if an exception or missing file condition was caused by system antivirus intervention.
  bool isQuarantineError(dynamic error) {
    if (error == null) return false;

    if (error is FileSystemException) {
      final errorCode = error.osError?.errorCode ?? 0;
      final msg = error.message.toLowerCase();
      final osMsg = error.osError?.message.toLowerCase() ?? '';

      // Windows 225 is ERROR_VIRUS_INFECTED:
      // "Operation did not complete successfully because the file contains a virus or potentially unwanted software."
      if (errorCode == 225 ||
          msg.contains('contains a virus') ||
          osMsg.contains('contains a virus') ||
          msg.contains('potentially unwanted') ||
          osMsg.contains('potentially unwanted') ||
          msg.contains('antivirus') ||
          osMsg.contains('antivirus')) {
        return true;
      }
    }

    final errStr = error.toString().toLowerCase();
    return errStr.contains('225') ||
        errStr.contains('contains a virus') ||
        errStr.contains('potentially unwanted') ||
        errStr.contains('antivirus');
  }

  /// Evaluates whether a completed download file that is now missing was likely removed by Antivirus.
  bool wasRemovedByAntivirus({
    required String filePath,
    required bool fileExists,
    required bool isSuspiciousFormat,
    dynamic lastError,
  }) {
    if (fileExists) return false;
    if (isQuarantineError(lastError)) return true;
    if (isSuspiciousFormat) {
      // High-risk executables that suddenly disappear after complete download on Windows
      // are typically quarantined by real-time security scanners (e.g. Windows Defender).
      return true;
    }
    return false;
  }
}

