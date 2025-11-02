import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/track_error_logger.dart';

/// Screen to display all tracks that failed with 403 errors
class TrackErrorLogScreen extends ConsumerStatefulWidget {
  const TrackErrorLogScreen({super.key});

  @override
  ConsumerState<TrackErrorLogScreen> createState() =>
      _TrackErrorLogScreenState();
}

class _TrackErrorLogScreenState extends ConsumerState<TrackErrorLogScreen> {
  List<Map<String, String>> _errors = [];
  bool _loading = true;
  String? _logFilePath;

  @override
  void initState() {
    super.initState();
    _loadErrors();
    // Print file path to console
    TrackErrorLogger.printLogFilePath();
  }

  Future<void> _loadErrors() async {
    setState(() => _loading = true);
    try {
      final errors = await TrackErrorLogger.getAllErrors();
      final path = await TrackErrorLogger.getLogFilePath();
      setState(() {
        _errors = errors;
        _logFilePath = path;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa logs?'),
        content: const Text('Bạn có chắc muốn xóa tất cả error logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TrackErrorLogger.clearLogs();
      _loadErrors();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa tất cả error logs')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Errors (403)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadErrors,
            tooltip: 'Tải lại',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _errors.isEmpty ? null : _clearLogs,
            tooltip: 'Xóa logs',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info card
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Tổng số tracks bị lỗi: ${_errors.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      if (_logFilePath != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'File CSV: $_logFilePath',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // List of errors
                Expanded(
                  child: _errors.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 64, color: Colors.green),
                              SizedBox(height: 16),
                              Text('Không có track nào bị lỗi 403'),
                              SizedBox(height: 8),
                              Text(
                                'Các track bị lỗi sẽ được ghi lại tự động',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _errors.length,
                          itemBuilder: (ctx, i) {
                            final error = _errors[i];
                            final timestamp = error['timestamp'] ?? '';
                            final trackId = error['track_id'] ?? '';
                            final title = error['title'] ?? 'Unknown';
                            final artist = error['artist'] ?? 'Unknown';
                            final previewUrl = error['preview_url'] ?? '';
                            final errorDetails = error['error_details'] ?? '';

                            // Parse timestamp
                            String displayTime = timestamp;
                            try {
                              final dt = DateTime.parse(timestamp);
                              displayTime =
                                  '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                            } catch (_) {}

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.red.shade100,
                                  child: Icon(Icons.error_outline,
                                      color: Colors.red.shade700),
                                ),
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(artist,
                                        style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ID: $trackId • $displayTime',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    if (errorDetails.isNotEmpty)
                                      Text(
                                        errorDetails,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: previewUrl.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.link,
                                            color: Colors.blue),
                                        tooltip: 'Copy URL',
                                        onPressed: () {
                                          // Could implement clipboard copy here
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'URL: ${previewUrl.length > 50 ? previewUrl.substring(0, 50) + '...' : previewUrl}')),
                                          );
                                        },
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
