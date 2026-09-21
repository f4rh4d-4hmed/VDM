import 'dart:io';

class AppConstants {
  static String get appName => Platform.isAndroid ? 'VDM' : 'Virus Download Manager';
  
  // Layout breakpoints
  static const double compactWidth = 600.0;
  static const double mediumWidth = 840.0;

  // Defaults
  static const int defaultMaxConcurrentDownloads = 3;
  
  // Storage keys
  static const String storageKeyTasks = 'vdownloader_tasks';
  static const String storageKeySettings = 'vdownloader_settings';

  // Default network headers
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static const Map<String, String> defaultHttpHeaders = {
    'User-Agent': defaultUserAgent,
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'identity',
  };

  // Integration & Protocol Constants
  static const String protocolScheme = 'virusdownloader';
  static const int defaultServerPort = 9849;

  // Virus scan constants
  static const int maxAutoScanFileSizeBytes = 5 * 1024 * 1024 * 1024; // 5 GB
}

