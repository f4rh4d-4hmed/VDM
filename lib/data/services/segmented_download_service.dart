import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../domain/models/proxy_config.dart';
import 'adaptive_rate_limiter.dart';
import 'file_service.dart';
import 'http_download_service.dart';
import 'proxy_service.dart';

/// Maximum file size for placeholder pre-allocation (3GB).
/// Files larger than or equal to 3GB skip pre-allocation to prevent system stutter and disk wear.
const int maxPlaceholderFileSize = 3 * 1024 * 1024 * 1024;

class SegmentWorkerState {
  final int index;
  final int startByte;
  int endByte;
  int downloadedBytes;
  final ProxyConfig? proxy; // null = direct connection

  SegmentWorkerState({
    required this.index,
    required this.startByte,
    required this.endByte,
    this.downloadedBytes = 0,
    this.proxy,
  });

  int get totalSegmentBytes => (endByte - startByte) + 1;
  int get currentOffset => startByte + downloadedBytes;
  bool get isFinished => downloadedBytes >= totalSegmentBytes;
  int get remainingBytes => math.max(0, totalSegmentBytes - downloadedBytes);

  Map<String, dynamic> toJson() => {
        'index': index,
        'startByte': startByte,
        'endByte': endByte,
        'downloadedBytes': downloadedBytes,
      };

  factory SegmentWorkerState.fromJson(Map<String, dynamic> json) =>
      SegmentWorkerState(
        index: json['index'] as int,
        startByte: json['startByte'] as int,
        endByte: json['endByte'] as int,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      );
}

/// Dynamic proxy pool for Rocket Mode.
/// Dispenses candidate proxies, tracks dead or slow proxies, and rotates dynamically.
class DynamicProxyPool {
  final List<ProxyConfig> _candidates;
  final Set<String> _deadOrSlowProxies = {};
  int _nextIndex = 0;

  DynamicProxyPool(List<ProxyConfig> proxies)
      : _candidates = List.of(proxies) {
    // Sort candidates: proxies with verified positive benchmark speed come first
    _candidates.sort((a, b) {
      final sA = a.lastBenchmarkSpeed ?? 0.0;
      final sB = b.lastBenchmarkSpeed ?? 0.0;
      return sB.compareTo(sA);
    });
  }

  bool get isEmpty => _candidates.isEmpty;
  int get candidateCount => _candidates.length;
  int get deadOrSlowCount => _deadOrSlowProxies.length;

  /// Acquires the next available candidate proxy that has not been marked slow or dead.
  ProxyConfig? acquireNext() {
    while (_nextIndex < _candidates.length) {
      final p = _candidates[_nextIndex++];
      if (!_deadOrSlowProxies.contains(p.originalUrl) &&
          !_deadOrSlowProxies.contains(p.displayUrl)) {
        return p;
      }
    }
    return null;
  }

  /// Returns an active proxy, cycling round-robin among healthy proxies.
  /// Used to assign proxies when workerCount > candidateCount, or during work stealing.
  ProxyConfig? getBestActiveProxy() {
    final healthy = _candidates
        .where((p) =>
            !_deadOrSlowProxies.contains(p.originalUrl) &&
            !_deadOrSlowProxies.contains(p.displayUrl))
        .toList();
    if (healthy.isEmpty) return null;
    return healthy[(_nextIndex++) % healthy.length];
  }

  /// Checks if there is an alternative healthy proxy available to rotate to.
  bool hasAlternativeProxy(ProxyConfig current) {
    return _candidates.any((p) =>
        p.originalUrl != current.originalUrl &&
        p.displayUrl != current.displayUrl &&
        !_deadOrSlowProxies.contains(p.originalUrl) &&
        !_deadOrSlowProxies.contains(p.displayUrl));
  }

  /// Marks a proxy as slow, stalled, or dead so it won't be reused.
  void markSlowOrDead(ProxyConfig proxy, {String? reason}) {
    _deadOrSlowProxies.add(proxy.originalUrl);
    _deadOrSlowProxies.add(proxy.displayUrl);
  }
}

class SegmentedDownloadService {
  final ProxyService proxyService;
  final FileService fileService;

  SegmentedDownloadService({
    required this.proxyService,
    required this.fileService,
  });

  /// Download a file using multiple parallel segment workers, with optional
  /// placeholder allocation, Rocket Mode proxy distribution, and speed limiting.
  Future<void> downloadFileSegmented({
    required String url,
    required String savePath,
    String? tempPath,
    String? metaPath,
    required int workerCount,
    required CancelToken cancelToken,
    required DownloadProgressCallback onProgress,
    bool usePlaceholderMode = true,
    SpeedLimitMode speedLimitMode = SpeedLimitMode.unlimited,
    List<ProxyConfig> availableProxies = const [],
    Map<String, String>? headers,
    void Function({required bool isResumable})? onResumableChecked,
    void Function(String message)? onStatusMessage,
    AdaptiveRateLimiter? rateLimiter,
  }) async {
    final limiter = rateLimiter ?? AdaptiveRateLimiter();

    // 1. Probe the remote server to check resumability and total file size
    final probeDio = proxyService.createDioWithProxy(null);
    final probeHeaders = <String, dynamic>{};
    if (headers != null) probeHeaders.addAll(headers);

    Response probeResp;
    try {
      await limiter.acquireToken(cancelToken: cancelToken);
      // 1. Try HEAD with bytes=0-0
      probeResp = await probeDio.head(
        url,
        options: Options(
          headers: {...probeHeaders, 'range': 'bytes=0-0'},
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
    } catch (_) {
      try {
        // 2. Try HEAD without range
        probeResp = await probeDio.head(
          url,
          options: Options(
            headers: probeHeaders,
            validateStatus: (s) => s != null && s >= 200 && s < 400,
          ),
          cancelToken: cancelToken,
        );
      } catch (_) {
        try {
          // 3. Try stream GET with range
          probeResp = await probeDio.get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              headers: {...probeHeaders, 'range': 'bytes=0-0'},
              validateStatus: (s) => s != null && s >= 200 && s < 400,
            ),
            cancelToken: cancelToken,
          );
        } catch (_) {
          // 4. Try stream GET without range
          probeResp = await probeDio.get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              headers: probeHeaders,
              validateStatus: (s) => s != null && s >= 200 && s < 400,
            ),
            cancelToken: cancelToken,
          );
        }
      }
    }

    final acceptRanges = probeResp.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
    final contentRange = probeResp.headers.value(HttpHeaders.contentRangeHeader);
    int totalBytes = 0;

    if (contentRange != null) {
      final match = RegExp(r'/(\d+)').firstMatch(contentRange);
      if (match != null) {
        totalBytes = int.tryParse(match.group(1) ?? '') ?? 0;
      }
    } else {
      final cl = probeResp.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) totalBytes = int.tryParse(cl) ?? 0;
    }

    final isResumable = probeResp.statusCode == 206 ||
        acceptRanges == 'bytes' ||
        contentRange != null;

    onResumableChecked?.call(isResumable: isResumable);

    // 2. Storage Strategy
    final shouldPreallocate = usePlaceholderMode &&
        totalBytes > 0 &&
        totalBytes < maxPlaceholderFileSize;

    final String activeFilePath = tempPath ?? savePath;

    // If server does not support byte ranges or size is unknown, fallback to single stream
    if (!isResumable || totalBytes <= 0 || (workerCount <= 1 && speedLimitMode != SpeedLimitMode.rocket)) {
      final singleService = HttpDownloadService();
      await singleService.downloadFile(
        url: url,
        savePath: activeFilePath,
        cancelToken: cancelToken,
        onProgress: onProgress,
        allowResume: isResumable,
        headers: headers,
        onResumableChecked: onResumableChecked,
      );
      if (activeFilePath != savePath && !cancelToken.isCancelled) {
        onStatusMessage?.call('Moving file to destination...');
        await fileService.moveFile(activeFilePath, savePath);
      }
      return;
    }

    // 3. Worker Distribution & Dynamic Proxy Pool for Rocket Mode
    final clampedWorkers = (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty)
        ? math.max(4, workerCount).clamp(1, 16)
        : workerCount.clamp(1, 16);
    final workerList = <SegmentWorkerState>[];
    final proxyPool = DynamicProxyPool(availableProxies);

    if (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty) {
      onStatusMessage?.call(
        'Rocket mode: Active with ${availableProxies.length} proxies (in-flight testing & auto-handover enabled).',
      );
    }

    // Check for existing metadata (resuming segmented download)
    final metaFile = File(metaPath ?? '$activeFilePath.vdown_meta');
    bool metaRestored = false;

    // Failsafe migration: if metadata exists at legacy locations but not metaFile
    if (!await metaFile.exists()) {
      final legacyMeta = File('$savePath.vdown_meta');
      if (await legacyMeta.exists()) {
        try {
          await legacyMeta.copy(metaFile.path);
          await fileService.deleteFile(legacyMeta.path);
        } catch (_) {}
      } else if (tempPath != null) {
        final legacyTempMeta = File('$tempPath.vdown_meta');
        if (await legacyTempMeta.exists()) {
          try {
            await legacyTempMeta.copy(metaFile.path);
            await fileService.deleteFile(legacyTempMeta.path);
          } catch (_) {}
        }
      }
    }

    if (await metaFile.exists()) {
      try {
        final metaContent = await metaFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(metaContent);
        final restored = jsonList
            .whereType<Map<String, dynamic>>()
            .map(SegmentWorkerState.fromJson)
            .toList();

        if (_isValidSegmentList(restored, totalBytes)) {
          workerList.addAll(restored);
          metaRestored = true;
        }
      } catch (e) {
        debugPrint('Error restoring segment metadata: $e');
      }
    }

    if (!metaRestored) {
      workerList.clear();
      final blockSize = (totalBytes / clampedWorkers).ceil();
      for (int i = 0; i < clampedWorkers; i++) {
        final start = i * blockSize;
        final end = math.min((i + 1) * blockSize - 1, totalBytes - 1);
        if (start > totalBytes - 1) break;

        ProxyConfig? assignedProxy;
        if (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty) {
          // Worker 0 is always direct connection for maximum stability and baseline throughput.
          // Remaining workers acquire candidate proxies from the pool or cycle round-robin.
          if (i >= 1) {
            assignedProxy = proxyPool.acquireNext() ?? proxyPool.getBestActiveProxy();
          }
        }

        workerList.add(
          SegmentWorkerState(
            index: i,
            startByte: start,
            endByte: end,
            downloadedBytes: 0,
            proxy: assignedProxy,
          ),
        );
      }
    }

    // 4. File Initialization / Placeholder Mode
    final targetFile = File(activeFilePath);
    if (!await targetFile.exists() || !metaRestored) {
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      if (shouldPreallocate) {
        onStatusMessage?.call('Pre-allocating placeholder file...');
        final raf = await targetFile.open(mode: FileMode.write);
        try {
          await raf.truncate(totalBytes);
        } catch (_) {
          // If fast truncate fails, write initial zero
          await raf.writeByte(0);
        } finally {
          await raf.close();
        }
      } else {
        await targetFile.create(recursive: true);
      }
    }

    // Persist initial metadata
    await _saveMeta(metaFile, workerList);

    // 5. Execution: Stream chunks and write concurrently
    final raf = await targetFile.open(mode: FileMode.append);
    int totalDownloaded = workerList.fold(0, (sum, w) => sum + w.downloadedBytes);

    int lastSampleBytes = totalDownloaded;
    DateTime lastSampleTime = DateTime.now();
    double currentSpeed = 0.0;
    final maxSpeed = speedLimitMode.maxBytesPerSecond;

    // Mutex write queue for safe sequential writes to file
    Future<void> writeQueue = Future.value();
    Future<void> writeChunk(int writeOffset, List<int> chunk) {
      final completer = Completer<void>();
      writeQueue = writeQueue.then((_) async {
        try {
          await raf.setPosition(writeOffset);
          await raf.writeFrom(chunk);
          completer.complete();
        } catch (e, st) {
          completer.completeError(e, st);
        }
      });
      return completer.future;
    }

    // Launch workers with Dynamic Work Stealing to eliminate the straggler problem
    final activeSegments = <SegmentWorkerState>{};
    final workerFutures = <Future<void>>[];

    for (int slot = 0; slot < clampedWorkers; slot++) {
      workerFutures.add(() async {
        // Preferred proxy for this slot:
        // Slot 0 is always direct connection in Rocket Mode.
        // Other slots use proxies from proxyPool.
        ProxyConfig? currentProxy;
        if (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty) {
          if (slot >= 1) {
            currentProxy = proxyPool.acquireNext() ?? proxyPool.getBestActiveProxy();
          }
        }

        while (!cancelToken.isCancelled) {
          final SegmentWorkerState? worker = _acquireNextWork(
            workerList,
            activeSegments,
            preferredProxy: currentProxy,
          );

          if (worker == null) {
            // No more work available to steal
            break;
          }

          if (worker.index >= clampedWorkers) {
            onStatusMessage?.call(
              'Worker ${slot + 1}: Dynamic work stealing activated (Range: ${worker.startByte}-${worker.endByte}).',
            );
          }

          // Use the worker's own proxy if set, or fall back to this slot's proxy
          if (worker.proxy != null) {
            currentProxy = worker.proxy;
          } else if (slot >= 1 && speedLimitMode == SpeedLimitMode.rocket && currentProxy == null) {
            currentProxy = proxyPool.acquireNext() ?? proxyPool.getBestActiveProxy();
          }

          int directRetries = 0;

          while (worker.currentOffset <= worker.endByte && !cancelToken.isCancelled) {
            final startRange = worker.currentOffset;
            final endRange = worker.endByte;
            if (startRange > endRange) break;

            final reqHeaders = <String, dynamic>{
              'range': 'bytes=$startRange-$endRange',
            };
            if (headers != null) reqHeaders.addAll(headers);

            final dio = proxyService.createDioWithProxy(
              currentProxy,
              baseOptions: BaseOptions(
                connectTimeout: currentProxy != null
                    ? const Duration(seconds: 5)
                    : const Duration(seconds: 15),
                receiveTimeout: currentProxy != null
                    ? const Duration(seconds: 12)
                    : const Duration(seconds: 30),
              ),
            );

            final requestCancelToken = CancelToken();
            void onParentCancel() {
              if (!requestCancelToken.isCancelled) {
                requestCancelToken.cancel('Parent cancelled');
              }
            }

            cancelToken.whenCancel.then((_) => onParentCancel());

            bool shouldRotateProxy = false;
            String? failureReason;
            final sessionWatch = Stopwatch()..start();
            int bytesInSession = 0;

            try {
              await limiter.acquireToken(cancelToken: requestCancelToken);

              final resp = await dio.get<ResponseBody>(
                url,
                options: Options(
                  responseType: ResponseType.stream,
                  headers: reqHeaders,
                  validateStatus: (s) => s != null && s >= 200 && s < 400,
                ),
                cancelToken: requestCancelToken,
              );

              limiter.reportSuccess();

              final stream = resp.data?.stream;
              if (stream == null) {
                throw Exception('Empty response stream');
              }

              final stallTimeout = currentProxy != null
                  ? const Duration(seconds: 6)
                  : const Duration(seconds: 15);

              await for (final chunk in stream.timeout(stallTimeout)) {
                if (cancelToken.isCancelled) break;

                // Ensure chunk doesn't overshoot worker.endByte if the segment was split
                final remainingInSegment = worker.endByte - worker.currentOffset + 1;
                if (remainingInSegment <= 0) break;

                final toWrite = chunk.length > remainingInSegment
                    ? chunk.sublist(0, remainingInSegment)
                    : chunk;

                final offset = worker.currentOffset;
                await writeChunk(offset, toWrite);

                worker.downloadedBytes += toWrite.length;
                totalDownloaded += toWrite.length;
                bytesInSession += toWrite.length;

                // Slowness check for proxy workers in Rocket mode:
                // Only evaluate after warmup (>= 6.0s elapsed and at least 128KB transferred)
                // AND ONLY rotate if there is an alternative healthy proxy in the pool!
                if (currentProxy != null && speedLimitMode == SpeedLimitMode.rocket) {
                  final elapsedSec = sessionWatch.elapsedMilliseconds / 1000.0;
                  if (elapsedSec >= 6.0 && bytesInSession >= 128 * 1024) {
                    final proxySpeed = bytesInSession / elapsedSec;
                    // If proxy speed is extremely slow (< 30 KB/s) and an alternative proxy is available
                    if (proxySpeed < 30 * 1024 && proxyPool.hasAlternativeProxy(currentProxy)) {
                      failureReason = 'Speed too slow (${AppUtils.formatSpeed(proxySpeed)})';
                      shouldRotateProxy = true;
                      requestCancelToken.cancel(failureReason);
                      break;
                    }
                  }
                }

                // Speed Limiter throttle check
                if (maxSpeed > 0 && currentSpeed > maxSpeed) {
                  final overRatio = (currentSpeed - maxSpeed) / maxSpeed;
                  final pauseMs = (overRatio * 50).clamp(10, 100).toInt();
                  await Future.delayed(Duration(milliseconds: pauseMs));
                }

                // Throttle UI update every ~350ms
                final now = DateTime.now();
                final elapsed = now.difference(lastSampleTime).inMilliseconds;
                if (elapsed >= 350) {
                  final delta = totalDownloaded - lastSampleBytes;
                  currentSpeed = (delta / elapsed) * 1000.0;
                  lastSampleBytes = totalDownloaded;
                  lastSampleTime = now;

                  onProgress(
                    downloadedBytes: totalDownloaded,
                    totalBytes: totalBytes,
                    speedBytesPerSec: currentSpeed,
                  );
                }

                // If segment has reached completion (e.g. up to splitPoint), break stream
                if (worker.isFinished) {
                  break;
                }
              }

              directRetries = 0;
            } catch (e) {
              if (cancelToken.isCancelled) break;
              if (e is DioException && e.response?.statusCode == 429) {
                final cooldown = limiter.reportRateLimit(e.response?.headers.map);
                onStatusMessage?.call(
                  'Worker ${slot + 1}: Rate limited (429). Cooldown ${cooldown.inSeconds}s...',
                );
              }
              shouldRotateProxy = true;
              failureReason = e is TimeoutException
                  ? 'Proxy stalled (no data for 6s)'
                  : (failureReason ?? e.toString());
            }

            if (cancelToken.isCancelled) break;

            if (shouldRotateProxy && currentProxy != null) {
              proxyPool.markSlowOrDead(currentProxy, reason: failureReason);
              final oldProxyUrl = currentProxy.displayUrl;
              final nextProxy = proxyPool.acquireNext() ?? proxyPool.getBestActiveProxy();
              currentProxy = nextProxy;

              if (nextProxy != null) {
                onStatusMessage?.call(
                  'Worker ${slot + 1}: Proxy $oldProxyUrl slow/died ($failureReason). Rotating to ${nextProxy.displayUrl}...',
                );
              } else {
                onStatusMessage?.call(
                  'Worker ${slot + 1}: Proxy pool exhausted. Resuming remainder with direct connection...',
                );
              }
              await Future.delayed(const Duration(milliseconds: 100));
            } else if (shouldRotateProxy && currentProxy == null) {
              // Direct connection had an issue
              directRetries++;
              if (directRetries > 6) {
                throw Exception('Direct worker connection failed after multiple retries: $failureReason');
              }
              await Future.delayed(Duration(milliseconds: 400 * directRetries));
            }
          }

          // Worker finished this segment
          activeSegments.remove(worker);
          // Persist progress to meta file
          await _saveMeta(metaFile, workerList);
        }
      }());
    }

    try {
      await Future.wait(workerFutures);
    } finally {
      await raf.flush();
      await raf.close();
      await _saveMeta(metaFile, workerList);
    }

    // 6. Post-Download Cleanup & Storage Finalization
    if (totalDownloaded >= totalBytes && !cancelToken.isCancelled) {
      // Failsafe removal of metadata file
      await fileService.deleteFile(metaFile.path);

      // If downloaded to temp, move to final designated folder
      if (activeFilePath != savePath) {
        onStatusMessage?.call('Moving file to destination...');
        final moved = await fileService.moveFile(activeFilePath, savePath);
        if (!moved) {
          throw FileSystemException('Failed to move completed file to destination', savePath);
        }
      }

      onProgress(
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        speedBytesPerSec: 0.0,
      );
    }
  }

  Future<void> _saveMeta(File metaFile, List<SegmentWorkerState> workers) async {
    try {
      final jsonStr = jsonEncode(workers.map((w) => w.toJson()).toList());
      await metaFile.writeAsString(jsonStr, flush: true);
    } catch (_) {}
  }

  /// Checks whether a restored segment list is contiguous, non-overlapping,
  /// covers the full [totalBytes], and contains valid downloaded byte counts.
  bool _isValidSegmentList(List<SegmentWorkerState> segments, int totalBytes) {
    if (segments.isEmpty || totalBytes <= 0) return false;
    final sorted = List<SegmentWorkerState>.from(segments)
      ..sort((a, b) => a.startByte.compareTo(b.startByte));
    if (sorted.first.startByte != 0) return false;
    if (sorted.last.endByte != totalBytes - 1) return false;

    for (int i = 0; i < sorted.length; i++) {
      final seg = sorted[i];
      if (seg.startByte > seg.endByte) return false;
      if (seg.downloadedBytes < 0 || seg.downloadedBytes > seg.totalSegmentBytes) {
        return false;
      }
      if (i < sorted.length - 1) {
        if (seg.endByte + 1 != sorted[i + 1].startByte) {
          return false;
        }
      }
    }
    return true;
  }

  /// Acquires an idle segment or dynamically splits the largest remaining active segment.
  /// This eliminates the straggler problem in Rocket mode and ensures all workers stay busy.
  SegmentWorkerState? _acquireNextWork(
    List<SegmentWorkerState> allWorkers,
    Set<SegmentWorkerState> activeSegments, {
    ProxyConfig? preferredProxy,
    int minSplitSize = 2 * 1024 * 1024, // 2MB
  }) {
    // 1. Check if there is an existing unfinished segment that is NOT currently active
    for (final w in allWorkers) {
      if (!w.isFinished && !activeSegments.contains(w)) {
        activeSegments.add(w);
        return w;
      }
    }

    // 2. Find the active segment with the largest remaining un-downloaded bytes
    SegmentWorkerState? victim;
    int maxRemaining = 0;

    for (final w in activeSegments) {
      if (w.isFinished) continue;
      final remaining = w.endByte - w.currentOffset + 1;
      if (remaining > maxRemaining) {
        maxRemaining = remaining;
        victim = w;
      }
    }

    if (victim == null || maxRemaining < minSplitSize) {
      return null;
    }

    // 3. Split remaining range in half:
    // Victim keeps the lower half [victim.currentOffset .. splitPoint]
    // The thief takes the upper half [splitPoint + 1 .. oldEnd]
    final half = (maxRemaining / 2).floor();
    final oldEnd = victim.endByte;
    final splitPoint = oldEnd - half;

    victim.endByte = splitPoint;

    final stolen = SegmentWorkerState(
      index: allWorkers.length,
      startByte: splitPoint + 1,
      endByte: oldEnd,
      downloadedBytes: 0,
      proxy: preferredProxy,
    );

    allWorkers.add(stolen);
    activeSegments.add(stolen);
    return stolen;
  }
}

