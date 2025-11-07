import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/dio_provider.dart';

class Playlist {
  final int id;
  final String name;
  final String? description;
  final bool isPublic;
  const Playlist({required this.id, required this.name, this.description, required this.isPublic});
}

abstract class IPlaylistRepository {
  Future<List<Playlist>> fetchMine();
  Future<Playlist> create(String name, {String? description, bool isPublic});
  Future<void> addTrack(int playlistId, int trackId);
  Future<void> removeTrack(int playlistId, int trackId);
  Future<Playlist> update(int id, {String? name, String? description, bool? isPublic});
  Future<void> delete(int id);
  Future<List<Playlist>> refresh();
}

class PlaylistDetail extends Playlist {
  final int trackCount;
  const PlaylistDetail({required super.id, required super.name, super.description, required super.isPublic, required this.trackCount});
}

class PlaylistTrackEntry {
  final int trackId;
  final int position;
  final String? title;
  final int? artistId;
  final String? artistName;
  final int? durationMs;
  final String? coverUrl;
  final String? previewUrl;
  const PlaylistTrackEntry({
    required this.trackId,
    required this.position,
    this.title,
    this.artistId,
    this.artistName,
    this.durationMs,
    this.coverUrl,
    this.previewUrl,
  });
}

class PlaylistRepository implements IPlaylistRepository {
  final Dio _dio;
  final String baseUrl;
  PlaylistRepository(this._dio, this.baseUrl);

  @override
  Future<List<Playlist>> fetchMine() async {
    try {
      final res = await _dio.get('$baseUrl/playlists/');
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .map((e) => Playlist(
                  id: e['id'],
                  name: e['name'] ?? 'Untitled',
                  description: e['description'],
                  isPublic: e['is_public'] ?? true,
                ))
            .toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Playlist> create(String name, {String? description, bool isPublic = true}) async {
  final res = await _dio.post('$baseUrl/playlists/', data: {
      'name': name,
      'description': description,
      'is_public': isPublic,
    });
    if (res.statusCode == 200 || res.statusCode == 201) {
      final e = res.data;
      return Playlist(id: e['id'], name: e['name'], description: e['description'], isPublic: e['is_public']);
    }
    throw Exception('Create playlist failed');
  }

  Future<Playlist> update(int id, {String? name, String? description, bool? isPublic}) async {
    final res = await _dio.patch('$baseUrl/playlists/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (isPublic != null) 'is_public': isPublic,
    });
    if (res.statusCode == 200 && res.data != null) {
      final e = res.data;
      return Playlist(id: e['id'], name: e['name'], description: e['description'], isPublic: e['is_public']);
    }
    throw Exception('Update playlist failed');
  }

  Future<void> delete(int id) async {
    await _dio.delete('$baseUrl/playlists/$id');
  }

  @override
  Future<void> addTrack(int playlistId, int trackId) async {
  await _dio.post('$baseUrl/playlists/$playlistId/tracks', data: {'track_id': trackId});  // backend route no trailing slash needed
  }

  @override
  Future<void> removeTrack(int playlistId, int trackId) async {
  await _dio.delete('$baseUrl/playlists/$playlistId/tracks/$trackId');
  }

  @override
  Future<List<Playlist>> refresh() => fetchMine();

  // New detail endpoint
  Future<PlaylistDetail> fetchDetail(int id) async {
    final res = await _dio.get('$baseUrl/playlists/$id');
    if (res.statusCode == 200) {
      final e = res.data;
      return PlaylistDetail(
        id: e['id'],
        name: e['name'] ?? 'Untitled',
        description: e['description'],
        isPublic: e['is_public'] ?? true,
        trackCount: e['track_count'] ?? 0,
      );
    }
    throw Exception('Playlist not found');
  }

  Future<List<PlaylistTrackEntry>> fetchTracks(int id) async {
    final res = await _dio.get('$baseUrl/playlists/$id/tracks');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List)
          .map((e) => PlaylistTrackEntry(
                trackId: e['track_id'],
                position: e['position'],
                title: e['title'],
                artistId: e['artist_id'],
                artistName: e['artist_name'],
                durationMs: e['duration_ms'],
                coverUrl: e['cover_url'],
                previewUrl: e['preview_url'],
              ))
          .toList();
    }
    return [];
  }

  Future<void> reorderTracks(int playlistId, List<int> orderedTrackIds) async {
    await _dio.patch('$baseUrl/playlists/$playlistId/reorder', data: {
      'ordered_track_ids': orderedTrackIds,
    });
  }

  Future<Set<int>> fetchMemberships(int trackId) async {
    final res = await _dio.get('$baseUrl/playlists/track-memberships/$trackId');
    if (res.statusCode == 200 && res.data is List) {
      return (res.data as List).map((e) => e as int).toSet();
    }
    return <int>{};
  }
}

final playlistRepositoryProvider = Provider<IPlaylistRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final cfg = ref.watch(appConfigProvider);
  return PlaylistRepository(dio, cfg.apiBaseUrl);
});
