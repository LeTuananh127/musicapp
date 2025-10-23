import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/track_repository.dart';
import '../../player/application/player_providers.dart';
import '../../player/application/audio_error_provider.dart';

// Keep track of which track ids we've reported as viewed in this app session to avoid duplicate calls
final Set<int> _reportedViews = <int>{};

final trackDetailProvider = FutureProvider.autoDispose.family<Track?, int>((ref, id) async {
  final repo = ref.read(trackRepositoryProvider);
  return repo.getById(id);
});

class TrackDetailScreen extends ConsumerWidget {
  final int trackId;
  const TrackDetailScreen({super.key, required this.trackId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trackDetailProvider(trackId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi tải track: $e')),
        data: (t) {
          if (t == null) return const Center(child: Text('Track không tồn tại'));
          // report view once per session and refresh track data so views show up
          if (!_reportedViews.contains(trackId)) {
            _reportedViews.add(trackId);
            // fire-and-forget the view call (best-effort)
            Future.microtask(() async {
              try {
                await ref.read(trackRepositoryProvider).view(trackId);
                // re-fetch the track so the latest `views` value is displayed
                ref.invalidate(trackDetailProvider(trackId));
              } catch (_) {}
            });
          }
          final ctrl = ref.read(playerControllerProvider.notifier);
          final state = ref.watch(playerControllerProvider);
          final audioError = ref.watch(audioErrorProvider);
          // display follows what's currently playing; if nothing is playing, show the requested track
          final display = state.current ?? t;
          // show audio errors, then clear
          if (audioError != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(audioError)));
              ref.read(audioErrorProvider.notifier).state = null;
            });
          }
          Widget cover = const Icon(Icons.music_note, size: 120);
          if (display.coverUrl != null) {
            cover = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(display.coverUrl!, width: 200, height: 200, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 120),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(child: cover),
                const SizedBox(height: 16),
                Text(display.title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(display.artistName, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                // Views
                if (t.views != null) Text('Lượt xem: ${t.views}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                Text('Duration: ${display.duration.inMinutes}:${(display.duration.inSeconds.remainder(60)).toString().padLeft(2, '0') }'),
                const SizedBox(height: 24),
                // Shuffle / prev / play / next / repeat
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle, color: state.shuffle ? Theme.of(context).colorScheme.primary : null),
                      onPressed: () => ctrl.toggleShuffle(),
                    ),
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: state.hasPrevious ? () => ctrl.previous() : null,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                      child: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        if (display.previewUrl == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không có preview cho track này.')));
                          return;
                        }
                        if (state.current?.id == display.id) {
                          ctrl.togglePlay();
                        } else {
                          // start playing the displayed track (which may be the original t or the current)
                          ctrl.playQueue([display], 0);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.skip_next),
                      onPressed: state.hasNext ? () => ctrl.next() : null,
                    ),
                    IconButton(
                      icon: Icon(state.repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                          color: state.repeatMode == RepeatMode.off ? null : Theme.of(context).colorScheme.primary),
                      onPressed: () => ctrl.cycleRepeatMode(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Position slider
                if (state.current != null) ...[
                  Text('${_fmt(state.position)} / ${_fmt(state.current!.duration)}'),
                  Slider(
                    value: state.position.inMilliseconds.clamp(0, state.current!.duration.inMilliseconds).toDouble(),
                    max: state.current!.duration.inMilliseconds == 0 ? 1 : state.current!.duration.inMilliseconds.toDouble(),
                    onChanged: (v) => ctrl.seek(Duration(milliseconds: v.toInt())),
                  ),
                ],
                const SizedBox(height: 12),
                if (display.previewUrl != null)
                  Text('Preview URL: ${display.previewUrl}', maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
