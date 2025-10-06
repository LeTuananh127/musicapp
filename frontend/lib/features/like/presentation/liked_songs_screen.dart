import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/like_providers.dart';
import '../../player/application/player_providers.dart';

class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likedList = ref.watch(likedTracksListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked Songs'),
        actions: [
          IconButton(
            tooltip: 'Play All',
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              final data = ref.read(likedTracksListProvider);
              data.whenOrNull(data: (tracks) {
                if (tracks.isEmpty) return;
                ref.read(playerControllerProvider.notifier).playQueue(tracks, 0);
              });
            },
          ),
        ],
      ),
      body: likedList.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(child: Text('Chưa có bài hát nào bạn đã thích.'));
          }
            return ListView.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final t = tracks[i];
                final trackId = int.tryParse(t.id) ?? 0;
                final liked = ref.watch(likedTracksProvider).contains(trackId);
                final player = ref.watch(playerControllerProvider);
                final isCurrent = player.current?.id == t.id;
                final playing = isCurrent && player.playing;
                String fmt(int ms){
                  final d = Duration(milliseconds: ms);
                  final m = d.inMinutes.remainder(60).toString().padLeft(2,'0');
                  final s = d.inSeconds.remainder(60).toString().padLeft(2,'0');
                  return '$m:$s';
                }
                final durText = fmt(t.durationMs);
                final playerState = ref.watch(playerControllerProvider);
                Duration currentPos = isCurrent ? playerState.position : Duration.zero;
                String extra = '';
                if (isCurrent) {
                  String fmtD(Duration d){
                    final m = d.inMinutes.remainder(60).toString().padLeft(2,'0');
                    final s = d.inSeconds.remainder(60).toString().padLeft(2,'0');
                    return '$m:$s';
                  }
                  final total = Duration(milliseconds: t.durationMs);
                  extra = ' • ${fmtD(currentPos)} / ${fmtD(total)}';
                }
                return ListTile(
                  tileColor: isCurrent ? Colors.blue.withValues(alpha: 0.06) : null,
                  title: Text(
                    t.title,
                    style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
                  ),
                  subtitle: Text('${t.artistName} • $durText$extra'),
                  leading: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
                        onPressed: () => ref.read(likedTracksProvider.notifier).toggle(trackId),
                      ),
                      IconButton(
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                        onPressed: () {
                          final ctrl = ref.read(playerControllerProvider.notifier);
                          if (!isCurrent) {
                            ctrl.playQueue(tracks, i);
                          } else {
                            ctrl.togglePlay();
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }
}
