import 'package:flutter_test/flutter_test.dart';
import 'package:virus_download_manager/core/enums.dart';
import 'package:virus_download_manager/data/services/taskbar_service.dart';
import 'package:virus_download_manager/domain/models/download_task.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

void main() {
  group('TaskbarService Tests', () {
    late TaskbarService service;
    int? recordedMode;
    int? recordedCompleted;
    int? recordedTotal;

    setUp(() {
      service = TaskbarService();
      recordedMode = null;
      recordedCompleted = null;
      recordedTotal = null;

      TaskbarService.mockSetProgressMode = (mode) {
        recordedMode = mode;
      };
      TaskbarService.mockSetProgress = (completed, total) {
        recordedCompleted = completed;
        recordedTotal = total;
      };
    });

    tearDown(() {
      TaskbarService.mockSetProgressMode = null;
      TaskbarService.mockSetProgress = null;
    });

    DownloadTask createTask({
      required String id,
      required DownloadStatus status,
      int downloaded = 0,
      int total = 1000,
    }) {
      return DownloadTask(
        id: id,
        url: 'https://example.com/$id.zip',
        fileName: '$id.zip',
        savePath: 'C:/Downloads/$id.zip',
        totalBytes: total,
        downloadedBytes: downloaded,
        status: status,
        dateAdded: DateTime.now(),
      );
    }

    test('updateProgress with 0 downloading tasks and no paused tasks clears progress', () {
      // Transition from active downloading to 0 downloading tasks
      final active = [
        createTask(id: '1', status: DownloadStatus.downloading, downloaded: 50, total: 100),
      ];
      service.updateProgress(active);
      expect(service.currentMode, TaskbarProgressMode.normal);
      expect(recordedMode, TaskbarProgressMode.normal);

      final completedTasks = [
        createTask(id: '1', status: DownloadStatus.completed, downloaded: 1000, total: 1000),
      ];

      service.updateProgress(completedTasks);
      expect(service.currentMode, TaskbarProgressMode.noProgress);
      expect(recordedMode, TaskbarProgressMode.noProgress);
    });

    test('updateProgress with 1 downloading task with known size sets normal progress', () {
      final tasks = [
        createTask(id: '1', status: DownloadStatus.downloading, downloaded: 450, total: 1000),
      ];

      service.updateProgress(tasks);
      expect(service.currentMode, TaskbarProgressMode.normal);
      expect(recordedMode, TaskbarProgressMode.normal);
      expect(recordedCompleted, 450);
      expect(recordedTotal, 1000);
    });

    test('updateProgress with 1 downloading task with unknown size sets indeterminate', () {
      final tasks = [
        createTask(id: '1', status: DownloadStatus.downloading, downloaded: 200, total: 0),
      ];

      service.updateProgress(tasks);
      expect(service.currentMode, TaskbarProgressMode.indeterminate);
      expect(recordedMode, TaskbarProgressMode.indeterminate);
    });

    test('updateProgress with multiple downloading tasks computes overall combined progress', () {
      final tasks = [
        createTask(id: '1', status: DownloadStatus.downloading, downloaded: 200, total: 1000),
        createTask(id: '2', status: DownloadStatus.downloading, downloaded: 300, total: 2000),
        createTask(id: '3', status: DownloadStatus.completed, downloaded: 500, total: 500),
      ];

      service.updateProgress(tasks);
      expect(service.currentMode, TaskbarProgressMode.normal);
      expect(recordedMode, TaskbarProgressMode.normal);
      // Total downloaded: 200 + 300 = 500
      // Total bytes: 1000 + 2000 = 3000
      expect(recordedCompleted, 500);
      expect(recordedTotal, 3000);
    });

    test('updateProgress with only paused tasks sets paused progress mode', () {
      final tasks = [
        createTask(id: '1', status: DownloadStatus.paused, downloaded: 200, total: 1000),
      ];

      service.updateProgress(tasks);
      expect(service.currentMode, TaskbarProgressMode.paused);
      expect(recordedMode, TaskbarProgressMode.paused);
      expect(recordedCompleted, 200);
      expect(recordedTotal, 1000);
    });

    test('clear() resets progress mode to noProgress', () {
      final tasks = [
        createTask(id: '1', status: DownloadStatus.downloading, downloaded: 100, total: 200),
      ];
      service.updateProgress(tasks);
      expect(service.currentMode, TaskbarProgressMode.normal);

      service.clear();
      expect(service.currentMode, TaskbarProgressMode.noProgress);
      expect(recordedMode, TaskbarProgressMode.noProgress);
    });

    test('updateProgress with large file (> 2GB) scales safely to 10,000 without int32 overflow', () {
      // 5 GB file with 2.5 GB downloaded (50%)
      const fiveGb = 5 * 1024 * 1024 * 1024;
      const twoAndHalfGb = 2560 * 1024 * 1024;
      final tasks = [
        createTask(id: '1', status: DownloadStatus.downloading, downloaded: twoAndHalfGb, total: fiveGb),
      ];

      service.updateProgress(tasks);
      expect(service.currentMode, TaskbarProgressMode.normal);
      expect(recordedMode, TaskbarProgressMode.normal);
      expect(recordedCompleted, 5000);
      expect(recordedTotal, 10000);
    });
  });
}

