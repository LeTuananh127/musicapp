import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playlist_providers.dart';
import '../../like/application/like_providers.dart';
import '../../player/application/player_providers.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/playlist_repository.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final int playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                final queue = list
                    .map((e) => Track(
                          id: e.trackId.toString(),
                          title: e.title ?? 'Track ${e.trackId}',
                          artistName: 'N/A',
                          durationMs: e.durationMs ?? 180000,
                        ))
                    .toList();
                ref.read(playerControllerProvider.notifier).playQueue(queue, 0);
              });
            },
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(playlistDetailProvider(playlistId));
              ref.invalidate(playlistTracksProvider(playlistId));
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
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: true,
                      itemCount: list.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final mutable = [...list];
                        final item = mutable.removeAt(oldIndex);
                        mutable.insert(newIndex, item);
                        // optimistic UI: update provider cache by invalidating (simpler: ref.invalidate)
                        final repo = ref.read(playlistRepositoryProvider) as dynamic; // concrete
                        await repo.reorderTracks(playlistId, mutable.map((e) => e.trackId).toList());
                        ref.invalidate(playlistTracksProvider(playlistId));
                      },
                      itemBuilder: (c, i) {
                        final t = list[i];
                        final liked = ref.watch(likedTracksProvider).contains(t.trackId);
                        final player = ref.watch(playerControllerProvider);
                        final isCurrent = player.current?.id == t.trackId.toString();
                        final playing = isCurrent && player.playing;
                        final durMs = t.durationMs ?? 0;
                        String fmt(int ms){
                          final d = Duration(milliseconds: ms);
                          final m = d.inMinutes.remainder(60).toString().padLeft(2,'0');
                          final s = d.inSeconds.remainder(60).toString().padLeft(2,'0');
                          return '$m:$s';
                        }
                        final playerState = ref.watch(playerControllerProvider);
                        final currentPos = isCurrent ? playerState.position : Duration.zero;
                        String posStr = '';
                        if (isCurrent) {
                          final total = Duration(milliseconds: durMs == 0 ? 1 : durMs);
                          String fmtD(Duration d){
                            final m = d.inMinutes.remainder(60).toString().padLeft(2,'0');
                            final s = d.inSeconds.remainder(60).toString().padLeft(2,'0');
                            return '$m:$s';
                          }
                          posStr = ' • ${fmtD(currentPos)} / ${fmtD(total)}';
                        }
                        return ListTile(
                          key: ValueKey('pl-$playlistId-${t.trackId}'),
                          leading: CircleAvatar(backgroundColor: isCurrent ? Colors.green.shade600 : null, child: Text('${i + 1}')),
                          title: Text(
                            t.title ?? 'Track ${t.trackId}',
                            style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
                          ),
                          subtitle: Text('${durMs>0?fmt(durMs):'--:--'}$posStr • ID: ${t.trackId}'),
                          tileColor: isCurrent ? Colors.green.withValues(alpha: 0.08) : null,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: liked ? 'Bỏ thích' : 'Thích',
                                icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
                                onPressed: () => ref.read(likedTracksProvider.notifier).toggle(t.trackId),
                              ),
                              IconButton(
                                tooltip: playing ? 'Tạm dừng' : 'Phát',
                                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                                onPressed: () {
                                  final ctrl = ref.read(playerControllerProvider.notifier);
                                  if (!isCurrent) {
                                    // Build queue from current list so next/previous work
                                    final queue = list
                                        .map((e) => Track(
                                              id: e.trackId.toString(),
                                              title: e.title ?? 'Track ${e.trackId}',
                                              artistName: 'N/A',
                                              durationMs: e.durationMs ?? 180000,
                                            ))
                                        .toList();
                                    ctrl.playQueue(queue, i);
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
                                        await ref.read(playlistTrackRemoveControllerProvider(playlistId).notifier).remove(t.trackId);
                                      },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
