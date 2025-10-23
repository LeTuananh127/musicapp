import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/like_repository.dart';
import '../../../data/repositories/track_repository.dart';
import '../../../data/models/track.dart';

final likedTracksProvider = StateNotifierProvider<LikedTracksController, Set<int>>((ref) {
  final repo = ref.watch(likeRepositoryProvider);
  return LikedTracksController(ref, repo);
});

class LikedTracksController extends StateNotifier<Set<int>> {
  final Ref ref;
  final ILikeRepository repo;
  bool _loaded = false;
  LikedTracksController(this.ref, this.repo) : super({});

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final liked = await repo.fetchLiked();
    state = liked;
    _loaded = true;
  }

  Future<void> toggle(int trackId) async {
    await ensureLoaded();
    final current = Set<int>.from(state);
    final isLiked = current.contains(trackId);
    // optimistic
    if (isLiked) {
      current.remove(trackId);
      state = current;
      try {
        await repo.unlike(trackId);
      } catch (_) {
        // rollback
        current.add(trackId);
        state = current;
      }
    } else {
      current.add(trackId);
      state = current;
      try {
        await repo.like(trackId);
      } catch (_) {
        current.remove(trackId);
        state = current;
      }
    }
  }

  /// Clear local liked state (used on logout to avoid leaking previous user's likes)
  Future<void> clear() async {
    state = {};
    _loaded = false;
  }
}

// Derived provider: fetch full track objects for liked IDs (simple approach: fetchAll then filter)
final likedTracksListProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final likedIds = ref.watch(likedTracksProvider);
  if (likedIds.isEmpty) return <Track>[];
  final repo = ref.watch(trackRepositoryProvider);
  // naive: fetch all then filter; later could add endpoint /tracks?ids=
  final all = await repo.fetchAll();
  return all.where((t) => likedIds.contains(int.tryParse(t.id) ?? -1)).toList();
});
