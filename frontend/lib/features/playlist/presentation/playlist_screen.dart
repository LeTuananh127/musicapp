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
                          // Edit button
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Chỉnh sửa',
                            onPressed: () => _showEditDialog(context, ref, p.id, p.name, p.description),
                          ),
                          // Delete button (red)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Xóa',
                            onPressed: () => _showDeleteDialog(context, ref, p.id, p.name),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(playlistId: p.id),
                      )),
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

  void _showEditDialog(BuildContext context, WidgetRef ref, int id, String name, String? description) {
    final nameCtrl = TextEditingController(text: name);
    final descCtrl = TextEditingController(text: description ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh sửa Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tên playlist không được trống')),
                );
                return;
              }
              // TODO: Call API to update playlist
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã cập nhật playlist')),
                );
                ref.invalidate(myPlaylistsProvider);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, int id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa playlist?'),
        content: Text('Bạn có chắc muốn xóa "$name"? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // TODO: Call API to delete playlist
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã xóa "$name"')),
                );
                ref.invalidate(myPlaylistsProvider);
              }
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
