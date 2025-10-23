import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math';
import '../../../shared/providers/dio_provider.dart';
import '../../auth/application/auth_providers.dart';
import 'package:dio/dio.dart';
import '../application/recommend_controller.dart';
import '../../../data/repositories/playlist_repository.dart';
import '../../playlist/application/playlist_providers.dart';
import '../../../data/models/track.dart';

class RecommendScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>>? playlists;
  const RecommendScreen({super.key, this.playlists});

  @override
  ConsumerState<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends ConsumerState<RecommendScreen> {
  bool _loadingRemote = false;
  String? _error;
  List<int>? _artistIds;
  bool _loadingArtistTracks = false;
  List<Map<String, dynamic>> _artistTracks = [];
  Future<void>? _artistTracksFuture;

  @override
  void initState() {
    super.initState();
    _ensurePlaylistsIfNeeded();
    _ensureArtistIds();
    _loadArtistTracksIfNeeded();
  }

  Future<void> _loadArtistTracksIfNeeded() async {
    // ensure we have artist ids first
    await _ensureArtistIds();
    if (_artistIds == null || _artistIds!.isEmpty) return;
    // ensure we only kick off the tracks fetch once
    _artistTracksFuture ??= _fetchArtistTracks();
    if (mounted) setState(() {});
  }

  Future<void> _ensurePlaylistsIfNeeded() async {
    final onboarding = ref.read(onboardingPlaylistsProvider);
    if (widget.playlists != null || onboarding != null) return;
    // try to fetch user's preferred artists and call recommend endpoint
    setState(() { _loadingRemote = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/users/me/preferences/artists', options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List ids = res.data is List ? res.data : res.data['value'] ?? [];
      if (ids.isEmpty) {
        setState(() { _loadingRemote = false; });
        return;
      }
      // store artist ids for later 'all tracks' fetch
      try {
        _artistIds = ids.map((e) => e as int).toList();
      } catch (_) {
        _artistIds = List<int>.from(ids);
      }
      final artistParam = _artistIds!.join(',');
      final r2 = await dio.get('$base/recommend/playlists', queryParameters: {'artists': artistParam}, options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List data = r2.data is Map ? r2.data['value'] ?? r2.data : r2.data;
      final playlists = data.map((e) => {'id': e['id'], 'name': e['name'], 'score': e['score']}).toList();
      ref.read(onboardingPlaylistsProvider.notifier).state = playlists;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() { _loadingRemote = false; });
  }

  Future<void> _ensureArtistIds() async {
    if (_artistIds != null) return;
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/users/me/preferences/artists', options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List ids = res.data is List ? res.data : res.data['value'] ?? [];
      try {
        _artistIds = ids.map((e) => e as int).toList();
      } catch (_) {
        _artistIds = List<int>.from(ids);
      }
    } catch (_) {
      _artistIds = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchArtistTracks() async {
    if (_artistIds == null || _artistIds!.isEmpty) return;
    setState(() { _loadingArtistTracks = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/artists/tracks', queryParameters: {'artists': _artistIds!.join(',')});
      final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      _artistTracks = data.map((e) {
        final rawPreview = e['preview_url'] ?? e['preview'];
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
            preview = '$base${rp.startsWith('/') ? '' : '/'}$rp';
          }
        }
        return {
          'id': e['id'],
          'title': e['title'] ?? 'Track ${e['id']}',
          'artist_name': e['artist_name'] ?? '',
          'duration_ms': e['duration_ms'] ?? 0,
          'preview_url': preview,
        };
      }).toList().cast<Map<String, dynamic>>();
    } catch (e) {
      _artistTracks = [];
      _error = e.toString();
    }
    if (mounted) setState(() { _loadingArtistTracks = false; });
  }

  @override
  Widget build(BuildContext context) {
    final playlists = widget.playlists ?? ref.watch(onboardingPlaylistsProvider);
    if (playlists != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gợi ý cho bạn')),
        body: playlists.isEmpty
            ? const Center(child: Text('Không có gợi ý'))
            : FutureBuilder<void>(
                future: _artistTracksFuture,
                builder: (ctx, snap) {
                  // we will render a single ListView; if artist tracks exist, inject virtual playlist tiles at top
                  final List<Widget> topTiles = [];
                    if (_loadingArtistTracks) {
                    topTiles.add(const ListTile(title: Text('Loading artist tracks...')));
                  } else if (_artistTracks.isNotEmpty) {
                    // Shuffle all tracks first, then split into chunks so each virtual playlist
                    // contains randomly selected tracks.
                    final shuffled = List<Map<String, dynamic>>.from(_artistTracks);
                    shuffled.shuffle(Random());
                    final chunks = <List<Map<String, dynamic>>>[];
                    for (var i = 0; i < shuffled.length; i += 20) {
                      chunks.add(shuffled.sublist(i, (i + 20).clamp(0, shuffled.length)));
                    }
                    for (var idx = 0; idx < chunks.length; idx++) {
                      final chunk = chunks[idx];
                      // Build a title from the unique artist names in this chunk.
                      final artistsInChunk = chunk
                          .map((e) => (e['artist_name'] as String?) ?? '')
                          .where((s) => s.isNotEmpty)
                          .toSet()
                          .toList();
                      var title = 'Artists playlist #${idx + 1}';
                      if (artistsInChunk.isNotEmpty) {
                        title = artistsInChunk.join(' / ');
                        // Truncate long titles so they don't overflow UI
                        const maxLen = 40;
                        if (title.length > maxLen) {
                          title = title.substring(0, maxLen);
                          // Try to avoid cutting mid-separator
                          final lastSep = title.lastIndexOf(' / ');
                          if (lastSep > 0) title = title.substring(0, lastSep);
                          title = '${title.trim()}...';
                        }
                        // Append part number if we have multiple chunks
                        if (chunks.length > 1) title = '$title • part ${idx + 1}';
                      }
                      topTiles.add(ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        leading: const Icon(Icons.queue_music),
                        title: Text(title),
                        subtitle: Text('Playlist ${chunk.length} tracks from selected artists'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text('Public', style: TextStyle(fontSize: 12.0, color: Colors.black54)),
                            SizedBox(width: 8),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () async {
                          final passTitle = title;
                          context.go('/virtual-playlist', extra: {'tracks': chunk, 'title': passTitle});
                        },
                      ));
                    }
                  }

                  return ListView.separated(
                    itemCount: topTiles.length + playlists.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      if (i < topTiles.length) return topTiles[i];
                      final p = playlists[i - topTiles.length];
                      return ListTile(
                        title: Text(p['name']),
                        subtitle: Text('Score: ${p['score'].toStringAsFixed(2)}'),
                        onTap: () => context.go('/playlists/${p['id']}'),
                      );
                    },
                  );
                },
              ),
      );
    }

    // Fallback: fetch recommended/popular tracks from backend for display when no playlists
    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations')),
      body: _loadingRemote
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Lỗi: $_error'))
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchRecommendedTracks(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                    if (snap.hasError) return Center(child: Text('Lỗi tải bài hát: ${snap.error}'));
                    final list = snap.data ?? [];
                    if (list.isEmpty) return const Center(child: Text('Không có đề xuất bài hát'));
                    return ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (c, i) {
                        final t = list[i];
                        final track = Track(
                          id: t['track_id'].toString(),
                          title: t['title'] ?? 'Track ${t['track_id']}',
                          artistName: t['artist_name'] ?? '',
                          durationMs: (t['duration_ms'] as int?) ?? 0,
                        );
                        return ListTile(
                          title: Text(track.title),
                          subtitle: Text(track.artistName),
                          trailing: IconButton(
                            icon: const Icon(Icons.playlist_add),
                            tooltip: 'Thêm vào playlist',
                            onPressed: () => _showAddToPlaylistSheet(context, ref, track),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRecommendedTracks() async {
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
  final uid = auth.userId;
  if (uid == null) return [];
  final res = await dio.get('$base/recommend/user/$uid', options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      // data contains items like {track_id, score}. We need track metadata; for now assume backend returns track metadata in this endpoint, else frontend will show minimal info.
      // Try to map directly; if only ids present, return minimal entries.
      return data.map((e) {
        final tid = e['track_id'];
        return {
          'track_id': tid,
          'title': e['title'] ?? 'Track $tid',
          'artist_name': e['artist_name'] ?? '',
          'duration_ms': e['duration_ms'] ?? 0,
          'score': e['score'],
        };
      }).toList().cast<Map<String, dynamic>>();
    } catch (e) {
      return Future.error(e);
    }
  }

  void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref, Track track) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Consumer(
          builder: (c, r, _) {
            final asyncLists = r.watch(myPlaylistsProvider);
            return SafeArea(
              child: asyncLists.when(
                data: (lists) {
                  if (lists.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Bạn chưa có playlist. Hãy tạo mới ở tab Playlists.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              // Navigate to playlists tab (index might be 2 depending on shell nav order)
                              // We rely on parent navigation bar; developer can update if index changes.
                              // Using Router to go to /playlists
                              Navigator.of(context).pushNamed('/playlists');
                            },
                            child: const Text('Tới Playlists'),
                          )
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: lists.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c2, i) {
                      final p = lists[i];
                      return ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(p.name),
                        subtitle: p.description != null && p.description!.isNotEmpty
                            ? Text(p.description!)
                            : null,
                        onTap: () async {
                          final repo = r.read(playlistRepositoryProvider);
                          final tid = int.tryParse(track.id);
                          if (tid == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ID bài hát không hợp lệ')),
                            );
                            return;
                          }
                          try {
                            await repo.addTrack(p.id, tid);
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Đã thêm "${track.title}" vào ${p.name}')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Lỗi thêm vào playlist: $e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Lỗi tải playlists: $e'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
