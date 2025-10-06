import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/recommend_controller.dart';
import '../../../data/repositories/playlist_repository.dart';
import '../../playlist/application/playlist_providers.dart';
import '../../../data/models/track.dart';

class RecommendScreen extends ConsumerWidget {
  const RecommendScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTracks = ref.watch(recommendedTracksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations')),
      body: asyncTracks.when(
        data: (tracks) => ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (c, i) {
            final track = tracks[i];
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
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
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
