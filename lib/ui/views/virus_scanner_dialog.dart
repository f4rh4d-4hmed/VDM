import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../domain/models/download_task.dart';
import '../../domain/models/virus_scan_result.dart';
import '../view_models/downloads_view_model.dart';
import '../view_models/settings_view_model.dart';

class VirusScannerDialog extends StatefulWidget {
  final DownloadTask task;

  const VirusScannerDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, DownloadTask task) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => VirusScannerDialog(task: task),
    );
  }

  @override
  State<VirusScannerDialog> createState() => _VirusScannerDialogState();
}

class _VirusScannerDialogState extends State<VirusScannerDialog> {
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _inlineApiKey;
  final TextEditingController _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScan();
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _initScan({bool forceManual = false}) async {
    final downloadsVm = context.read<DownloadsViewModel>();
    final cached = downloadsVm.getVirusScanResult(widget.task.id);

    // If cached and not forcing manual, display existing result
    if (cached != null && !forceManual && !cached.isError) {
      return;
    }

    setState(() => _isLoading = true);
    await downloadsVm.scanTaskWithVirusScanner(
      widget.task.id,
      forceManualScan: forceManual,
      customApiKey: _inlineApiKey,
    );
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSaveKeyAndScan() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;

    final settingsVm = context.read<SettingsViewModel>();
    final downloadsVm = context.read<DownloadsViewModel>();
    await settingsVm.updateVirusTotalApiKey(key);
    if (!mounted) return;
    setState(() {
      _inlineApiKey = key;
      _isLoading = true;
    });

    await downloadsVm.scanTaskWithVirusScanner(
      widget.task.id,
      customApiKey: key,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpload() async {
    final downloadsVm = context.read<DownloadsViewModel>();
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    await downloadsVm.uploadTaskToVirusTotal(
      widget.task.id,
      customApiKey: _inlineApiKey,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );

    if (mounted) {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadsVm = context.watch<DownloadsViewModel>();
    final settingsVm = context.watch<SettingsViewModel>();
    final result = downloadsVm.getVirusScanResult(widget.task.id);
    final hasApiKey = settingsVm.settings.virusTotalApiKey.isNotEmpty || (_inlineApiKey != null && _inlineApiKey!.isNotEmpty);
    final isOver5GB = widget.task.totalBytes > AppConstants.maxAutoScanFileSizeBytes;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _getHeaderIcon(result),
            color: _getHeaderColor(theme, result),
            size: 24,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Virus Scanner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File Info
              Text(
                widget.task.fileName,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Size: ${widget.task.formattedTotalSize}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 20),

              // 1. Desktop Antivirus Handover Section (Desktop Only)
              if (AppUtils.isDesktop) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        result?.desktopAntivirusHandedOver == true
                            ? Icons.verified_user_rounded
                            : Icons.shield_outlined,
                        color: result?.desktopAntivirusHandedOver == true ? Colors.green : Colors.blueGrey,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Desktop Antivirus Handover',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              result?.desktopAntivirusDetails ??
                                  'Handed over to native OS security protection during download.',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 2. Large File (>5GB) Notice
              if (result?.isSkippedTooLarge == true || (isOver5GB && result == null)) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'File exceeds 5 GB. Automatic scan skipped. Manual scan is available below.',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Loading indicator
              if (_isLoading) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(height: 10),
                        Text('Scanning with VirusTotal & Antivirus...', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ] else if (_isUploading) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
                        const SizedBox(height: 10),
                        Text('Uploading to VirusTotal (${(_uploadProgress * 100).toStringAsFixed(0)}%)...',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ] else if (!hasApiKey) ...[
                // Prompt for API key
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VirusTotal API Key Required',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Get a free API key at virustotal.com to enable cross-platform threat analysis.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyController,
                        decoration: const InputDecoration(
                          hintText: 'Paste VirusTotal API key',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: _handleSaveKeyAndScan,
                          child: const Text('Save & Scan', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (result != null) ...[
                // VirusTotal Scan Result
                _buildResultContent(context, result),
              ] else ...[
                Center(
                  child: FilledButton.icon(
                    onPressed: () => _initScan(forceManual: true),
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Scan File Now'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (result?.isSkippedTooLarge == true || isOver5GB)
          TextButton(
            onPressed: _isLoading ? null : () => _initScan(forceManual: true),
            child: const Text('Manual Scan'),
          ),
        if (hasApiKey && !_isLoading && !_isUploading)
          TextButton(
            onPressed: () => _initScan(forceManual: true),
            child: const Text('Re-scan'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildResultContent(BuildContext context, VirusScanResult result) {
    final theme = Theme.of(context);

    if (result.isClean) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Clean (${result.maliciousCount}/${result.totalEngines} engines flagged)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'No security vendors flagged this file as malicious.',
              style: TextStyle(fontSize: 12),
            ),
            if (result.permalink != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(result.permalink!)),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('View VirusTotal Report', style: TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
      );
    }

    if (result.isMalicious || result.isSuspicious) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${result.maliciousCount} Security Vendor(s) Flagged File',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (result.detectedThreats.isNotEmpty) ...[
              const Text('Detections:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
              const SizedBox(height: 4),
              ...result.detectedThreats.entries.take(4).map((e) => Text(
                    '• ${e.key}: ${e.value}',
                    style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                  )),
            ],
            if (result.permalink != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => launchUrl(Uri.parse(result.permalink!)),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('View Full Threat Report', style: TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
      );
    }

    if (result.isNotFound) {
      final canUpload = (result.fileSizeBytes ?? 0) <= 32 * 1024 * 1024;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.help_outline_rounded, color: Colors.blueGrey, size: 18),
                SizedBox(width: 6),
                Text('Hash Not Seen on VirusTotal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'No previous scan exists on VirusTotal for this SHA-256 hash.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (canUpload) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _handleUpload,
                icon: const Icon(Icons.cloud_upload_outlined, size: 14),
                label: const Text('Upload & Scan (≤ 32 MB)', style: TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
      );
    }

    if (result.isError) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.errorMessage ?? 'Error scanning file.',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  IconData _getHeaderIcon(VirusScanResult? result) {
    if (result == null) return Icons.security_rounded;
    if (result.isClean) return Icons.check_circle_rounded;
    if (result.isMalicious) return Icons.gpp_bad_rounded;
    if (result.isSuspicious || result.isSkippedTooLarge) return Icons.gpp_maybe_rounded;
    return Icons.security_rounded;
  }

  Color _getHeaderColor(ThemeData theme, VirusScanResult? result) {
    if (result == null) return theme.colorScheme.primary;
    if (result.isClean) return Colors.green;
    if (result.isMalicious) return Colors.red;
    if (result.isSuspicious || result.isSkippedTooLarge) return Colors.amber;
    return theme.colorScheme.primary;
  }
}
