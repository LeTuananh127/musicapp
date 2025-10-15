import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/playlist_repository.dart';
import '../../like/application/like_providers.dart';
import '../../player/application/player_providers.dart';
import '../../playlist/application/playlist_providers.dart';
import '../../../data/repositories/track_repository.dart';
import '../../../shared/providers/dio_provider.dart';
import 'package:go_router/go_router.dart';

// Tracks provider to avoid refetch on every rebuild
final homeTracksProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(trackRepositoryProvider);
  // Fetch newest 50 so recently uploaded tracks appear
  return repo.fetchAll(limit: 50, order: 'desc');
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(homeTracksProvider),
          ),
          IconButton(
            tooltip: 'Play All',
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              final asyncValue = ref.read(homeTracksProvider);
              asyncValue.whenOrNull(data: (tracks) {
                if (tracks.isEmpty) return;
                ref.read(playerControllerProvider.notifier).playQueue(tracks, 0);
              });
            },
          ),
          IconButton(
            tooltip: 'Deezer',
            icon: const Icon(Icons.cloud),
            onPressed: () => context.go('/deezer'),
          ),
          IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: ref.watch(homeTracksProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(child: Text('Không có track.'));
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
              Widget? coverWidget;
              if (t.coverUrl != null) {
                final cfg = ref.read(appConfigProvider);
                final raw = t.coverUrl!;
                final resolved = raw.startsWith('http') ? raw : (cfg.apiBaseUrl + raw);
                coverWidget = ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    resolved,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                  ),
                );
              }
              return ListTile(
                title: Text(t.title),
                subtitle: Text(t.artistName),
                tileColor: isCurrent ? Colors.blue.withValues(alpha: 0.06) : null,
                leading: SizedBox(
                  width: 140,
                  child: Row(
                    children: [
                      if (coverWidget != null) coverWidget, if (coverWidget != null) const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
                        onPressed: () => ref.read(likedTracksProvider.notifier).toggle(trackId),
                      ),
                      IconButton(
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                        onPressed: () {
                          final ctrl = ref.read(playerControllerProvider.notifier);
                          if (!isCurrent) {
                            // Build queue from current fetched tracks
                            ctrl.playQueue(tracks, i);
                          } else {
                            ctrl.togglePlay();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'add') {
                      if (trackId <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Track ID không hợp lệ, không thể thêm.')),
                        );
                        return;
                      }
                      _showAddToPlaylist(context, ref, trackId);
                    }
                  },
                  itemBuilder: (c) => const [
                    PopupMenuItem(value: 'add', child: Text('Thêm vào playlist')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddToPlaylist(BuildContext context, WidgetRef ref, int trackId) {
    // ensure likes loaded (not strictly needed here)
    ref.read(likedTracksProvider.notifier).ensureLoaded();
    showModalBottomSheet(
      context: context,
      builder: (c) {
        return Consumer(builder: (c2, watchRef, _) {
          final playlistsAsync = watchRef.watch(myPlaylistsProvider);
          final membershipsAsync = watchRef.watch(trackPlaylistMembershipsProvider(trackId));
          return SafeArea(
          child: playlistsAsync.when(
            data: (pls) {
              if (pls.isEmpty) {
                return ListView(
                  children: [
                    const ListTile(title: Text('Chưa có playlist')),
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: const Text('Tải lại'),
                      onTap: () => ref.invalidate(myPlaylistsProvider),
                    )
                  ],
                ); 
              }
              final memberships = membershipsAsync.maybeWhen(data: (s) => s, orElse: () => <int>{});
              return ListView(
                children: [
                  const ListTile(title: Text('Chọn playlist')), 
                    for (final p in pls)
                      _AddToPlaylistTile(
                        playlistId: p.id,
                        name: p.name,
                        trackId: trackId,
                        ref: ref,
                        parentContext: context,
                        sheetContext: c,
                        alreadyIn: memberships.contains(p.id),
                      ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Tạo playlist mới và thêm'),
                    onTap: () async {
                      final name = await showDialog<String>(
                        context: context,
                        builder: (d) {
                          final ctrl = TextEditingController();
                          return AlertDialog(
                            title: const Text('Tên playlist'),
                            content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Nhập tên')), 
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Huỷ')),
                              ElevatedButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Tạo')), 
                            ],
                          );
                        },
                      );
                      if (name == null || name.isEmpty) return;
                      final repo = ref.read(playlistRepositoryProvider) as PlaylistRepository;
                      try {
                        final p = await repo.create(name);
                        ref.invalidate(myPlaylistsProvider);
                        await repo.addTrack(p.id, trackId);
                        ref.invalidate(trackPlaylistMembershipsProvider(trackId));
                        if (context.mounted) {
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã tạo và thêm vào "$name"')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tạo/thêm: $e')));
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Làm mới danh sách'),
                    onTap: () => watchRef.invalidate(myPlaylistsProvider),
                  )
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Lỗi tải playlist: $e'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(myPlaylistsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  )
                ],
              ),
            ),
          ),
        );
        });
      },
    );
  }
}

class _AddToPlaylistTile extends StatefulWidget {
  final int playlistId;
  final String name;
  final int trackId;
  final WidgetRef ref;
  final BuildContext parentContext; // for snackbar
  final BuildContext sheetContext;  // for closing
  final bool alreadyIn;
  const _AddToPlaylistTile({required this.playlistId, required this.name, required this.trackId, required this.ref, required this.parentContext, required this.sheetContext, this.alreadyIn = false});

  @override
  State<_AddToPlaylistTile> createState() => _AddToPlaylistTileState();
}

class _AddToPlaylistTileState extends State<_AddToPlaylistTile> {
  bool _loading = false;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.name),
      leading: widget.alreadyIn ? const Icon(Icons.check, color: Colors.green) : null,
      trailing: _loading
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : widget.alreadyIn
              ? IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  tooltip: 'Gỡ khỏi playlist',
                  onPressed: _loading ? null : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Gỡ track?'),
                        content: Text('Xoá khỏi "${widget.name}"?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Huỷ')),
                          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Gỡ')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    setState(() => _loading = true);
                    final repo = widget.ref.read(playlistRepositoryProvider);
                    try {
                      await repo.removeTrack(widget.playlistId, widget.trackId).timeout(const Duration(seconds: 10));
                      if (mounted) setState(() => _loading = false);
                      try {
                        widget.ref.invalidate(playlistTracksProvider(widget.playlistId));
                        widget.ref.invalidate(playlistDetailProvider(widget.playlistId));
                        widget.ref.invalidate(trackPlaylistMembershipsProvider(widget.trackId));
                      } catch (_) {}
                      if (widget.parentContext.mounted) {
                        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                          SnackBar(content: Text('Đã gỡ khỏi "${widget.name}"')),
                        );
                      }
                    } catch (e) {
                      if (mounted) setState(() => _loading = false);
                      if (widget.parentContext.mounted) {
                        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                          SnackBar(content: Text('Gỡ thất bại: $e')),
                        );
                      }
                    }
                  },
                )
              : null,
      enabled: !_loading, // Cho phép tap cả khi alreadyIn để no-op hoặc future enhancement
      onTap: _loading || widget.alreadyIn
          ? null
          : () async {
        setState(() => _loading = true);
        final repo = widget.ref.read(playlistRepositoryProvider);
        try {
          // Fail-safe: add a timeout so UI không quay mãi nếu server im lặng
          await repo.addTrack(widget.playlistId, widget.trackId).timeout(const Duration(seconds: 10));
          if (mounted) setState(() => _loading = false);
          if (widget.parentContext.mounted) {
            Navigator.pop(widget.sheetContext);
            // invalidate playlist detail & tracks if someone đang mở (an toàn, chi phí thấp)
            try {
              widget.ref.invalidate(playlistTracksProvider(widget.playlistId));
              widget.ref.invalidate(playlistDetailProvider(widget.playlistId));
              widget.ref.invalidate(trackPlaylistMembershipsProvider(widget.trackId));
            } catch (_) {}
            ScaffoldMessenger.of(widget.parentContext).showSnackBar(
              SnackBar(content: Text('Đã thêm vào "${widget.name}"')),
            );
          }
        } on TimeoutException {
          if (mounted) setState(() => _loading = false);
          if (widget.parentContext.mounted) {
            ScaffoldMessenger.of(widget.parentContext).showSnackBar(
              const SnackBar(content: Text('Hết thời gian chờ máy chủ (timeout).')), 
            );
          }
        } catch (e) {
          if (mounted) setState(() => _loading = false);
          if (widget.parentContext.mounted) {
            ScaffoldMessenger.of(widget.parentContext).showSnackBar(
              SnackBar(content: Text('Thêm thất bại: $e')),
            );
          }
        }
      },
    );
  }
}
