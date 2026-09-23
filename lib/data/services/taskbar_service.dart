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
      final prevMode = _currentMode;
      _currentMode = mode;
      if (mockSetProgressMode != null) {
        mockSetProgressMode!(mode);
      } else {
        WindowsTaskbar.setProgressMode(mode).catchError((e) {
          debugPrint('WindowsTaskbar.setProgressMode error: $e');
          // Reset so subsequent ticks will retry once window is ready/visible
          _currentMode = prevMode;
        });
      }
    }
  }

  void _setProgress(int completed, int total) {
    // WindowsTaskbar plugin uses int32_t internally (max 2,147,483,647).
    // For downloads larger than 10,000 bytes (especially > 2GB files),
    // normalize the progress to 0-10,000 range to prevent int32 overflow
    // and int64 variant type mismatch in the native Windows plugin.
    int safeCompleted = completed;
    int safeTotal = total;
    if (safeTotal > 10000) {
      safeCompleted = ((completed / total) * 10000).clamp(0, 10000).toInt();
      safeTotal = 10000;
    }

    if (_lastCompleted != safeCompleted || _lastTotal != safeTotal) {
      final prevCompleted = _lastCompleted;
      final prevTotal = _lastTotal;
      _lastCompleted = safeCompleted;
      _lastTotal = safeTotal;
      if (mockSetProgress != null) {
        mockSetProgress!(safeCompleted, safeTotal);
      } else {
        WindowsTaskbar.setProgress(safeCompleted, safeTotal).catchError((e) {
          debugPrint('WindowsTaskbar.setProgress error: $e');
          _lastCompleted = prevCompleted;
          _lastTotal = prevTotal;
        });
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
