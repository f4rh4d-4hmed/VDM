import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/services/antivirus_service.dart';
import '../../data/services/integrity_service.dart';
import '../../data/services/virus_total_service.dart';
import '../../domain/models/download_task.dart';
import '../../domain/models/virus_scan_result.dart';

class DownloadsViewModel extends ChangeNotifier {
  final DownloadRepository repository;

  DownloadStatus? _statusFilter; // null = All
  DownloadCategory _categoryFilter = DownloadCategory.all;
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.dateAdded;

  final Set<String> _autoScannedTaskIds = {};

  DownloadsViewModel({required this.repository}) {
    repository.addListener(_onRepositoryUpdated);
  }

  @override
  void dispose() {
    repository.removeListener(_onRepositoryUpdated);
    super.dispose();
  }

  void _onRepositoryUpdated() {
    final settings = repository.settingsRepo.currentSettings;
    if (settings.autoScanWithVirusTotal && settings.virusTotalApiKey.isNotEmpty) {
      for (final t in repository.tasks) {
        if (t.status == DownloadStatus.completed && !_autoScannedTaskIds.contains(t.id)) {
          _autoScannedTaskIds.add(t.id);
          scanTaskWithVirusScanner(t.id);
        }
      }
    }
    notifyListeners();
  }

  // Getters
  DownloadStatus? get statusFilter => _statusFilter;
  DownloadCategory get categoryFilter => _categoryFilter;
  String get searchQuery => _searchQuery;
  SortOrder get sortOrder => _sortOrder;

  // All Tasks (unfiltered)
  List<DownloadTask> get allTasks => repository.tasks;

  // Filtered & Sorted Tasks
  List<DownloadTask> get tasks {
    var result = List<DownloadTask>.from(repository.tasks);

    // Filter by status
    if (_statusFilter != null) {
      if (_statusFilter == DownloadStatus.downloading) {
        // Include queued in active downloads view
        result = result
            .where((t) =>
                t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.queued)
            .toList();
      } else {
        result = result.where((t) => t.status == _statusFilter).toList();
      }
    }

    // Filter by category
    if (_categoryFilter != DownloadCategory.all) {
      result = result.where((t) => t.category == _categoryFilter).toList();
    }

    // Filter by search query
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      result = result
          .where((t) =>
              t.fileName.toLowerCase().contains(query) ||
              t.url.toLowerCase().contains(query))
          .toList();
    }

    // Sort
    switch (_sortOrder) {
      case SortOrder.dateAdded:
        result.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case SortOrder.name:
        result.sort((a, b) =>
            a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
        break;
      case SortOrder.size:
        result.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
        break;
    }

    return result;
  }

  /// Tasks that are actively running, queued, or paused
  List<DownloadTask> get activeTasks => getActiveTasks();

  /// Returns active tasks, optionally filtered by a specific active status
  List<DownloadTask> getActiveTasks([DownloadStatus? statusFilter]) {
    var result = repository.tasks
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.paused)
        .toList();

    if (statusFilter != null) {
      if (statusFilter == DownloadStatus.downloading) {
        result = result
            .where((t) =>
                t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.queued)
            .toList();
      } else {
        result = result.where((t) => t.status == statusFilter).toList();
      }
    }

    result.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return result;
  }

  // Stats
  int get totalCount => repository.tasks.length;

  /// Total count of in-progress tasks (downloading + queued + paused)
  int get activeCount => repository.tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued ||
          t.status == DownloadStatus.paused)
      .length;

  int get downloadingCount => repository.tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued)
      .length;

  int get pausedCount => repository.tasks
      .where((t) => t.status == DownloadStatus.paused)
      .length;

  int get queuedCount => repository.tasks
      .where((t) => t.status == DownloadStatus.queued)
      .length;

  int get completedCount => repository.tasks
      .where((t) => t.status == DownloadStatus.completed)
      .length;

  int get failedCount => repository.tasks
      .where((t) =>
          t.status == DownloadStatus.failed ||
          t.status == DownloadStatus.cancelled)
      .length;

  double get totalSpeedBytesPerSec => repository.tasks
      .where((t) => t.status == DownloadStatus.downloading)
      .fold(0.0, (sum, t) => sum + t.speedBytesPerSec);

  int get totalDownloadedBytes =>
      repository.tasks.fold(0, (sum, t) => sum + t.downloadedBytes);

  int getCountForCategory(DownloadCategory category) {
    if (category == DownloadCategory.all) return repository.tasks.length;
    return repository.tasks.where((t) => t.category == category).length;
  }

  // Setters
  void setStatusFilter(DownloadStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void setCategoryFilter(DownloadCategory category) {
    _categoryFilter = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  // Actions
  Future<void> addDownload({
    required String url,
    required String fileName,
    required String targetDirectory,
    DownloadCategory? category,
    Map<String, String>? headers,
    bool? isResumable,
  }) {
    return repository.addTask(
      url: url,
      fileName: fileName,
      targetDirectory: targetDirectory,
      category: category,
      headers: headers,
      isResumable: isResumable,
    );
  }

  Future<void> pause(String id) => repository.pauseDownload(id);
  Future<void> resume(String id) => repository.resumeDownload(id);
  Future<void> cancel(String id) => repository.cancelDownload(id);
  Future<void> retry(String id) => repository.retryDownload(id);
  Future<void> changeDownloadUrl(
    String id,
    String newUrl, {
    Map<String, String>? headers,
    bool restartFromBeginning = false,
  }) =>
      repository.changeDownloadUrl(
        id,
        newUrl,
        headers: headers,
        restartFromBeginning: restartFromBeginning,
      );
  Future<void> remove(String id, {bool deleteFile = false}) =>
      repository.removeTask(id, deleteFileOnDisk: deleteFile);

  Future<void> rename(String id, String newName) =>
      repository.renameTask(id, newName);

  Future<void> pauseAll() => repository.pauseAll();
  Future<void> resumeAll() => repository.resumeAll();
  Future<void> cancelAllActive() => repository.cancelAllActive();

  Future<RecheckResult> recheck(String id, {void Function(double progress, String status)? onProgress}) =>
      repository.recheckTask(id, onProgress: onProgress);

  Future<String> calculateHash(
    String id,
    HashAlgorithm algo, {
    void Function(double progress)? onProgress,
  }) =>
      repository.calculateFileHash(id, algo, onProgress: onProgress);

  Future<RepairResult> scanAndRepairZeroGaps(
    String id, {
    int pieceSize = 8 * 1024 * 1024,
    void Function(double progress, String status)? onProgress,
  }) =>
      repository.scanAndRepairZeroGaps(id, pieceSize: pieceSize, onProgress: onProgress);

  Future<List<ZeroPiece>> findZeroPieces(
    String id, {
    int pieceSize = 8 * 1024 * 1024,
    void Function(double progress, String status)? onProgress,
  }) =>
      repository.findZeroPieces(id, pieceSize: pieceSize, onProgress: onProgress);

  final VirusTotalService _virusTotalService = VirusTotalService();
  final Map<String, VirusScanResult> _virusScanResults = {};

  VirusScanResult? getVirusScanResult(String taskId) => _virusScanResults[taskId];

  /// Scans a task using the dual-engine Virus Scanner:
  /// - Desktop Built-in Antivirus Handover (Desktop only)
  /// - VirusTotal v3 Hash lookup (All platforms)
  /// Files <= 5 GB are scanned automatically. Files > 5 GB require [forceManualScan] = true.
  Future<VirusScanResult> scanTaskWithVirusScanner(
    String taskId, {
    bool forceManualScan = false,
    String? customApiKey,
  }) async {
    final taskIndex = repository.tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      final res = VirusScanResult.error(message: 'Task not found.');
      _virusScanResults[taskId] = res;
      notifyListeners();
      return res;
    }
    final task = repository.tasks[taskIndex];
    final file = File(task.savePath);
    if (!await file.exists()) {
      final res = VirusScanResult.error(message: 'File not found on disk: ${task.savePath}');
      _virusScanResults[taskId] = res;
      notifyListeners();
      return res;
    }

    final fileSize = await file.length();

    // 1. Desktop Antivirus Handover (Desktop only)
    DesktopHandoverResult? handoverResult;
    if (AppUtils.isDesktop && repository.settingsRepo.currentSettings.enableDesktopAntivirusHandover) {
      handoverResult = await repository.antivirusService.performDesktopHandover(
        task.savePath,
        sourceUrl: task.url,
        referrerUrl: task.headers?['Referer'] ?? task.headers?['referer'],
        fileSizeBytes: fileSize,
        forceManualScan: forceManualScan,
      );
    }

    // 2. Check 5 GB boundary for automatic detection
    if (!forceManualScan && !repository.antivirusService.shouldAutoScan(fileSize)) {
      final res = VirusScanResult.skippedTooLarge(
        fileSizeBytes: fileSize,
        desktopAntivirusHandedOver: handoverResult?.success ?? false,
        desktopAntivirusDetails: handoverResult?.details,
      );
      _virusScanResults[taskId] = res;
      notifyListeners();
      return res;
    }

    // 3. Compute SHA-256 hash using IntegrityService
    final integrityService = repository.integrityService ?? IntegrityService();
    final sha256Hash = await integrityService.calculateFileHash(
      task.savePath,
      HashAlgorithm.sha256,
    );

    // 4. VirusTotal lookup
    final apiKey = (customApiKey != null && customApiKey.isNotEmpty)
        ? customApiKey.trim()
        : repository.settingsRepo.currentSettings.virusTotalApiKey;

    if (apiKey.isEmpty) {
      final res = VirusScanResult(
        status: VirusScanStatus.notFound,
        fileSha256: sha256Hash,
        fileSizeBytes: fileSize,
        errorMessage: 'VirusTotal API key is not configured.',
        desktopAntivirusHandedOver: handoverResult?.success ?? false,
        desktopAntivirusDetails: handoverResult?.details,
      );
      _virusScanResults[taskId] = res;
      notifyListeners();
      return res;
    }

    final res = await _virusTotalService.scanFileHash(
      sha256Hash,
      apiKey,
      fileSizeBytes: fileSize,
      desktopAntivirusHandedOver: handoverResult?.success ?? false,
      desktopAntivirusDetails: handoverResult?.details,
      forceManualScan: forceManualScan,
    );

    _virusScanResults[taskId] = res;
    notifyListeners();
    return res;
  }

  Future<VirusScanResult> uploadTaskToVirusTotal(
    String taskId, {
    String? customApiKey,
    void Function(double progress)? onProgress,
  }) async {
    final taskIndex = repository.tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      return VirusScanResult.error(message: 'Task not found.');
    }
    final task = repository.tasks[taskIndex];
    final apiKey = (customApiKey != null && customApiKey.isNotEmpty)
        ? customApiKey.trim()
        : repository.settingsRepo.currentSettings.virusTotalApiKey;

    final cached = _virusScanResults[taskId];

    final res = await _virusTotalService.uploadAndScanFile(
      task.savePath,
      apiKey,
      sha256Hash: cached?.fileSha256,
      onProgress: onProgress,
    );
    _virusScanResults[taskId] = res;
    notifyListeners();
    return res;
  }
}

