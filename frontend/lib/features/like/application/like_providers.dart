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
    // Only increment counter - no need to invalidate (causes CircularDependencyError)
    Future.microtask(() {
      ref.read(likedTracksRefreshProvider.notifier).state++;
    });
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
        // Update state after API success - this will trigger likedTracksListProvider rebuild
        current.remove(trackId);
        state = current;
        print('  → Updated state after unlike: $state');
        // Only increment counter - no need to invalidate (causes CircularDependencyError)
        Future.microtask(() {
          final oldCount = ref.read(likedTracksRefreshProvider);
          ref.read(likedTracksRefreshProvider.notifier).state++;
          print('  🔄 Incremented counter: $oldCount → ${ref.read(likedTracksRefreshProvider)}');
        });
      } catch (e) {
        print('  ❌ Unlike API failed: $e');
        // Don't change state on error
      }
    } else {
      // Like flow
      try {
        await repo.like(trackId);
        print('  ✅ Like API success');
        // Update state after API success - this will trigger likedTracksListProvider rebuild
        current.add(trackId);
        state = current;
        print('  → Updated state after like: $state');
        // Only increment counter - no need to invalidate (causes CircularDependencyError)
        Future.microtask(() {
          final oldCount = ref.read(likedTracksRefreshProvider);
          ref.read(likedTracksRefreshProvider.notifier).state++;
          print('  🔄 Incremented counter: $oldCount → ${ref.read(likedTracksRefreshProvider)}');
        });
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
// Using refresh counter to force rebuild when data changes
// Make this public so UI can watch it to trigger rebuild
final likedTracksRefreshProvider = StateProvider<int>((ref) => 0);

final likedTracksListProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  // Keep alive to prevent auto-dispose
  ref.keepAlive();
  
  // Watch refresh counter to bust cache - this FORCES rebuild
  final refreshCount = ref.watch(likedTracksRefreshProvider);
  final likedIds = ref.watch(likedTracksProvider);
  print('🔄 likedTracksListProvider rebuilding (refresh #$refreshCount) with ${likedIds.length} liked IDs: $likedIds');
  
  if (likedIds.isEmpty) return <Track>[];
  final repo = ref.watch(trackRepositoryProvider);

  // Fetch each track by ID instead of fetchAll (which has limit)
  // Parallelize requests for better latency and then sort by id desc for stable order
  final ids = likedIds.toList()..sort((a, b) => b.compareTo(a));
  final futures = ids.map((id) async {
    try {
      return await repo.getById(id);
    } catch (e) {
      print('❌ Error fetching track $id: $e');
      return null;
    }
  }).toList();

  final resolved = await Future.wait(futures);
  final tracks = resolved.whereType<Track>().toList();

  print('✅ likedTracksListProvider returning ${tracks.length} tracks: ${tracks.map((t) => t.id).toList()}');
  return tracks;
});
