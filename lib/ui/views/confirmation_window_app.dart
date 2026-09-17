import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';

class ConfirmationWindowApp extends StatefulWidget {
  final String url;
  final String fileName;
  final String? category;
  final String? token;
  final Map<String, String>? headers;
  final int port;

  const ConfirmationWindowApp({
    super.key,
    required this.url,
    required this.fileName,
    this.category,
    this.token,
    this.headers,
    this.port = AppConstants.defaultServerPort,
  });

  @override
  State<ConfirmationWindowApp> createState() => _ConfirmationWindowAppState();
}

class _ConfirmationWindowAppState extends State<ConfirmationWindowApp> {
  bool _isSending = false;

  Future<void> _handleConfirm() async {
    setState(() => _isSending = true);
    final client = HttpClient();
    try {
      final request = await client.post('127.0.0.1', widget.port, '/add').timeout(const Duration(seconds: 4));
      request.headers.contentType = ContentType.json;
      if (widget.token != null && widget.token!.isNotEmpty) {
        request.headers.set(AppConstants.extensionTokenHeader, widget.token!);
      }

      final payload = {
        'url': widget.url,
        'fileName': widget.fileName,
        'category': widget.category ?? 'other',
        'headers': widget.headers,
        'force': true,
      };

      request.write(jsonEncode(payload));
      final response = await request.close();
      await response.drain();
    } catch (e) {
      debugPrint('Error confirming download: $e');
    } finally {
      client.close();
      exit(0);
    }
  }

  void _handleCancel() {
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final isSuspicious = AppUtils.isSuspiciousFormat(widget.fileName);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Builder(
              builder: (ctx) {
                final theme = Theme.of(ctx);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Question & Question Icon
                    Row(
                      children: [
                        Icon(
                          isSuspicious ? Icons.shield_outlined : Icons.download_outlined,
                          size: 20,
                          color: isSuspicious ? theme.colorScheme.error : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Do you want to download this file?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    // File Name container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: widget.fileName,
                            child: Text(
                              widget.fileName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSuspicious) ...[
                            const SizedBox(height: 4),
                            Text(
                              '[Security Note: Executable file - monitored by Antivirus]',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Action buttons (Yes / No)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _isSending ? null : _handleCancel,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('No'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _isSending ? null : _handleConfirm,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Yes'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
