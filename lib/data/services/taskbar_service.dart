import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import '../../core/enums.dart';
import '../../domain/models/download_task.dart';

class TaskbarService {
  @visibleForTesting
  static void Function(int mode)? mockSetProgressMode;

  @visibleForTesting
  static void Function(int completed, int total)? mockSetProgress;

  int _currentMode = TaskbarProgressMode.noProgress;
  int _lastCompleted = -1;
  int _lastTotal = -1;

  int get currentMode => _currentMode;

  /// Updates the Windows taskbar progress bar based on active download tasks.
  /// - 0 downloading tasks: clears progress (or shows paused if tasks are paused).
  /// - 1 downloading task: shows progress for that specific download.
  /// - >1 downloading tasks: calculates and displays overall combined progress.
  void updateProgress(List<DownloadTask> tasks) {
    if (kIsWeb || (!Platform.isWindows && mockSetProgressMode == null)) return;

    try {
      final downloadingTasks = tasks
          .where((t) => t.status == DownloadStatus.downloading)
          .toList();

      if (downloadingTasks.isEmpty) {
        final pausedTasks = tasks
            .where((t) => t.status == DownloadStatus.paused)
            .toList();

        if (pausedTasks.isNotEmpty) {
          int totalDownloaded = pausedTasks.fold(0, (sum, t) => sum + t.downloadedBytes);
          int totalBytes = pausedTasks.fold(0, (sum, t) => sum + (t.totalBytes > 0 ? t.totalBytes : 0));

          _setMode(TaskbarProgressMode.paused);
          if (totalBytes > 0) {
            _setProgress(totalDownloaded, totalBytes);
          }
        } else {
          _setMode(TaskbarProgressMode.noProgress);
        }
        return;
      }

      if (downloadingTasks.length == 1) {
        final single = downloadingTasks.first;
        if (single.totalBytes > 0) {
          _setMode(TaskbarProgressMode.normal);
          _setProgress(single.downloadedBytes, single.totalBytes);
        } else {
          _setMode(TaskbarProgressMode.indeterminate);
        }
      } else {
        // Multiple active downloads: aggregate overall progress
        int totalDownloaded = downloadingTasks.fold(
          0,
          (sum, t) => sum + t.downloadedBytes,
        );
        int totalBytes = downloadingTasks.fold(
          0,
          (sum, t) => sum + (t.totalBytes > 0 ? t.totalBytes : 0),
        );

        if (totalBytes > 0) {
          _setMode(TaskbarProgressMode.normal);
          _setProgress(totalDownloaded, totalBytes);
        } else {
          _setMode(TaskbarProgressMode.indeterminate);
        }
      }
    } catch (e) {
      debugPrint('Error updating taskbar progress: $e');
    }
  }

  void _setMode(int mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      if (mockSetProgressMode != null) {
        mockSetProgressMode!(mode);
      } else {
        WindowsTaskbar.setProgressMode(mode);
      }
    }
  }

  void _setProgress(int completed, int total) {
    if (_lastCompleted != completed || _lastTotal != total) {
      _lastCompleted = completed;
      _lastTotal = total;
      if (mockSetProgress != null) {
        mockSetProgress!(completed, total);
      } else {
        WindowsTaskbar.setProgress(completed, total);
      }
    }
  }

  /// Clears the taskbar progress bar
  void clear() {
    if (kIsWeb || (!Platform.isWindows && mockSetProgressMode == null)) return;
    try {
      _setMode(TaskbarProgressMode.noProgress);
      _lastCompleted = -1;
      _lastTotal = -1;
    } catch (_) {}
  }

  void dispose() {
    clear();
  }
}
