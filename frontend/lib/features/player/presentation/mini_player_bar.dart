import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/player_providers.dart';
// queue_screen not used in compact mode

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final track = state.current;
    if (track == null) return const SizedBox.shrink();
    final dur = Duration(milliseconds: track.durationMs);
    final pos = state.position;
  String fmtTime(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
        child: InkWell(
          // Use push so the track detail is pushed onto the navigation stack.
          // This ensures the Back button pops back to the previous screen
          // instead of replacing the route (which could lead to Home).
          onTap: () => context.push('/track/${track.id}'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(fmtTime(pos), style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              minThumbSeparation: 0,
                            ),
                            child: Slider(
                              value: pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                              max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
                              onChanged: (v) => ctrl.seek(Duration(milliseconds: v.toInt())),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(fmtTime(dur), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            _MiniPlayerControls(state: state, ctrl: ctrl),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerControls extends StatelessWidget {
  final dynamic state; // PlayerStateModel
  final dynamic ctrl;  // PlayerController
  const _MiniPlayerControls({required this.state, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    // Dùng Wrap để tự xuống hàng nếu màn hình quá hẹp / text scale lớn
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _icon(context, icon: Icons.skip_previous, onPressed: state.hasPrevious ? ctrl.previous : null),
        _icon(context, icon: state.playing ? Icons.pause : Icons.play_arrow, onPressed: ctrl.togglePlay),
        _icon(context, icon: Icons.skip_next, onPressed: state.hasNext ? ctrl.next : null),
      ],
    );
  }

  Widget _icon(BuildContext context, {required IconData icon, VoidCallback? onPressed, Color? color}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: Icon(icon, size: 22, color: color),
      onPressed: onPressed,
    );
  }


}


