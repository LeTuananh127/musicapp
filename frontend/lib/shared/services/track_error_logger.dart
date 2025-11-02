import 'dart:io';
import '../../../data/models/track.dart';

/// Service for logging tracks that fail with 403 errors to a CSV file
class TrackErrorLogger {
  static const String _filename = 'track_errors_403.csv';

  // Save CSV in project's services folder instead of Documents
  static String get _csvPath {
    // Get the path to this Dart file
    final scriptPath = Platform.script.toFilePath();
    // Navigate to lib/shared/services folder
    final servicesDir = File(scriptPath).parent.path;
    return '$servicesDir/$_filename';
  }

  /// Log a track that failed with 403 error
  static Future<void> log403Error(Track track, {String? errorDetails}) async {
    try {
      print(
          '🔴 [TrackErrorLogger] Starting to log 403 error for track: ${track.id} - ${track.title}');

      final file = File(_csvPath);
      print('📄 [TrackErrorLogger] CSV file path: ${file.path}');

      // Check if file exists to determine if we need to write header
      final exists = await file.exists();
      print('✓ [TrackErrorLogger] File exists: $exists');

      // Prepare CSV row
      final timestamp = DateTime.now().toIso8601String();
      final id = track.id;
      final title = _escapeCsv(track.title);
      final artist = _escapeCsv(track.artistName);
      final previewUrl = _escapeCsv(track.previewUrl ?? '');
      final coverUrl = _escapeCsv(track.coverUrl ?? '');
      final details = _escapeCsv(errorDetails ?? '403 Forbidden');

      final row =
          '$timestamp,$id,"$title","$artist","$previewUrl","$coverUrl","$details"\n';

      // Write to file
      if (!exists) {
        // Write header first
        const header =
            'timestamp,track_id,title,artist,preview_url,cover_url,error_details\n';
        await file.writeAsString(header, mode: FileMode.write);
        print('📝 [TrackErrorLogger] Wrote CSV header');
      }

      await file.writeAsString(row, mode: FileMode.append);
      print(
          '✅ [TrackErrorLogger] Successfully logged 403 error for track: ${track.title} (${track.id}) to $_filename');
      print('   File location: ${file.path}');
    } catch (e, stackTrace) {
      print('❌ [TrackErrorLogger] Failed to log 403 error: $e');
      print('   Stack trace: $stackTrace');
    }
  }

  /// Escape CSV special characters
  static String _escapeCsv(String value) {
    // Replace double quotes with double-double quotes
    return value.replaceAll('"', '""');
  }

  /// Get the path to the error log file
  static Future<String> getLogFilePath() async {
    try {
      final path = _csvPath;
      print('📂 [TrackErrorLogger] CSV file location: $path');
      return path;
    } catch (e) {
      print('❌ [TrackErrorLogger] Failed to get log file path: $e');
      return 'Error: $e';
    }
  }

  /// Print the log file path to console (for debugging)
  static Future<void> printLogFilePath() async {
    final path = await getLogFilePath();
    print('');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📁 Track 403 Error Log File Location:');
    print('   $path');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('');

    // Check if file exists
    try {
      final file = File(path);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        print('✅ File exists with ${lines.length} lines (including header)');
        if (lines.length > 1) {
          print('   Total errors logged: ${lines.length - 1}');
        }
      } else {
        print('ℹ️  File does not exist yet (no errors logged)');
      }
    } catch (e) {
      print('⚠️  Could not read file: $e');
    }
  }

  /// Clear all error logs
  static Future<void> clearLogs() async {
    try {
      final file = File(_csvPath);

      if (await file.exists()) {
        await file.delete();
        print('🗑️ Cleared error logs');
      }
    } catch (e) {
      print('❌ Failed to clear logs: $e');
    }
  }

  /// Get all logged errors as a list of maps
  static Future<List<Map<String, String>>> getAllErrors() async {
    try {
      final file = File(_csvPath);

      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      final lines = content.split('\n');

      if (lines.isEmpty || lines.length == 1) {
        return [];
      }

      final errors = <Map<String, String>>[];

      // Skip header (first line) and empty lines
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = _parseCsvLine(line);
        if (parts.length >= 7) {
          errors.add({
            'timestamp': parts[0],
            'track_id': parts[1],
            'title': parts[2],
            'artist': parts[3],
            'preview_url': parts[4],
            'cover_url': parts[5],
            'error_details': parts[6],
          });
        }
      }

      return errors;
    } catch (e) {
      print('❌ Failed to read error logs: $e');
      return [];
    }
  }

  /// Simple CSV line parser
  static List<String> _parseCsvLine(String line) {
    final parts = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Double quote escape
          buffer.write('"');
          i++; // Skip next quote
        } else {
          // Toggle quote mode
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // End of field
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    // Add last field
    if (buffer.isNotEmpty || line.endsWith(',')) {
      parts.add(buffer.toString());
    }

    return parts;
  }
}
