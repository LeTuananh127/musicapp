import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/player_providers.dart';
import '../../../data/models/track.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final queue = state.queue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          if (queue.isNotEmpty)
            IconButton(
              tooltip: state.shuffle ? 'Tắt shuffle' : 'Bật shuffle',
              icon: Icon(Icons.shuffle, color: state.shuffle ? Theme.of(context).colorScheme.primary : null),
              onPressed: ctrl.toggleShuffle,
            ),
          if (queue.isNotEmpty)
            IconButton(
              tooltip: 'Xóa queue',
              icon: const Icon(Icons.clear_all),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Xóa toàn bộ queue?'),
                    content: const Text('Hành động này sẽ dừng phát và mất hàng đợi hiện tại.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Huỷ')),
                      ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Xóa')),
                    ],
                  ),
                );
                if (confirm == true) {
                  ctrl.stop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa queue')));
                  }
                }
              },
            ),
        ],
      ),
      body: queue.isEmpty
          ? const Center(child: Text('Queue trống'))
          : ReorderableListView.builder(
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                ctrl.reorder(oldIndex, newIndex);
              },
              itemBuilder: (c, i) {
                final Track t = queue[i];
                final isCurrent = i == state.currentIndex;
                return Dismissible(
                  key: ValueKey('q-${t.id}'),
                  background: Container(color: Colors.redAccent.withValues(alpha: 0.7), alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 16), child: const Icon(Icons.delete, color: Colors.white)),
                  secondaryBackground: Container(color: Colors.redAccent.withValues(alpha: 0.7), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) => ctrl.removeAt(i),
                  child: ListTile(
                    selected: isCurrent,
                    selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('ID: ${t.id}'),
                    leading: isCurrent ? const Icon(Icons.play_arrow) : Text('${i + 1}'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill),
                          tooltip: 'Phát từ đây',
                          onPressed: () => ctrl.jumpTo(i),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Xóa khỏi queue',
                          onPressed: () => ctrl.removeAt(i),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
