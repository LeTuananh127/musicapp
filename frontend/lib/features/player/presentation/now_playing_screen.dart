import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/player_providers.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final track = state.current;
    if (track == null) {
      return const Scaffold(body: Center(child: Text('Không có bài hát đang phát.')));
    }
    final dur = Duration(milliseconds: track.durationMs);
    final pos = state.position;
    String fmt(Duration d){
      final m = d.inMinutes.remainder(60).toString().padLeft(2,'0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2,'0');
      return '$m:$s';
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          IconButton(
            tooltip: state.shuffle? 'Tắt shuffle' : 'Bật shuffle',
            icon: Icon(Icons.shuffle, color: state.shuffle? Theme.of(context).colorScheme.primary : null),
            onPressed: ctrl.toggleShuffle,
          ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music),
            onPressed: () => Navigator.of(context).pushNamed('/queue'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Artwork placeholder
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(track.artistName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(fmt(pos)),
                Expanded(
                  child: Slider(
                    value: pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                    max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
                    onChanged: (v) => ctrl.seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
                Text(fmt(dur)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                IconButton(
                  icon: Icon(Icons.repeat, color: state.repeatMode == RepeatMode.all ? Theme.of(context).colorScheme.primary : null),
                  onPressed: ctrl.cycleRepeatMode,
                  tooltip: 'Repeat (All/One/Off)',
                ),
                IconButton(
                  icon: Icon(Icons.skip_previous, color: state.hasPrevious? null : Colors.grey),
                  onPressed: state.hasPrevious ? ctrl.previous : null,
                  tooltip: 'Previous',
                ),
                CircleAvatar(
                  radius: 30,
                  child: IconButton(
                    icon: Icon(state.playing ? Icons.pause : Icons.play_arrow, size: 32),
                    onPressed: ctrl.togglePlay,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, color: state.hasNext? null : Colors.grey),
                  onPressed: state.hasNext ? ctrl.next : null,
                  tooltip: 'Next',
                ),
                IconButton(
                  icon: Icon(Icons.repeat_one, color: state.repeatMode == RepeatMode.one ? Theme.of(context).colorScheme.primary : null),
                  onPressed: ctrl.cycleRepeatMode,
                  tooltip: 'Repeat One',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.queue_music),
              label: const Text('Xem queue'),
              onPressed: () => Navigator.of(context).pushNamed('/queue'),
            )
          ],
        ),
      ),
    );
  }
}
