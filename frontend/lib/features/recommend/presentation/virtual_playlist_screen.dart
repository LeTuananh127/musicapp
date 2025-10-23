import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../like/application/like_providers.dart';
import '../../player/application/player_providers.dart';
import '../../playlist/application/playlist_providers.dart';
import '../../../data/repositories/playlist_repository.dart';
import '../../../data/models/track.dart';
class VirtualPlaylistScreen extends ConsumerStatefulWidget {
  final List<int>? artistIds;
  final List<Map<String, dynamic>>? tracks;
  final String title;
  const VirtualPlaylistScreen({super.key, this.artistIds, this.tracks, required this.title});

  @override
  ConsumerState<VirtualPlaylistScreen> createState() => _VirtualPlaylistScreenState();
}

class _VirtualPlaylistScreenState extends ConsumerState<VirtualPlaylistScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tracks = [];
  List<Map<String, dynamic>> _shuffled = [];
  List<List<Map<String, dynamic>>> _chunks = [];
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _prepareChunks() {
    _shuffled = _tracks.map((e) => Map<String, dynamic>.from(e)).toList();
    _shuffled.shuffle(Random());
    _chunks = [];
    for (var i = 0; i < _shuffled.length; i += 20) {
      _chunks.add(_shuffled.sublist(i, (i + 20).clamp(0, _shuffled.length)));
    }
    _pageIndex = 0;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.tracks != null) {
        _tracks = widget.tracks!.map((e) => Map<String, dynamic>.from(e)).toList();
        _prepareChunks();
      } else {
        if (widget.artistIds == null || widget.artistIds!.isEmpty) {
          _tracks = [];
          _error = 'No artist ids provided';
          setState(() { _loading = false; });
          return;
        }
        final dio = ref.read(dioProvider);
        final base = ref.read(appConfigProvider).apiBaseUrl;
        final res = await dio.get('$base/artists/tracks', queryParameters: {'artists': widget.artistIds!.join(',')});
        final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
        _tracks = data.map((e) {
          final rawPreview = e['preview_url'] ?? e['preview'];
          String? preview;
          if (rawPreview != null) {
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
            'cover_url': e['cover_url'] ?? e['cover'] ?? e['album_cover_url'] ?? '',
            'preview_url': preview,
          };
        }).toList().cast<Map<String, dynamic>>();
        _prepareChunks();
      }
    } catch (e) {
      _error = e.toString();
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _tracks.fold<int>(0, (s, e) => s + (e['duration_ms'] as int? ?? 0));
    final dur = Duration(milliseconds: totalMs);
    final durStr = dur.inHours > 0 ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m' : '${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s';
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Lỗi: $_error'),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Quay lại'),
                          ),
                        ],
                      ),
                    )
              : Column(
                  children: [
                    ListTile(
                      title: Text(widget.title),
                      subtitle: Text('${_tracks.length} tracks • Public • $durStr'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {
                            final queue = _shuffled.isNotEmpty
                                ? _shuffled
                                    .map((e) => Track(id: e['id'].toString(), title: e['title'] ?? 'Track ${e['id']}', artistName: e['artist_name'] ?? '', durationMs: (e['duration_ms'] as int?) ?? 0))
                                    .toList()
                                : _tracks
                                    .map((e) => Track(id: e['id'].toString(), title: e['title'] ?? 'Track ${e['id']}', artistName: e['artist_name'] ?? '', durationMs: (e['duration_ms'] as int?) ?? 0))
                                    .toList();
                            if (queue.isNotEmpty) ref.read(playerControllerProvider.notifier).playQueue(queue, 0);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _load,
                        ),
                      ]),
                    ),
                    const Divider(height: 1),
                    // Debug: show sample computed cover URLs so we can verify whether
                    // the app is computing absolute URLs correctly or the backend
                    // returns relative paths. Remove this once verified.
                    if (_tracks.isNotEmpty) Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                      child: Builder(builder: (c) {
                        final base = ref.read(appConfigProvider).apiBaseUrl;
                        final samples = <String>[];
                        for (var i = 0; i < _tracks.length && samples.length < 3; i++) {
                          final raw = (_tracks[i]['cover_url'] as String?) ?? '';
                          if (raw.isEmpty) continue;
                          final full = raw.startsWith('http') ? raw : '$base${raw.startsWith('/') ? '' : '/'}$raw';
                          samples.add(full);
                        }
                        if (samples.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: samples.map((s) => Text(s, style: const TextStyle(fontSize: 11, color: Colors.black54))).toList(),
                        );
                      }),
                    ),
                    if (_tracks.isEmpty)
                      const Expanded(child: Center(child: Text('Playlist trống')))
                    else
                      Expanded(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: _pageIndex > 0 ? () => setState(() => _pageIndex -= 1) : null,
                                  ),
                                  Text('Page ${_pageIndex + 1} / ${_chunks.isEmpty ? 1 : _chunks.length}'),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: _pageIndex < (_chunks.length - 1) ? () => setState(() => _pageIndex += 1) : null,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.shuffle),
                                    onPressed: _shuffled.isEmpty ? null : _reshuffle,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: ListView.separated(
                                itemCount: _chunks.isEmpty ? 0 : _chunks[_pageIndex.clamp(0, _chunks.length - 1)].length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (c, idx) {
                                  final chunk = _chunks.isEmpty ? <Map<String, dynamic>>[] : _chunks[_pageIndex.clamp(0, _chunks.length - 1)];
                                  final t = chunk[idx];
                                  final globalIndex = _shuffled.indexWhere((e) => e['id'].toString() == t['id'].toString());
                                  final tid = t['id'] as int;
                                  final trackModel = Track(id: tid.toString(), title: t['title'] ?? 'Track $tid', artistName: t['artist_name'] ?? '', durationMs: (t['duration_ms'] as int?) ?? 0);
                                  final liked = ref.watch(likedTracksProvider).contains(tid);
                                  final player = ref.watch(playerControllerProvider);
                                  final isCurrent = player.current?.id == trackModel.id;
                                  final rawCover = (t['cover_url'] as String?) ?? '';
                                  final cfg = ref.read(appConfigProvider);
                                  String resolvedCover = '';
                                  if (rawCover.isNotEmpty) {
                                    if (rawCover.startsWith('http')) {
                                      resolvedCover = rawCover;
                                    } else {
                                      final base = cfg.apiBaseUrl;
                                      resolvedCover = '$base${rawCover.startsWith('/') ? '' : '/'}$rawCover';
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
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 48,
                                          height: 48,
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.music_note, color: Colors.black54),
                                        ),
                                      ),
                                    );
                                  } else {
                                    leadingWidget = CircleAvatar(
                                      backgroundColor: Colors.grey.shade200,
                                      child: const Icon(Icons.music_note, color: Colors.black54),
                                    );
                                  }
                                  return ListTile(
                                    leading: SizedBox(width: 48, height: 48, child: leadingWidget),
                                    title: Text(trackModel.title, style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null),
                                    subtitle: Text(trackModel.artistName),
                                    tileColor: isCurrent ? Colors.green.withOpacity(0.06) : null,
                                    onTap: () {
                                      final ctrl = ref.read(playerControllerProvider.notifier);
                                      final queue = _shuffled.isNotEmpty
                                          ? _shuffled.map((e) => Track(id: e['id'].toString(), title: e['title'] ?? 'Track ${e['id']}', artistName: e['artist_name'] ?? '', durationMs: (e['duration_ms'] as int?) ?? 0, previewUrl: e['preview_url'] as String? , coverUrl: e['cover_url'] as String? )).toList()
                                          : _tracks.map((e) => Track(id: e['id'].toString(), title: e['title'] ?? 'Track ${e['id']}', artistName: e['artist_name'] ?? '', durationMs: (e['duration_ms'] as int?) ?? 0, previewUrl: e['preview_url'] as String?, coverUrl: e['cover_url'] as String?)).toList();
                                      final startIndex = globalIndex >= 0 ? globalIndex : 0;
                                      if (!isCurrent) {
                                        ctrl.playQueue(queue, startIndex);
                                      } else {
                                        ctrl.togglePlay();
                                      }
                                    },
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
                                          onPressed: () => ref.read(likedTracksProvider.notifier).toggle(tid),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) async {
                                            if (v == 'add') {
                                              _showAddToPlaylistSheet(context, ref, trackModel);
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem(value: 'add', child: Text('Thêm vào playlist')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
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
                        subtitle: p.description != null && p.description!.isNotEmpty ? Text(p.description!) : null,
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

