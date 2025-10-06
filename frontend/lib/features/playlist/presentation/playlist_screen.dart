import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playlist_providers.dart';
import '../../like/presentation/liked_songs_screen.dart';
import 'playlist_detail_screen.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlaylists = ref.watch(myPlaylistsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myPlaylistsProvider),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: asyncPlaylists.when(
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myPlaylistsProvider),
          child: list.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 160),
                    Center(child: Text('Chưa có playlist')),
                  ],
                )
              : ListView.separated(
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(Icons.favorite, color: Colors.red),
                        title: const Text('Liked Songs'),
                        subtitle: const Text('Các bài hát bạn đã thích'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                        ),
                      );
                    }
                    final p = list[i - 1];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text(p.description ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.isPublic ? 'Public' : 'Private'),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: Theme.of(c).colorScheme.outline),
                        ],
                      ),
                      onTap: () => _showPlaylistActions(context, ref, p.id, p.name),
                    );
                  },
                ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên')),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Mô tả')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          Consumer(builder: (c, r, _) {
            final state = r.watch(createPlaylistControllerProvider);
            return FilledButton(
              onPressed: state.loading
                  ? null
                  : () async {
                      final ok = await r.read(createPlaylistControllerProvider.notifier)
                          .create(nameCtrl.text.trim(), description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim());
                      if (ok && context.mounted) Navigator.pop(ctx);
                    },
              child: state.loading ? const SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Tạo'),
            );
          })
        ],
      ),
    );
  }

  void _showPlaylistActions(BuildContext context, WidgetRef ref, int id, String name) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Mở'),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: id),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Đóng'),
              onTap: () => Navigator.pop(c),
            ),
          ],
        ),
      ),
    );
  }
}
