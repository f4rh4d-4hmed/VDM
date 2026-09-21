import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DetectedBrowser {
  final String name;
  final String executablePath;
  final String extensionsUrl;
  final bool isChromium;
  final String? iconPath;

  const DetectedBrowser({
    required this.name,
    required this.executablePath,
    required this.extensionsUrl,
    this.isChromium = true,
    this.iconPath,
  });

  DetectedBrowser copyWith({
    String? name,
    String? executablePath,
    String? extensionsUrl,
    bool? isChromium,
    String? iconPath,
  }) {
    return DetectedBrowser(
      name: name ?? this.name,
      executablePath: executablePath ?? this.executablePath,
      extensionsUrl: extensionsUrl ?? this.extensionsUrl,
      isChromium: isChromium ?? this.isChromium,
      iconPath: iconPath ?? this.iconPath,
    );
  }
}

class BrowserIntegrationService {
  /// Returns the absolute path where extension files reside or are extracted
  Future<String> getExtensionPath() async {
    // 1. Check if extras/extension directory exists relative to current working directory
    final localExtrasDir = Directory(p.join(Directory.current.path, 'extras', 'extension'));
    if (await localExtrasDir.exists() && await File(p.join(localExtrasDir.path, 'manifest.json')).exists()) {
      return localExtrasDir.path;
    }

    // 2. Check executable directory on desktop
    final exeDir = File(Platform.resolvedExecutable).parent;
    final installedExtDir = Directory(p.join(exeDir.path, 'extension'));
    if (await installedExtDir.exists() && await File(p.join(installedExtDir.path, 'manifest.json')).exists()) {
      return installedExtDir.path;
    }
    final exeExtrasDir = Directory(p.join(exeDir.path, 'extras', 'extension'));
    if (await exeExtrasDir.exists() && await File(p.join(exeExtrasDir.path, 'manifest.json')).exists()) {
      return exeExtrasDir.path;
    }

    // 3. Unpack from Flutter assets into AppSupport/VirusDownloader/extension
    final appSupport = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(appSupport.path, 'extension'));
    await targetDir.create(recursive: true);

    // List of assets to unpack
    final assetPaths = [
      'extras/extension/manifest.json',
      'extras/extension/background.js',
      'extras/extension/content.js',
      'extras/extension/content.css',
      'extras/extension/popup.html',
      'extras/extension/popup.js',
      'extras/extension/popup.css',
      'extras/extension/options.html',
      'extras/extension/options.js',
      'extras/extension/icons/icon16.png',
      'extras/extension/icons/icon32.png',
      'extras/extension/icons/icon48.png',
      'extras/extension/icons/icon128.png',
    ];

    for (final asset in assetPaths) {
      try {
        final byteData = await rootBundle.load(asset);
        final rel = asset.replaceFirst('extras/extension/', '');
        final outFile = File(p.join(targetDir.path, rel));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } catch (e) {
        debugPrint('Failed to unpack asset $asset: $e');
      }
    }

    return targetDir.path;
  }

  /// Scans system for installed web browsers across desktop platforms
  Future<List<DetectedBrowser>> detectInstalledBrowsers() async {
    final list = <DetectedBrowser>[];

    if (Platform.isWindows) {
      final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
      final progFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final progFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

      // 1. Google Chrome
      final chromePaths = [
        p.join(progFiles, r'Google\Chrome\Application\chrome.exe'),
        p.join(progFilesX86, r'Google\Chrome\Application\chrome.exe'),
        p.join(localApp, r'Google\Chrome\Application\chrome.exe'),
      ];
      for (final cp in chromePaths) {
        if (await File(cp).exists()) {
          list.add(DetectedBrowser(
            name: 'Google Chrome',
            executablePath: cp,
            extensionsUrl: 'chrome://extensions',
            isChromium: true,
          ));
          break;
        }
      }

      // 2. Microsoft Edge
      final edgePaths = [
        p.join(progFilesX86, r'Microsoft\Edge\Application\msedge.exe'),
        p.join(progFiles, r'Microsoft\Edge\Application\msedge.exe'),
      ];
      for (final ep in edgePaths) {
        if (await File(ep).exists()) {
          list.add(DetectedBrowser(
            name: 'Microsoft Edge',
            executablePath: ep,
            extensionsUrl: 'edge://extensions',
            isChromium: true,
          ));
          break;
        }
      }

      // 3. Brave Browser
      final bravePaths = [
        p.join(localApp, r'BraveSoftware\Brave-Browser\Application\brave.exe'),
        p.join(progFiles, r'BraveSoftware\Brave-Browser\Application\brave.exe'),
      ];
      for (final bp in bravePaths) {
        if (await File(bp).exists()) {
          list.add(DetectedBrowser(
            name: 'Brave Browser',
            executablePath: bp,
            extensionsUrl: 'brave://extensions',
            isChromium: true,
          ));
          break;
        }
      }

      // 4. Opera / Opera GX
      final operaPaths = [
        p.join(localApp, r'Programs\Opera\launcher.exe'),
        p.join(localApp, r'Programs\Opera GX\launcher.exe'),
      ];
      for (final op in operaPaths) {
        if (await File(op).exists()) {
          list.add(DetectedBrowser(
            name: op.contains('GX') ? 'Opera GX' : 'Opera',
            executablePath: op,
            extensionsUrl: 'opera://extensions',
            isChromium: true,
          ));
          break;
        }
      }

      // 5. Vivaldi
      final vivaldiPaths = [
        p.join(localApp, r'Vivaldi\Application\vivaldi.exe'),
        p.join(progFiles, r'Vivaldi\Application\vivaldi.exe'),
      ];
      for (final vp in vivaldiPaths) {
        if (await File(vp).exists()) {
          list.add(DetectedBrowser(
            name: 'Vivaldi',
            executablePath: vp,
            extensionsUrl: 'vivaldi://extensions',
            isChromium: true,
          ));
          break;
        }
      }

      // 6. Mozilla Firefox
      final firefoxPaths = [
        p.join(progFiles, r'Mozilla Firefox\firefox.exe'),
        p.join(progFilesX86, r'Mozilla Firefox\firefox.exe'),
      ];
      for (final fp in firefoxPaths) {
        if (await File(fp).exists()) {
          list.add(DetectedBrowser(
            name: 'Mozilla Firefox',
            executablePath: fp,
            extensionsUrl: 'about:addons',
            isChromium: false,
          ));
          break;
        }
      }
    } else if (Platform.isMacOS) {
      final macCandidates = [
        {'name': 'Google Chrome', 'path': '/Applications/Google Chrome.app', 'url': 'chrome://extensions', 'chromium': true},
        {'name': 'Microsoft Edge', 'path': '/Applications/Microsoft Edge.app', 'url': 'edge://extensions', 'chromium': true},
        {'name': 'Brave Browser', 'path': '/Applications/Brave Browser.app', 'url': 'brave://extensions', 'chromium': true},
        {'name': 'Opera', 'path': '/Applications/Opera.app', 'url': 'opera://extensions', 'chromium': true},
        {'name': 'Opera GX', 'path': '/Applications/Opera GX.app', 'url': 'opera://extensions', 'chromium': true},
        {'name': 'Vivaldi', 'path': '/Applications/Vivaldi.app', 'url': 'vivaldi://extensions', 'chromium': true},
        {'name': 'Mozilla Firefox', 'path': '/Applications/Firefox.app', 'url': 'about:addons', 'chromium': false},
        {'name': 'Arc', 'path': '/Applications/Arc.app', 'url': 'arc://extensions', 'chromium': true},
        {'name': 'Safari', 'path': '/Applications/Safari.app', 'url': '', 'chromium': false},
      ];

      for (final c in macCandidates) {
        final appPath = c['path'] as String;
        if (await Directory(appPath).exists() || await File(appPath).exists()) {
          list.add(DetectedBrowser(
            name: c['name'] as String,
            executablePath: appPath,
            extensionsUrl: c['url'] as String,
            isChromium: c['chromium'] as bool,
          ));
        }
      }
    } else if (Platform.isLinux) {
      final linuxCandidates = [
        {
          'name': 'Google Chrome',
          'paths': ['/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/snap/bin/google-chrome'],
          'url': 'chrome://extensions',
          'chromium': true,
        },
        {
          'name': 'Chromium',
          'paths': ['/usr/bin/chromium', '/usr/bin/chromium-browser', '/snap/bin/chromium'],
          'url': 'chrome://extensions',
          'chromium': true,
        },
        {
          'name': 'Microsoft Edge',
          'paths': ['/usr/bin/microsoft-edge', '/usr/bin/microsoft-edge-stable'],
          'url': 'edge://extensions',
          'chromium': true,
        },
        {
          'name': 'Brave Browser',
          'paths': ['/usr/bin/brave-browser', '/snap/bin/brave'],
          'url': 'brave://extensions',
          'chromium': true,
        },
        {
          'name': 'Opera',
          'paths': ['/usr/bin/opera', '/snap/bin/opera'],
          'url': 'opera://extensions',
          'chromium': true,
        },
        {
          'name': 'Vivaldi',
          'paths': ['/usr/bin/vivaldi', '/usr/bin/vivaldi-stable'],
          'url': 'vivaldi://extensions',
          'chromium': true,
        },
        {
          'name': 'Mozilla Firefox',
          'paths': ['/usr/bin/firefox', '/snap/bin/firefox'],
          'url': 'about:addons',
          'chromium': false,
        },
      ];

      for (final c in linuxCandidates) {
        final paths = c['paths'] as List<String>;
        for (final pth in paths) {
          if (await File(pth).exists()) {
            list.add(DetectedBrowser(
              name: c['name'] as String,
              executablePath: pth,
              extensionsUrl: c['url'] as String,
              isChromium: c['chromium'] as bool,
            ));
            break;
          }
        }
      }
    }

    return await _resolveIcons(list);
  }

  /// Extracts or locates actual browser icons directly from the operating system
  Future<List<DetectedBrowser>> _resolveIcons(List<DetectedBrowser> browsers) async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final iconDir = Directory(p.join(appSupport.path, 'browser_icons'));
      if (!await iconDir.exists()) {
        await iconDir.create(recursive: true);
      }

      final resolved = <DetectedBrowser>[];
      final toExtractWindows = <Map<String, String>>[];

      for (final b in browsers) {
        final safeName = b.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').toLowerCase();
        final targetFile = File(p.join(iconDir.path, '$safeName.png'));

        if (await targetFile.exists() && (await targetFile.length()) > 0) {
          resolved.add(b.copyWith(iconPath: targetFile.path));
          continue;
        }

        if (Platform.isWindows) {
          toExtractWindows.add({
            'browserName': b.name,
            'exe': b.executablePath,
            'out': targetFile.path,
          });
          resolved.add(b);
        } else if (Platform.isMacOS) {
          final iconPath = await _extractMacIcon(b.executablePath, targetFile.path);
          resolved.add(b.copyWith(iconPath: iconPath));
        } else if (Platform.isLinux) {
          final iconPath = await _resolveLinuxIcon(safeName);
          resolved.add(b.copyWith(iconPath: iconPath));
        } else {
          resolved.add(b);
        }
      }

      if (toExtractWindows.isNotEmpty) {
        await _extractWindowsIconsBatch(toExtractWindows);
        for (int i = 0; i < resolved.length; i++) {
          final b = resolved[i];
          if (b.iconPath == null) {
            final safeName = b.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').toLowerCase();
            final targetFile = File(p.join(iconDir.path, '$safeName.png'));
            if (await targetFile.exists() && (await targetFile.length()) > 0) {
              resolved[i] = b.copyWith(iconPath: targetFile.path);
            }
          }
        }
      }

      return resolved;
    } catch (e) {
      debugPrint('Error resolving browser icons from OS: $e');
      return browsers;
    }
  }

  Future<void> _extractWindowsIconsBatch(List<Map<String, String>> items) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('Add-Type -AssemblyName System.Drawing');
      buffer.writeln('\$items = @(');
      for (final item in items) {
        final exe = item['exe']!.replaceAll("'", "''");
        final out = item['out']!.replaceAll("'", "''");
        buffer.writeln("  @{ exe = '$exe'; out = '$out' }");
      }
      buffer.writeln(')');
      buffer.writeln(r'''
foreach ($item in $items) {
  try {
    $i = [System.Drawing.Icon]::ExtractAssociatedIcon($item.exe)
    if ($i -ne $null) {
      $b = $i.ToBitmap()
      $b.Save($item.out, [System.Drawing.Imaging.ImageFormat]::Png)
      $b.Dispose()
      $i.Dispose()
    }
  } catch {}
}
''');

      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        buffer.toString(),
      ]);
    } catch (e) {
      debugPrint('Windows icon extraction batch failed: $e');
    }
  }

  Future<String?> _extractMacIcon(String exePath, String targetPngPath) async {
    try {
      String appBundlePath = exePath;
      if (!appBundlePath.endsWith('.app')) {
        final idx = appBundlePath.indexOf('.app');
        if (idx != -1) {
          appBundlePath = appBundlePath.substring(0, idx + 4);
        }
      }
      final resourcesDir = Directory(p.join(appBundlePath, 'Contents', 'Resources'));
      if (await resourcesDir.exists()) {
        final entries = await resourcesDir.list().toList();
        final icnsFiles = entries.whereType<File>().where((f) => f.path.endsWith('.icns')).toList();
        if (icnsFiles.isNotEmpty) {
          final icnsPath = icnsFiles.first.path;
          await Process.run('sips', [
            '-s',
            'format',
            'png',
            icnsPath,
            '--out',
            targetPngPath,
            '-z',
            '128',
            '128',
          ]);
          final targetFile = File(targetPngPath);
          if (await targetFile.exists() && (await targetFile.length()) > 0) {
            return targetFile.path;
          }
        }
      }
    } catch (e) {
      debugPrint('macOS icon extraction failed: $e');
    }
    return null;
  }

  Future<String?> _resolveLinuxIcon(String safeName) async {
    try {
      final iconNames = [
        safeName,
        safeName.replaceAll('_', '-'),
        'google-chrome',
        'google-chrome-stable',
        'microsoft-edge',
        'brave-browser',
        'opera',
        'vivaldi',
        'firefox',
        'chromium-browser',
        'chromium',
      ];
      for (final iname in iconNames) {
        final candidatePaths = [
          '/usr/share/icons/hicolor/128x128/apps/$iname.png',
          '/usr/share/icons/hicolor/scalable/apps/$iname.svg',
          '/usr/share/icons/hicolor/64x64/apps/$iname.png',
          '/usr/share/icons/hicolor/48x48/apps/$iname.png',
          '/usr/share/pixmaps/$iname.png',
        ];
        for (final cp in candidatePaths) {
          if (await File(cp).exists()) {
            return cp;
          }
        }
      }
    } catch (e) {
      debugPrint('Linux icon resolution failed: $e');
    }
    return null;
  }

  /// Automatically launches the browser with the extension loaded
  Future<bool> launchBrowserWithExtension(DetectedBrowser browser) async {
    try {
      final extPath = await getExtensionPath();

      // Copy extension path to clipboard for convenient developer mode setup
      await Clipboard.setData(ClipboardData(text: extPath));

      if (browser.isChromium) {
        // Launch with --load-extension flag
        await Process.start(
          browser.executablePath,
          [
            '--load-extension=$extPath',
            browser.extensionsUrl,
          ],
          mode: ProcessStartMode.detached,
        );
        return true;
      } else {
        await Process.start(
          browser.executablePath,
          [browser.extensionsUrl],
          mode: ProcessStartMode.detached,
        );
        return true;
      }
    } catch (e) {
      debugPrint('Failed to launch browser with extension: $e');
      return false;
    }
  }

  /// Opens the extension folder in Windows Explorer or system file manager
  Future<void> openExtensionFolder() async {
    final extPath = await getExtensionPath();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [extPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [extPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [extPath]);
    }
  }

  /// Copies extension path to clipboard
  Future<String> copyExtensionPathToClipboard() async {
    final extPath = await getExtensionPath();
    await Clipboard.setData(ClipboardData(text: extPath));
    return extPath;
  }
}

