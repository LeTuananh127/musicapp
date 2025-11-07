import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:io' show Platform;
import '../models/track.dart';
import '../../shared/providers/dio_provider.dart';

abstract class ITrackRepository {
  Future<List<Track>> fetchAll({int? limit, int? offset, String order});
  Future<Track?> getById(int id);
  Future<void> view(int id);
}

class TrackRepository implements ITrackRepository {
  final Dio _dio;
  final String baseUrl;
  TrackRepository(this._dio, this.baseUrl);

  @override
  Future<List<Track>> fetchAll({int? limit, int? offset, String order = 'desc'}) async {
  // Use trailing slash to avoid 307 redirect from FastAPI for the mounted prefix
  final params = <String, dynamic>{
    if (limit != null) 'limit': limit,
    if (offset != null) 'offset': offset,
    'order': order,
  };
  final response = await _dio.get('$baseUrl/tracks/', queryParameters: params);
    if (response.statusCode == 200) {
      final base = baseUrl;
      final raw = response.data is List ? response.data as List : (response.data is Map ? (response.data['value'] ?? []) as List : []);
      final list = raw
          .map((e) {
            final rawPreview = e['preview_url'];
            String? preview;
            if (rawPreview == null) {
              preview = null;
            } else {
              final rp = rawPreview.toString();
              if (rp.startsWith('http')) {
                // If the URL is a Deezer CDN preview (dzcdn), route through backend proxy to avoid CDN restrictions
                if (rp.contains('cdnt-preview.dzcdn.net') || rp.contains('cdns-preview.dzcdn.net') || rp.contains('dzcdn.net')) {
                  // Use backend proxy endpoint /deezer/stream/{id}
                  preview = '$base/deezer/stream/${e['id']}';
                } else {
                  preview = rp;
                }
              } else {
                preview = base + rp;
              }
            }
            final rawCover = e['cover_url'];
            final cover = rawCover == null
                ? null
                : (rawCover.toString().startsWith('http')
                    ? rawCover
                    : (base + rawCover.toString()));
            return Track(
              id: (e['id']).toString(),
              title: e['title'] ?? 'Unknown',
              artistName: e['artist_name'] ?? e['artistName'] ?? (e['artist']?['name'] ?? 'Unknown'),
              durationMs: (e['duration_ms'] ?? (e['duration'] ?? 0) * 1000) as int,
              previewUrl: preview,
              coverUrl: cover,
              views: (e['views'] as num?)?.toInt(),
            );
          })
          .toList();
      return limit != null ? list.take(limit).toList() : list;
    }
    return [];
  }

  @override
  Future<Track?> getById(int id) async {
    try {
  final resp = await _dio.get('$baseUrl/tracks/$id');
      if (resp.statusCode == 200 && resp.data != null) {
        final e = resp.data;
        final base = baseUrl;
        final rawPreview = e['preview_url'];
        String? preview;
        if (rawPreview == null) {
          preview = null;
        } else {
          final rp = rawPreview.toString();
          if (rp.startsWith('http')) {
            if (rp.contains('cdnt-preview.dzcdn.net') || rp.contains('cdns-preview.dzcdn.net') || rp.contains('dzcdn.net')) {
              preview = '$base/deezer/stream/${e['id']}';
            } else {
              preview = rp;
            }
          } else {
            preview = base + rp;
          }
        }
        final rawCover = e['cover_url'];
        final cover = rawCover == null
            ? null
            : (rawCover.toString().startsWith('http')
                ? rawCover
                : (base + rawCover.toString()));
        return Track(
          id: (e['id']).toString(),
          title: e['title'] ?? 'Unknown',
          artistName: e['artist_name'] ?? e['artistName'] ?? (e['artist']?['name'] ?? 'Unknown'),
          durationMs: (e['duration_ms'] ?? (e['duration'] ?? 0) * 1000) as int,
          previewUrl: preview,
          coverUrl: cover,
          views: (e['views'] as num?)?.toInt(),
        );
      }
    } catch (_) {}
    return Track(id: id.toString(), title: 'Track $id', artistName: 'N/A', durationMs: 0, previewUrl: null);
  }

  @override
  Future<void> view(int id) async {
    try {
      await _dio.post('$baseUrl/tracks/$id/view');
    } catch (_) {
      // ignore errors – viewing is best-effort
    }
  }

  /// Upload a track file (audio) with optional cover image.
  /// Returns created Track or null on failure.
  Future<Track?> uploadTrack({
    required String title,
    int? artistId,
    required String audioPath,
    String? coverPath,
    int durationMs = 0,
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      final map = <String, dynamic>{
        'title': title,
        'duration_ms': durationMs,
        'audio': await MultipartFile.fromFile(audioPath, filename: audioPath.split(Platform.pathSeparator).last),
      };
      if (coverPath != null) {
        map['cover'] = await MultipartFile.fromFile(coverPath, filename: coverPath.split(Platform.pathSeparator).last);
      }
      // only include artist_id when provided (leave out to let backend create an artist owned by uploader)
      if (artistId != null && artistId > 0) {
        map['artist_id'] = artistId;
      }
      final form = FormData.fromMap(map);
      final resp = await _dio.post('$baseUrl/tracks/upload', data: form, onSendProgress: onSendProgress, options: Options(headers: {}));
      if (resp.statusCode == 200 && resp.data != null) {
        final e = resp.data as Map<String, dynamic>;
        final base = baseUrl;
        final rawPreview = e['preview_url'];
        String? preview;
        if (rawPreview == null) preview = null; else preview = rawPreview.toString().startsWith('http') ? rawPreview : base + rawPreview.toString();
        final rawCover = e['cover_url'];
        final cover = rawCover == null ? null : (rawCover.toString().startsWith('http') ? rawCover : base + rawCover.toString());
        return Track(
          id: (e['id']).toString(),
          title: e['title'] ?? title,
          artistName: e['artist_name'] ?? 'Unknown',
          durationMs: (e['duration_ms'] ?? durationMs) as int,
          previewUrl: preview,
          coverUrl: cover,
          views: (e['views'] as num?)?.toInt(),
        );
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// Create a track using external audio and cover URLs (no file upload)
  Future<Track?> createTrackWithUrls({
    required String title,
    int? artistId,
    int durationMs = 0,
    String? audioUrl,
    String? coverUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'title': title,
        'duration_ms': durationMs,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (coverUrl != null) 'cover_url': coverUrl,
      };
      if (artistId != null && artistId > 0) body['artist_id'] = artistId;
      final resp = await _dio.post('$baseUrl/tracks/create', data: body);
      if (resp.statusCode == 200 && resp.data != null) {
        final e = resp.data as Map<String, dynamic>;
        final base = baseUrl;
        final rawPreview = e['preview_url'];
        String? preview;
        if (rawPreview == null) preview = null; else preview = rawPreview.toString().startsWith('http') ? rawPreview : base + rawPreview.toString();
        final rawCover = e['cover_url'];
        final cover = rawCover == null ? null : (rawCover.toString().startsWith('http') ? rawCover : base + rawCover.toString());
        return Track(
          id: (e['id']).toString(),
          title: e['title'] ?? title,
          artistName: e['artist_name'] ?? 'Unknown',
          durationMs: (e['duration_ms'] ?? durationMs) as int,
          previewUrl: preview,
          coverUrl: cover,
          views: (e['views'] as num?)?.toInt(),
        );
      }
    } catch (_) {}
    return null;
  }
}

final trackRepositoryProvider = Provider<ITrackRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final cfg = ref.watch(appConfigProvider);
  return TrackRepository(dio, cfg.apiBaseUrl);
});
