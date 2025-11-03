import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/like_providers.dart';
import '../../player/application/player_providers.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../../data/models/track.dart';
import '../../../shared/services/shuffle_state_manager.dart';

class LikedSongsScreen extends ConsumerStatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  ConsumerState<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends ConsumerState<LikedSongsScreen> {
  List<Map<String, dynamic>> _shuffled = [];
  List<List<Map<String, dynamic>>> _chunks = [];
  int _pageIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _reloadData();
  }

  Future<void> _reloadData() async {
    // Reload liked tracks from server
    await ref.read(likedTracksProvider.notifier).reload();
    // No need to invalidate - likedTracksListProvider watches likedTracksProvider
    // and will auto-rebuild when state changes
  }

  @override
  void dispose() {
    // Save shuffle state when leaving screen
    _saveShuffleState();
    super.dispose();
  }

  String get _screenKey => ShuffleStateManager.likedSongsKey;

  void _saveShuffleState() {
    if (_shuffled.isNotEmpty) {
      ShuffleStateManager.saveShuffleState(_screenKey, _shuffled, _pageIndex);
    }
  }

  void _prepareChunks(List tracks) {
    // Try to load saved shuffle state from current session
    final savedState = ShuffleStateManager.loadShuffleState(_screenKey);

    if (savedState != null) {
      // Restore saved shuffle state
      _shuffled = savedState['shuffled'] as List<Map<String, dynamic>>;
      _pageIndex = savedState['pageIndex'] as int;
    } else {
      // Create new shuffle
      final copy = tracks
          .map((e) => {
                'id': e.id,
                'title': e.title,
                'artist_name': e.artistName,
                'duration_ms': e.durationMs,
                'cover_url': e.coverUrl ?? '',
                'preview_url': e.previewUrl ?? '',
              })
          .toList()
          .cast<Map<String, dynamic>>();
      copy.shuffle(Random());
      _shuffled = copy;
      _pageIndex = 0;
    }

    _chunks = [];
    for (var i = 0; i < _shuffled.length; i += 20) {
      _chunks.add(_shuffled.sublist(i, (i + 20).clamp(0, _shuffled.length)));
    }
    _initialized = true;
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
    final likedList = ref.watch(likedTracksListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked Songs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reloadData,
          ),
        ],
      ),
      body: likedList.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
                child: Text('Chưa có bài hát nào bạn đã thích.'));
          }

          // ALWAYS reset shuffle state when tracks change (not just count)
          // This ensures unliked tracks are removed immediately
          final trackIds = tracks.map((t) => t.id).toSet();
          final currentIds = _shuffled.map((t) => t['id'].toString()).toSet();
          
          if (!_initialized || !trackIds.containsAll(currentIds) || trackIds.length != currentIds.length) {
            print('🔄 Resetting shuffle state: initialized=$_initialized, trackIds=${trackIds.length}, currentIds=${currentIds.length}');
            _initialized = false;
            _shuffled = [];
            _chunks = [];
            _pageIndex = 0;
            _prepareChunks(tracks);
          }

          final pageCount = _chunks.isEmpty ? 1 : _chunks.length;
          final currentChunk = _chunks.isEmpty
              ? <Map<String, dynamic>>[]
              : _chunks[_pageIndex.clamp(0, pageCount - 1)];

          return RefreshIndicator(
            onRefresh: _reloadData,
            child: Column(
              children: [
                // Shuffle control only
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
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
                      ? const Center(
                          child: Text('Chưa có bài hát nào bạn đã thích.'))
                      : ListView.separated(
                        itemCount: currentChunk.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (c, idx) {
                          final t = currentChunk[idx];
                          final globalIndex = _shuffled.indexWhere(
                              (e) => e['id'].toString() == t['id'].toString());
                          final trackId = int.tryParse(t['id'].toString()) ?? 0;
                          final liked =
                              ref.watch(likedTracksProvider).contains(trackId);
                          final player = ref.watch(playerControllerProvider);
                          final isCurrent =
                              player.current?.id == t['id'].toString();

                          // Build album cover
                          final rawCover = (t['cover_url'] as String?) ?? '';
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
                                errorBuilder: (_, __, ___) => Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.music_note,
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
                            tileColor: isCurrent
                                ? Colors.green.withOpacity(0.06)
                                : null,
                            leading: SizedBox(
                                width: 48, height: 48, child: leadingWidget),
                            title: Text(
                              t['title'] ?? '',
                              style: isCurrent
                                  ? const TextStyle(fontWeight: FontWeight.bold)
                                  : null,
                            ),
                            subtitle: Text(t['artist_name'] ?? ''),
                            onTap: () {
                              final ctrl =
                                  ref.read(playerControllerProvider.notifier);
                              final queue = _shuffled
                                  .map((e) => Track(
                                        id: e['id'].toString(),
                                        title: e['title'] ?? '',
                                        artistName: e['artist_name'] ?? '',
                                        durationMs: e['duration_ms'] ?? 0,
                                        previewUrl: e['preview_url'] as String?,
                                        coverUrl: e['cover_url'] as String?,
                                      ))
                                  .toList();
                              final startIndex =
                                  globalIndex >= 0 ? globalIndex : 0;
                              // Debug: log track info
                              if (queue.isNotEmpty && startIndex < queue.length) {
                                print('💙 Liked tap: ${queue[startIndex].title}');
                                print('   preview_url: ${queue[startIndex].previewUrl}');
                                print('   cover_url: ${queue[startIndex].coverUrl}');
                              }
                              if (!isCurrent) {
                                ctrl.playQueue(queue, startIndex,
                                    origin: {'type': 'liked'});
                              } else {
                                ctrl.togglePlay();
                              }
                            },
                            trailing: IconButton(
                              icon: Icon(
                                  liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: liked ? Colors.red : null),
                              onPressed: () async {
                                if (liked) {
                                  // Show confirmation dialog before unliking
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Bỏ thích bài hát?'),
                                      content: Text('Bạn có chắc muốn bỏ thích "${t['title']}"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Hủy'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Bỏ thích'),
                                        ),
                                      ],
                                    ),
                                  );
                                  
                                  if (confirmed == true) {
                                    await ref.read(likedTracksProvider.notifier).toggle(trackId);
                                  }
                                } else {
                                  // Like without confirmation
                                  await ref.read(likedTracksProvider.notifier).toggle(trackId);
                                }
                              },
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }
}
