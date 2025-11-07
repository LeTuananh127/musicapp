import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playlist_providers.dart';
import '../../like/application/like_providers.dart';
import '../../player/application/player_providers.dart';
import '../../../data/models/track.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../../shared/services/shuffle_state_manager.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  // chunking & shuffle state
  List<Map<String, dynamic>> _shuffled = [];
  List<List<Map<String, dynamic>>> _chunks = [];
  int _pageIndex = 0;
  bool _initializedForPlaylist = false;

  @override
  void dispose() {
    // Save shuffle state when leaving screen
    _saveShuffleState();
    super.dispose();
  }

  String get _screenKey =>
      ShuffleStateManager.playlistDetailKey(widget.playlistId);

  void _saveShuffleState() {
    if (_shuffled.isNotEmpty) {
      ShuffleStateManager.saveShuffleState(_screenKey, _shuffled, _pageIndex);
    }
  }

  void _prepareChunks(List<dynamic> list) {
    // Clear old shuffle state to force rebuild with new proxy URLs
    ShuffleStateManager.clearShuffleState(_screenKey);
    
    // Always create new shuffle with backend proxy URLs
    final copy = list.map((e) => e).toList().cast<Map<String, dynamic>>();
    copy.shuffle(Random());
    _shuffled = copy;
    _pageIndex = 0;

    _chunks = [];
    for (var i = 0; i < _shuffled.length; i += 20) {
      _chunks.add(_shuffled.sublist(i, (i + 20).clamp(0, _shuffled.length)));
    }
    _initializedForPlaylist = true;
  }

  void _reshuffle() {
    setState(() {
      _shuffled.shuffle(Random());
      _chunks = [];
      for (var i = 0; i < _shuffled.length; i += 20) {
        _chunks.add(_shuffled.sublist(i, (i + 20).clamp(0, _shuffled.length)));
      }
      _pageIndex = 0;
      // Save new shuffle state
      _saveShuffleState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlistId = widget.playlistId;
    final detail = ref.watch(playlistDetailProvider(playlistId));
    final tracks = ref.watch(playlistTracksProvider(playlistId));
    return Scaffold(
      appBar: AppBar(
        title: detail.when(
          data: (d) => Text(d.name),
          loading: () => const Text('Playlist'),
          error: (e, _) => const Text('Lỗi'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(playlistDetailProvider(playlistId));
              ref.invalidate(playlistTracksProvider(playlistId));
              setState(() {
                _initializedForPlaylist = false;
                _shuffled = [];
                _chunks = [];
                _pageIndex = 0;
              });
            },
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Column(
        children: [
          detail.when(
            data: (d) {
              final tracksData = ref.watch(playlistTracksProvider(playlistId));
              String extra = '';
              tracksData.whenOrNull(data: (list) {
                if (list.isNotEmpty) {
                  final totalMs =
                      list.fold<int>(0, (sum, e) => sum + (e.durationMs ?? 0));
                  if (totalMs > 0) {
                    final dur = Duration(milliseconds: totalMs);
                    final h = dur.inHours;
                    final m = dur.inMinutes.remainder(60);
                    final s = dur.inSeconds.remainder(60);
                    final durStr = h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
                    extra = ' • $durStr';
                  }
                }
              });
              return ListTile(
                title: Text(d.description ?? ''),
                subtitle: Text('${d.trackCount} tracks$extra'),
              );
            },
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => ListTile(title: Text('Lỗi: $e')),
          ),
          const Divider(height: 1),
          Expanded(
            child: tracks.when(
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Playlist trống'))
                  : Builder(builder: (ctx) {
                      // initialize shuffle/chunks once per playlist load
            if (!_initializedForPlaylist) {
            // Build preview_url using configured backend base URL so
            // emulator/device networking (10.0.2.2 / ngrok) is respected.
            final base = ref.read(appConfigProvider).apiBaseUrl;
            _prepareChunks(list
              .map((e) => {
                  'id': e.trackId,
                  'title': e.title ?? 'Track ${e.trackId}',
                  'artist_name': e.artistName ?? 'N/A',
                  'duration_ms': e.durationMs ?? 0,
                  'cover_url': e.coverUrl ?? '',
                  // Use backend proxy instead of direct Deezer CDN
                  'preview_url': e.trackId > 0
                    ? '$base/deezer/stream/${e.trackId}'
                    : '',
                })
              .toList());
            }

                      final pageCount = _chunks.isEmpty ? 1 : _chunks.length;
                      final currentChunk = _chunks.isEmpty
                          ? <Map<String, dynamic>>[]
                          : _chunks[_pageIndex.clamp(0, pageCount - 1)];

                      return Column(
                        children: [
                          // shuffle control only
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Shuffle',
                                  icon: const Icon(Icons.shuffle),
                                  onPressed:
                                      _shuffled.isEmpty ? null : _reshuffle,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: currentChunk.isEmpty
                                ? const Center(child: Text('Playlist trống'))
                                : ListView.separated(
                                    itemCount: currentChunk.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (c, idx) {
                                      final t = currentChunk[idx];
                                      final globalIndex = _shuffled.indexWhere(
                                          (e) =>
                                              (e['id']).toString() ==
                                              t['id'].toString());
                                      final liked = ref
                                          .watch(likedTracksProvider)
                                          .contains(int.tryParse(
                                                  t['id'].toString()) ??
                                              -1);
                                      final player =
                                          ref.watch(playerControllerProvider);
                                      final isCurrent = player.current?.id ==
                                          t['id'].toString();

                                      // Build album cover
                                      final rawCover =
                                          (t['cover_url'] as String?) ?? '';
                                      final cfg = ref.read(appConfigProvider);
                                      String resolvedCover = '';
                                      if (rawCover.isNotEmpty) {
                                        if (rawCover.startsWith('http')) {
                                          resolvedCover = rawCover;
                                        } else {
                                          final base = cfg.apiBaseUrl;
                                          resolvedCover =
                                              '$base${rawCover.startsWith('/') ? '' : '/'}$rawCover';
                                        }
                                      }
                                      Widget leadingWidget;
                                      if (resolvedCover.isNotEmpty) {
                                        leadingWidget = ClipOval(
                                          child: Image.network(
                                            resolvedCover,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              width: 48,
                                              height: 48,
                                              color: Colors.grey.shade200,
                                              child: const Icon(
                                                  Icons.music_note,
                                                  color: Colors.black54),
                                            ),
                                          ),
                                        );
                                      } else {
                                        leadingWidget = CircleAvatar(
                                          backgroundColor: Colors.grey.shade200,
                                          child: const Icon(Icons.music_note,
                                              color: Colors.black54),
                                        );
                                      }

                                      return ListTile(
                                        key: ValueKey(
                                            'pl-$playlistId-${t['id']}'),
                                        leading: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: leadingWidget),
                                        title: Text(
                                          t['title'] ?? 'Track ${t['id']}',
                                          style: isCurrent
                                              ? const TextStyle(
                                                  fontWeight: FontWeight.bold)
                                              : null,
                                        ),
                                        subtitle: Text(t['artist_name'] ?? 'N/A'),
                                        tileColor: isCurrent
                                            ? Colors.green.withValues(alpha: 0.06)
                                            : null,
                                        onTap: () {
                                          final ctrl = ref.read(
                                              playerControllerProvider.notifier);
                                          final queue = _shuffled
                                              .map((e) => Track(
                                                    id: (e['id']).toString(),
                                                    title: e['title'] ??
                                                        'Track ${(e['id']).toString()}',
                                                    artistName:
                                                        e['artist_name'] ?? 'N/A',
                                                    durationMs:
                                                        (e['duration_ms'] as int?) ??
                                                            180000,
                                                    previewUrl: e['preview_url']
                                                        as String?,
                                                    coverUrl:
                                                        e['cover_url'] as String?,
                                                  ))
                                              .toList();
                                          final startIndex =
                                              globalIndex >= 0 ? globalIndex : 0;
                                          // Debug: log track info
                                          if (queue.isNotEmpty && startIndex < queue.length) {
                                            print('🎵 Playlist tap: ${queue[startIndex].title}');
                                            print('   preview_url: ${queue[startIndex].previewUrl}');
                                            print('   cover_url: ${queue[startIndex].coverUrl}');
                                          }
                                          if (!isCurrent) {
                                            ctrl.playQueue(queue, startIndex,
                                                origin: {
                                                  'type': 'playlist',
                                                  'playlistId': playlistId
                                                });
                                          } else {
                                            ctrl.togglePlay();
                                          }
                                        },
                                        trailing: Wrap(
                                          spacing: 4,
                                          children: [
                                            IconButton(
                                              tooltip: liked ? 'Bỏ thích' : 'Thích',
                                              icon: Icon(
                                                  liked
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  color: liked ? Colors.red : null),
                                              onPressed: () => ref
                                                  .read(
                                                      likedTracksProvider.notifier)
                                                  .toggle(int.tryParse(
                                                          t['id'].toString()) ??
                                                      -1),
                                            ),
                                            IconButton(
                                              tooltip: 'Xóa khỏi playlist',
                                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                                              onPressed: () async {
                                                // Remove track from playlist
                                                await ref
                                                    .read(playlistTrackRemoveControllerProvider(
                                                            playlistId)
                                                        .notifier)
                                                    .remove(int.tryParse(
                                                            t['id'].toString()) ??
                                                        -1);
                                                ref.invalidate(
                                                    playlistTracksProvider(
                                                        playlistId));
                                                setState(() {
                                                  _initializedForPlaylist = false;
                                                  _shuffled = [];
                                                  _chunks = [];
                                                  _pageIndex = 0;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    }),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
