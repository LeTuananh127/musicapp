import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playlist_providers.dart';
import '../../like/application/like_providers.dart';
import '../../player/application/player_providers.dart';
import '../../../data/models/track.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  // chunking & shuffle state
  List<Map<String, dynamic>> _shuffled = [];
  List<List<Map<String, dynamic>>> _chunks = [];
  int _pageIndex = 0;
  bool _initializedForPlaylist = false;

  void _prepareChunks(List<dynamic> list) {
    // produce a shuffled copy and split into pages of 20
    final copy = list.map((e) => e).toList().cast<Map<String, dynamic>>();
    copy.shuffle(Random());
    _shuffled = copy;
    _chunks = [];
    for (var i = 0; i < _shuffled.length; i += 20) {
      _chunks.add(_shuffled.sublist(i, (i + 20).clamp(0, _shuffled.length)));
    }
    _pageIndex = 0;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlistId = widget.playlistId;
    final detail = ref.watch(playlistDetailProvider(playlistId));
    final tracks = ref.watch(playlistTracksProvider(playlistId));
    final removeCtrl = ref.watch(playlistTrackRemoveControllerProvider(playlistId));
    return Scaffold(
      appBar: AppBar(
        title: detail.when(
          data: (d) => Text(d.name),
          loading: () => const Text('Playlist'),
          error: (e, _) => const Text('Lỗi'),
        ),
        actions: [
          IconButton(
            tooltip: 'Play All',
            onPressed: () {
              final tracksData = ref.read(playlistTracksProvider(playlistId));
              tracksData.whenOrNull(data: (list) {
                if (list.isEmpty) return;
                // ensure we play the entire shuffled queue if prepared, otherwise play full list
                final queueSource = _shuffled.isNotEmpty ? _shuffled : list.map((e) => {
                      'id': e.trackId,
                      'title': e.title ?? 'Track ${e.trackId}',
                      'artist_name': 'N/A',
                      'duration_ms': e.durationMs ?? 180000,
                    }).toList();
                final queue = queueSource
                    .map((e) => Track(
                          id: (e['id'] ?? e['trackId']).toString(),
                          title: e['title'] ?? 'Track ${(e['id'] ?? e['trackId']).toString()}',
                          artistName: e['artist_name'] ?? 'N/A',
                          durationMs: (e['duration_ms'] ?? e['durationMs'] ?? 180000) as int,
                        ))
                    .toList();
                if (queue.isNotEmpty) ref.read(playerControllerProvider.notifier).playQueue(queue, 0);
              });
            },
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(playlistDetailProvider(playlistId));
              ref.invalidate(playlistTracksProvider(playlistId));
              // reset local shuffle state so it's recomputed
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
                  final totalMs = list.fold<int>(0, (sum, e) => sum + (e.durationMs ?? 0));
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
                subtitle: Text('${d.trackCount} tracks • ${d.isPublic ? 'Public' : 'Private'}$extra'),
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
                        _prepareChunks(list.map((e) => {
                          'id': e.trackId,
                          'title': e.title ?? 'Track ${e.trackId}',
                          'artist_name': 'N/A',
                          'duration_ms': e.durationMs ?? 0,
                        }).toList());
                      }

                      final pageCount = _chunks.isEmpty ? 1 : _chunks.length;
                      final currentChunk = _chunks.isEmpty ? <Map<String, dynamic>>[] : _chunks[_pageIndex.clamp(0, pageCount - 1)];

                      return Column(
                        children: [
                          // paging & shuffle controls
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Prev page',
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: _pageIndex > 0 ? () => setState(() => _pageIndex -= 1) : null,
                                ),
                                Text('Page ${_pageIndex + 1} / $pageCount'),
                                IconButton(
                                  tooltip: 'Next page',
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: _pageIndex < pageCount - 1 ? () => setState(() => _pageIndex += 1) : null,
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Shuffle',
                                  icon: const Icon(Icons.shuffle),
                                  onPressed: _shuffled.isEmpty ? null : _reshuffle,
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
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (c, idx) {
                                      final t = currentChunk[idx];
                                      final globalIndex = _shuffled.indexWhere((e) => (e['id']).toString() == t['id'].toString());
                                      final liked = ref.watch(likedTracksProvider).contains(int.tryParse(t['id'].toString()) ?? -1);
                                      final player = ref.watch(playerControllerProvider);
                                      final isCurrent = player.current?.id == t['id'].toString();
                                      final playing = isCurrent && player.playing;
                                      final durMs = (t['duration_ms'] as int?) ?? 0;
                                      String fmt(int ms) {
                                        final d = Duration(milliseconds: ms);
                                        final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
                                        final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
                                        return '$m:$s';
                                      }
                                      final playerState = ref.watch(playerControllerProvider);
                                      final currentPos = isCurrent ? playerState.position : Duration.zero;
                                      String posStr = '';
                                      if (isCurrent) {
                                        final total = Duration(milliseconds: durMs == 0 ? 1 : durMs);
                                        String fmtD(Duration d) {
                                          final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
                                          final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
                                          return '$m:$s';
                                        }
                                        posStr = ' • ${fmtD(currentPos)} / ${fmtD(total)}';
                                      }
                                      return ListTile(
                                        key: ValueKey('pl-$playlistId-${t['id']}'),
                                        leading: CircleAvatar(backgroundColor: isCurrent ? Colors.green.shade600 : null, child: Text('${globalIndex + 1}')),
                                        title: Text(
                                          t['title'] ?? 'Track ${t['id']}',
                                          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
                                        ),
                                        subtitle: Text('${durMs > 0 ? fmt(durMs) : '--:--'}$posStr • ID: ${t['id']}'),
                                        tileColor: isCurrent ? Colors.green.withOpacity(0.08) : null,
                                        trailing: Wrap(
                                          spacing: 4,
                                          children: [
                                            IconButton(
                                              tooltip: liked ? 'Bỏ thích' : 'Thích',
                                              icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
                                              onPressed: () => ref.read(likedTracksProvider.notifier).toggle(int.tryParse(t['id'].toString()) ?? -1),
                                            ),
                                            IconButton(
                                              tooltip: playing ? 'Tạm dừng' : 'Phát',
                                              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                                              onPressed: () {
                                                final ctrl = ref.read(playerControllerProvider.notifier);
                                                // build queue from shuffled list so next/previous work across full set
                                                final queue = _shuffled
                                                    .map((e) => Track(
                                                          id: (e['id']).toString(),
                                                          title: e['title'] ?? 'Track ${(e['id']).toString()}',
                                                          artistName: e['artist_name'] ?? 'N/A',
                                                          durationMs: (e['duration_ms'] as int?) ?? 180000,
                                                        ))
                                                    .toList();
                                                if (!isCurrent) {
                                                  final startIndex = globalIndex >= 0 ? globalIndex : 0;
                                                  ctrl.playQueue(queue, startIndex);
                                                } else {
                                                  ctrl.togglePlay();
                                                }
                                              },
                                            ),
                                            IconButton(
                                              tooltip: 'Xóa',
                                              icon: const Icon(Icons.delete_outline),
                                              onPressed: removeCtrl is AsyncLoading
                                                  ? null
                                                  : () async {
                                                      // removing from original playlist still calls API as before
                                                      await ref.read(playlistTrackRemoveControllerProvider(playlistId).notifier).remove(int.tryParse(t['id'].toString()) ?? -1);
                                                      // invalidate so list reloads and shuffle state resets
                                                      ref.invalidate(playlistTracksProvider(playlistId));
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
