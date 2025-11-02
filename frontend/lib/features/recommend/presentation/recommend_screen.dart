import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math';
import '../../../shared/providers/dio_provider.dart';
import '../../auth/application/auth_providers.dart';
import 'package:dio/dio.dart';
import '../application/recommend_controller.dart';
import '../../../data/repositories/recommendation_repository.dart';
import '../../../data/repositories/playlist_repository.dart';
import '../../playlist/application/playlist_providers.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/track_repository.dart';
import 'conversational_mood_chat_widget.dart';
import '../../../shared/services/shuffle_state_manager.dart';

class RecommendScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>>? playlists;
  const RecommendScreen({super.key, this.playlists});

  @override
  ConsumerState<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends ConsumerState<RecommendScreen> {
  bool _creatingPlaylist = false;
  bool _loadingRemote = false;
  String? _error;
  List<int>? _artistIds;
  bool _loadingArtistTracks = false;
  List<Map<String, dynamic>> _artistTracks = [];
  Future<void>? _artistTracksFuture;
  bool _loadingFavoriteArtists = false;
  String? _favoriteArtistsError;
  List<_FavoriteArtist> _favoriteArtists = [];
  bool _loadingTopPlays = false;
  String? _topPlaysError;
  List<Map<String, dynamic>> _topPlayedTracks = [];
  bool _loadingBehaviorTracks = false;
  String? _behaviorTracksError;
  List<Map<String, dynamic>> _behaviorTracks = [];

  // Shuffle state for virtual playlists section
  List<Map<String, dynamic>>? _virtualPlaylistsShuffled;

  @override
  void initState() {
    super.initState();
    _loadShuffleState();
    _initializeData();
  }

  @override
  void dispose() {
    _saveShuffleState();
    super.dispose();
  }

  String get _screenKey => 'recommend_virtual_playlists';

  void _loadShuffleState() {
    final savedState = ShuffleStateManager.loadShuffleState(_screenKey);
    if (savedState != null) {
      _virtualPlaylistsShuffled =
          savedState['shuffled'] as List<Map<String, dynamic>>;
    }
  }

  void _saveShuffleState() {
    if (_virtualPlaylistsShuffled != null &&
        _virtualPlaylistsShuffled!.isNotEmpty) {
      ShuffleStateManager.saveShuffleState(
          _screenKey, _virtualPlaylistsShuffled!, 0);
    }
  }

  void _initializeData() {
    Future.microtask(() async {
      await _ensurePlaylistsIfNeeded();
      await _ensureArtistIds();
      await _loadArtistTracksIfNeeded(force: true);
      await Future.wait([
        _loadFavoriteArtists(),
        _loadTopPlayedTracks(),
        _loadBehaviorBasedTracks(),
      ]);
    });
  }

  Future<void> _loadArtistTracksIfNeeded({bool force = false}) async {
    // ensure we have artist ids first
    await _ensureArtistIds();
    if (_artistIds == null || _artistIds!.isEmpty) return;
    // ensure we only kick off the tracks fetch once
    if (force || _artistTracksFuture == null) {
      _artistTracksFuture = _fetchArtistTracks();
    }
    try {
      await _artistTracksFuture;
    } catch (_) {
      // error already captured inside _fetchArtistTracks
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensurePlaylistsIfNeeded() async {
    final onboarding = ref.read(onboardingPlaylistsProvider);
    if (widget.playlists != null || onboarding != null) return;
    // try to fetch user's preferred artists and call recommend endpoint
    setState(() {
      _loadingRemote = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/users/me/preferences/artists',
          options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List ids = res.data is List ? res.data : res.data['value'] ?? [];
      if (ids.isEmpty) {
        setState(() {
          _loadingRemote = false;
        });
        return;
      }
      // store artist ids for later 'all tracks' fetch
      try {
        _artistIds = ids.map((e) => e as int).toList();
      } catch (_) {
        _artistIds = List<int>.from(ids);
      }
      final artistParam = _artistIds!.join(',');
      final r2 = await dio.get('$base/recommend/playlists',
          queryParameters: {'artists': artistParam},
          options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List data = r2.data is Map ? r2.data['value'] ?? r2.data : r2.data;
      final playlists = data
          .map((e) => {'id': e['id'], 'name': e['name'], 'score': e['score']})
          .toList();
      ref.read(onboardingPlaylistsProvider.notifier).state = playlists;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted)
      setState(() {
        _loadingRemote = false;
      });
  }

  Future<void> _ensureArtistIds() async {
    if (_artistIds != null) return;
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/users/me/preferences/artists',
          options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
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
    setState(() {
      _loadingArtistTracks = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/artists/tracks',
          queryParameters: {'artists': _artistIds!.join(',')});
      final List data =
          res.data is Map ? res.data['value'] ?? res.data : res.data;
      _artistTracks = data
          .map((e) {
            final rawPreview = e['preview_url'] ?? e['preview'];
            String? preview;
            if (rawPreview == null) {
              preview = null;
            } else {
              final rp = rawPreview.toString();
              if (rp.startsWith('http')) {
                if (rp.contains('cdnt-preview.dzcdn.net') ||
                    rp.contains('cdns-preview.dzcdn.net') ||
                    rp.contains('dzcdn.net')) {
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
              'artist_id': e['artist_id'] ?? e['artistId'],
              'title': e['title'] ?? 'Track ${e['id']}',
              'artist_name': e['artist_name'] ?? '',
              'duration_ms': e['duration_ms'] ?? 0,
              'preview_url': preview,
              'cover_url': e['cover_url'] ?? e['cover'] ?? e['album_cover_url'],
            };
          })
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      _artistTracks = [];
      _error = e.toString();
    }
    if (mounted)
      setState(() {
        _loadingArtistTracks = false;
      });
  }

  Future<void> _loadFavoriteArtists() async {
    if (_artistIds == null || _artistIds!.isEmpty) {
      if (mounted) {
        setState(() {
          _favoriteArtists = [];
          _favoriteArtistsError = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loadingFavoriteArtists = true;
        _favoriteArtistsError = null;
      });
    }
    try {
      if (_artistTracksFuture != null) {
        await _artistTracksFuture;
      }
      final favorites = <int, _FavoriteArtistBuilder>{};
      for (final track in _artistTracks) {
        final artistId = (track['artist_id'] as num?)?.toInt();
        if (artistId == null) continue;
        final name = (track['artist_name'] as String?) ?? 'Artist $artistId';
        final builder = favorites.putIfAbsent(
            artistId, () => _FavoriteArtistBuilder(artistId, name));
        builder.addTrack(Map<String, dynamic>.from(track),
            _resolveMediaUrl(track['cover_url'] as String?));
      }
      final sorted = favorites.values.map((b) => b.build()).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _favoriteArtists = sorted;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _favoriteArtistsError = e.toString();
          _favoriteArtists = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingFavoriteArtists = false;
        });
      }
    }
  }

  Future<void> _loadTopPlayedTracks() async {
    if (mounted) {
      setState(() {
        _loadingTopPlays = true;
        _topPlaysError = null;
      });
    }
    try {
      final repo = ref.read(trackRepositoryProvider);
      final tracks = await repo.fetchAll(limit: 200, order: 'desc');
      tracks.sort((a, b) => (b.views ?? 0).compareTo(a.views ?? 0));
      final top = tracks.take(30).map(_trackModelToMap).toList();
      if (mounted) {
        setState(() {
          _topPlayedTracks = top;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _topPlaysError = e.toString();
          _topPlayedTracks = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingTopPlays = false;
        });
      }
    }
  }

  Future<void> _loadBehaviorBasedTracks() async {
    if (mounted) {
      setState(() {
        _loadingBehaviorTracks = true;
        _behaviorTracksError = null;
      });
    }
    try {
      final items = await _fetchRecommendedTracks();
      if (mounted) {
        setState(() {
          _behaviorTracks = items;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _behaviorTracksError = e.toString();
          _behaviorTracks = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingBehaviorTracks = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await _ensureArtistIds();
    await _loadArtistTracksIfNeeded(force: true);
    await Future.wait([
      _loadFavoriteArtists(),
      _loadTopPlayedTracks(),
      _loadBehaviorBasedTracks(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final playlists =
        widget.playlists ?? ref.watch(onboardingPlaylistsProvider);
    final canCreate = ref.read(authControllerProvider).userId != null;
    if (playlists != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gợi ý cho bạn'),
          actions: [
            IconButton(
              tooltip: 'AI Music Chat',
              icon: const Icon(Icons.smart_toy),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ConversationalMoodChatWidget(),
                  ),
                );
              },
            ),
            if (canCreate)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _creatingPlaylist
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Center(
                            widthFactor: 1.0,
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : IconButton(
                        tooltip: 'Tạo playlist từ gợi ý',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () =>
                            _createPlaylistFromRecommendations(context, ref),
                      ),
              )
          ],
        ),
        body: playlists.isEmpty
            ? const Center(child: Text('Không có gợi ý'))
            : RefreshIndicator(
                onRefresh: _refreshAll,
                child: FutureBuilder<void>(
                  future: _artistTracksFuture,
                  builder: (ctx, snap) {
                    final List<Widget> children = [];

                    final favoriteSection =
                        _buildFavoriteArtistsSection(context);
                    if (favoriteSection != null) {
                      children.add(favoriteSection);
                    }

                    final topPlaysSection = _buildTopPlaysSection(context);
                    if (topPlaysSection != null) {
                      if (children.isNotEmpty)
                        children.add(const SizedBox(height: 16));
                      children.add(topPlaysSection);
                    }

                    final behaviorSection =
                        _buildBehaviorPlaylistSection(context);
                    if (behaviorSection != null) {
                      if (children.isNotEmpty)
                        children.add(const SizedBox(height: 16));
                      children.add(behaviorSection);
                    }

                    final virtualSection =
                        _buildVirtualPlaylistsSection(context);
                    if (virtualSection.isNotEmpty) {
                      if (children.isNotEmpty)
                        children.add(const SizedBox(height: 16));
                      children.addAll(virtualSection);
                    }

                    if (children.isNotEmpty) {
                      children.add(const SizedBox(height: 16));
                    }
                    children
                        .add(_buildSectionHeader(context, 'Playlist đề xuất'));
                    children.add(const SizedBox(height: 8));
                    for (final p in playlists) {
                      children.add(Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.album_outlined),
                          title: Text(p['name'] ?? 'Playlist'),
                          subtitle:
                              Text('Score: ${p['score'].toStringAsFixed(2)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/playlists/${p['id']}'),
                        ),
                      ));
                    }
                    children.add(const SizedBox(height: 24));

                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: children,
                    );
                  },
                ),
              ),
      );
    }

    // Fallback: fetch recommended/popular tracks from backend for display when no playlists
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendations'),
        actions: [
          IconButton(
            tooltip: 'AI Music Chat',
            icon: const Icon(Icons.smart_toy),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConversationalMoodChatWidget(),
                ),
              );
            },
          ),
          if (canCreate)
            IconButton(
              tooltip: 'Tạo playlist từ gợi ý',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _createPlaylistFromRecommendations(context, ref),
            ),
        ],
      ),
      body: _loadingRemote
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Lỗi: $_error'))
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchRecommendedTracks(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done)
                      return const Center(child: CircularProgressIndicator());
                    if (snap.hasError)
                      return Center(
                          child: Text('Lỗi tải bài hát: ${snap.error}'));
                    final list = snap.data ?? [];
                    if (list.isEmpty)
                      return const Center(
                          child: Text('Không có đề xuất bài hát'));
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
                            onPressed: () =>
                                _showAddToPlaylistSheet(context, ref, track),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  Future<void> _createPlaylistFromRecommendations(
      BuildContext context, WidgetRef ref) async {
    if (_creatingPlaylist) return;
    setState(() {
      _creatingPlaylist = true;
    });
    try {
      final auth = ref.read(authControllerProvider);
      final uid = auth.userId;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Vui lòng đăng nhập để tạo playlist')));
        return;
      }
      final recRepo = ref.read(recommendationRepositoryProvider);
      final playlistRepo = ref.read(playlistRepositoryProvider);
      // Fetch top recommendations (limit 30)
      final recs = await recRepo.recommendForUser(uid, limit: 30);
      if (recs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không có đề xuất để tạo playlist')));
        return;
      }
      final name =
          'Gợi ý cho bạn - ${DateTime.now().toLocal().toIso8601String().split('T').first}';
      final created = await playlistRepo.create(name,
          description: 'Playlist auto-generated from your listening behaviour',
          isPublic: true);
      // Add tracks sequentially; ignore individual failures but report at the end
      var added = 0;
      for (final t in recs) {
        final tidStr = t.id;
        final tid = int.tryParse(tidStr) ??
            int.tryParse(tidStr.replaceAll(RegExp(r"[^0-9]"), ''));
        if (tid == null) continue;
        try {
          await playlistRepo.addTrack(created.id, tid);
          added++;
        } catch (_) {
          // continue
        }
      }
      // Refresh user's playlists provider so UI shows the new playlist
      try {
        ref.invalidate(myPlaylistsProvider);
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tạo playlist "${created.name}" với $added bài hát')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi khi tạo playlist: $e')));
    } finally {
      if (mounted)
        setState(() {
          _creatingPlaylist = false;
        });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRecommendedTracks() async {
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final uid = auth.userId;
      if (uid == null) return [];
      final res = await dio.get('$base/recommend/user/$uid',
          options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List data =
          res.data is Map ? res.data['value'] ?? res.data : res.data;
      // data contains items like {track_id, score}. We need track metadata; for now assume backend returns track metadata in this endpoint, else frontend will show minimal info.
      // Try to map directly; if only ids present, return minimal entries.
      return data
          .map((e) {
            final tid = e['track_id'];
            final parsedId = tid is int
                ? tid
                : tid is String
                    ? int.tryParse(tid) ?? (tid.hashCode & 0x7fffffff)
                    : (tid?.hashCode ?? DateTime.now().millisecondsSinceEpoch);
            return {
              'id': parsedId,
              'track_id': tid,
              'title': e['title'] ?? 'Track $tid',
              'artist_name': e['artist_name'] ?? '',
              'duration_ms': e['duration_ms'] ?? 0,
              'score': e['score'],
            };
          })
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      return Future.error(e);
    }
  }

  void _showAddToPlaylistSheet(
      BuildContext context, WidgetRef ref, Track track) {
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
                          const Text(
                              'Bạn chưa có playlist. Hãy tạo mới ở tab Playlists.'),
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
                        subtitle:
                            p.description != null && p.description!.isNotEmpty
                                ? Text(p.description!)
                                : null,
                        onTap: () async {
                          final repo = r.read(playlistRepositoryProvider);
                          final tid = int.tryParse(track.id);
                          if (tid == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('ID bài hát không hợp lệ')),
                            );
                            return;
                          }
                          try {
                            await repo.addTrack(p.id, tid);
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Đã thêm "${track.title}" vào ${p.name}')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Lỗi thêm vào playlist: $e')),
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

  Widget? _buildFavoriteArtistsSection(BuildContext context) {
    if (_artistIds == null || _artistIds!.isEmpty) {
      return null;
    }
    if (_loadingFavoriteArtists) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Nghệ sĩ yêu thích'),
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }
    if (_favoriteArtistsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Nghệ sĩ yêu thích'),
            const SizedBox(height: 8),
            Text('Lỗi tải nghệ sĩ: $_favoriteArtistsError'),
          ],
        ),
      );
    }
    if (_favoriteArtists.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Nghệ sĩ yêu thích'),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: _favoriteArtists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (c, i) {
              final artist = _favoriteArtists[i];
              return _FavoriteArtistCard(
                artist: artist,
                onTap: () => context.push(
                  '/virtual-playlist',
                  extra: {
                    'tracks': artist.tracks,
                    'title': 'Nghệ sĩ yêu thích: ${artist.name}',
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget? _buildTopPlaysSection(BuildContext context) {
    if (_loadingTopPlays) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Top lượt nghe'),
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_topPlaysError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Top lượt nghe'),
            const SizedBox(height: 8),
            Text('Lỗi tải top lượt nghe: $_topPlaysError'),
          ],
        ),
      );
    }
    if (_topPlayedTracks.isEmpty) return null;
    final preview = _topPlayedTracks
        .take(3)
        .map((t) => '${t['title']} • ${t['artist_name']}')
        .join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.15),
            child: Icon(Icons.trending_up,
                color: Theme.of(context).colorScheme.primary),
          ),
          title: const Text('Top 20 bài hát được nghe nhiều'),
          subtitle: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(
            '/virtual-playlist',
            extra: {
              'tracks': _topPlayedTracks,
              'title': 'Top lượt nghe',
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildBehaviorPlaylistSection(BuildContext context) {
    if (_loadingBehaviorTracks) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Dựa trên hành vi nghe'),
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_behaviorTracksError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Dựa trên hành vi nghe'),
            const SizedBox(height: 8),
            Text('Lỗi tải playlist đề xuất: $_behaviorTracksError'),
          ],
        ),
      );
    }
    if (_behaviorTracks.isEmpty) return null;
    final preview = _behaviorTracks
        .take(3)
        .map((t) => '${t['title']} • ${t['artist_name']}')
        .join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.secondary.withOpacity(0.15),
            child: Icon(Icons.psychology_alt,
                color: Theme.of(context).colorScheme.secondary),
          ),
          title: const Text('Playlist dành riêng cho bạn'),
          subtitle: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(
            '/virtual-playlist',
            extra: {
              'tracks': _behaviorTracks,
              'title': 'Dựa vào hành vi nghe',
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVirtualPlaylistsSection(BuildContext context) {
    if (_loadingArtistTracks) {
      return [
        _buildSectionHeader(context, 'Playlist nghệ sĩ tổng hợp'),
        const SizedBox(height: 12),
        const Center(child: CircularProgressIndicator()),
      ];
    }
    if (_artistTracks.isEmpty) return <Widget>[];

    final List<Widget> tiles = [];

    // Use saved shuffle state or create new one
    List<Map<String, dynamic>> shuffled;
    if (_virtualPlaylistsShuffled != null &&
        _virtualPlaylistsShuffled!.isNotEmpty) {
      // Verify saved state matches current tracks (in case data changed)
      final currentIds = _artistTracks.map((e) => e['id']).toSet();
      final savedIds = _virtualPlaylistsShuffled!.map((e) => e['id']).toSet();
      if (currentIds.length == savedIds.length &&
          currentIds.containsAll(savedIds)) {
        shuffled = _virtualPlaylistsShuffled!;
      } else {
        // Data changed, create new shuffle
        shuffled = List<Map<String, dynamic>>.from(_artistTracks);
        shuffled.shuffle(Random());
        _virtualPlaylistsShuffled = shuffled;
        _saveShuffleState();
      }
    } else {
      // First time, create shuffle
      shuffled = List<Map<String, dynamic>>.from(_artistTracks);
      shuffled.shuffle(Random());
      _virtualPlaylistsShuffled = shuffled;
      _saveShuffleState();
    }

    final chunks = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < shuffled.length; i += 20) {
      chunks.add(shuffled.sublist(i, (i + 20).clamp(0, shuffled.length)));
    }

    if (chunks.isEmpty) return <Widget>[];
    tiles.add(_buildSectionHeader(context, 'Playlist nghệ sĩ tổng hợp'));
    tiles.add(const SizedBox(height: 8));
    for (var idx = 0; idx < chunks.length; idx++) {
      final chunk = chunks[idx];
      final artistsInChunk = chunk
          .map((e) => (e['artist_name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      var title = 'Artists playlist #${idx + 1}';
      if (artistsInChunk.isNotEmpty) {
        title = artistsInChunk.join(' / ');
        const maxLen = 40;
        if (title.length > maxLen) {
          title = title.substring(0, maxLen);
          final lastSep = title.lastIndexOf(' / ');
          if (lastSep > 0) title = title.substring(0, lastSep);
          title = '${title.trim()}...';
        }
        if (chunks.length > 1) title = '$title • part ${idx + 1}';
      }
      tiles.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(title),
          subtitle:
              Text('Playlist ${chunk.length} tracks từ các nghệ sĩ yêu thích'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(
            '/virtual-playlist',
            extra: {
              'tracks': chunk,
              'title': title,
            },
          ),
        ),
      ));
    }
    return tiles;
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Map<String, dynamic> _trackModelToMap(Track track) {
    final parsedId = int.tryParse(track.id) ?? (track.id.hashCode & 0x7fffffff);
    return {
      'id': parsedId,
      'title': track.title,
      'artist_name': track.artistName,
      'duration_ms': track.durationMs,
      'preview_url': track.previewUrl,
      'cover_url': track.coverUrl,
    };
  }

  String? _resolveMediaUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }
}

class _FavoriteArtist {
  final int id;
  final String name;
  final String? coverUrl;
  final List<Map<String, dynamic>> tracks;

  const _FavoriteArtist(
      {required this.id,
      required this.name,
      required this.coverUrl,
      required this.tracks});
}

class _FavoriteArtistBuilder {
  final int id;
  final String name;
  String? _coverUrl;
  final List<Map<String, dynamic>> _tracks = [];

  _FavoriteArtistBuilder(this.id, this.name);

  void addTrack(Map<String, dynamic> track, String? coverUrl) {
    if (_tracks.length < 80) {
      _tracks.add(track);
    }
    if ((_coverUrl == null || _coverUrl!.isEmpty) &&
        coverUrl != null &&
        coverUrl.isNotEmpty) {
      _coverUrl = coverUrl;
    }
  }

  _FavoriteArtist build() {
    return _FavoriteArtist(
      id: id,
      name: name,
      coverUrl: _coverUrl,
      tracks: List<Map<String, dynamic>>.from(_tracks),
    );
  }
}

class _FavoriteArtistCard extends StatelessWidget {
  final _FavoriteArtist artist;
  final VoidCallback onTap;

  const _FavoriteArtistCard({required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Ink(
        width: 140,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: artist.coverUrl != null
                    ? Image.network(
                        artist.coverUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                              child: Icon(Icons.person,
                                  size: 40, color: Colors.black45)),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                            child: Icon(Icons.person,
                                size: 40, color: Colors.black45)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('${artist.tracks.length} bài hát',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
