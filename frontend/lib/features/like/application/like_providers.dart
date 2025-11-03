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
    print('🔄 Loading liked tracks from server...');
    final liked = await repo.fetchLiked();
    print('✅ Loaded ${liked.length} liked tracks: $liked');
    state = liked;
    _loaded = true;
  }

  /// Force reload from server (useful when returning to screen)
  Future<void> reload() async {
    print('🔄 Force reloading liked tracks from server...');
    final liked = await repo.fetchLiked();
    print('✅ Reloaded ${liked.length} liked tracks: $liked');
    state = liked;
    _loaded = true;
  }

  Future<void> toggle(int trackId) async {
    await ensureLoaded();
    final current = Set<int>.from(state);
    final isLiked = current.contains(trackId);
    print('❤️ Toggle like: trackId=$trackId, isLiked=$isLiked');
    
    if (isLiked) {
      // Unlike flow
      try {
        await repo.unlike(trackId);
        print('  ✅ Unlike API success');
        // Update state after API success
        current.remove(trackId);
        state = current;
        print('  → Updated state after unlike: $state');
        // Invalidate list provider to trigger refetch
        ref.invalidate(likedTracksListProvider);
      } catch (e) {
        print('  ❌ Unlike API failed: $e');
        // Don't change state on error
      }
    } else {
      // Like flow
      try {
        await repo.like(trackId);
        print('  ✅ Like API success');
        // Update state after API success
        current.add(trackId);
        state = current;
        print('  → Updated state after like: $state');
        // Invalidate list provider to trigger refetch
        ref.invalidate(likedTracksListProvider);
      } catch (e) {
        print('  ❌ Like API failed: $e');
        // Don't change state on error
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
  print('🔄 likedTracksListProvider rebuilding with ${likedIds.length} liked IDs');
  if (likedIds.isEmpty) return <Track>[];
  final repo = ref.watch(trackRepositoryProvider);
  // naive: fetch all then filter; later could add endpoint /tracks?ids=
  final all = await repo.fetchAll();
  final result = all.where((t) => likedIds.contains(int.tryParse(t.id) ?? -1)).toList();
  print('✅ likedTracksListProvider returning ${result.length} tracks');
  return result;
});
