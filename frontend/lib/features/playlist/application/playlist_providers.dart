import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/playlist_repository.dart';

final myPlaylistsProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.fetchMine();
});

class CreatePlaylistState {
  final bool loading;
  final String? error;
  CreatePlaylistState({this.loading = false, this.error});
  CreatePlaylistState copyWith({bool? loading, String? error}) =>
      CreatePlaylistState(loading: loading ?? this.loading, error: error);
}

class CreatePlaylistController extends StateNotifier<CreatePlaylistState> {
  final Ref ref;
  CreatePlaylistController(this.ref) : super(CreatePlaylistState());

  Future<bool> create(String name, {String? description}) async {
    state = state.copyWith(loading: true, error: null);
    final repo = ref.read(playlistRepositoryProvider);
    try {
      await repo.create(name, description: description);
      // refresh list
      ref.invalidate(myPlaylistsProvider);
      state = state.copyWith(loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }
}

final createPlaylistControllerProvider =
    StateNotifierProvider<CreatePlaylistController, CreatePlaylistState>((ref) => CreatePlaylistController(ref));

// Playlist detail providers
final playlistDetailProvider = FutureProvider.family.autoDispose((ref, int playlistId) async {
  final repo = ref.watch(playlistRepositoryProvider) as PlaylistRepository; // need concrete for new methods
  return repo.fetchDetail(playlistId);
});

final playlistTracksProvider = FutureProvider.family.autoDispose((ref, int playlistId) async {
  final repo = ref.watch(playlistRepositoryProvider) as PlaylistRepository;
  return repo.fetchTracks(playlistId);
});

// Track membership provider: which of user's playlists already contain the track
final trackPlaylistMembershipsProvider = FutureProvider.family.autoDispose<Set<int>, int>((ref, int trackId) async {
  final repo = ref.watch(playlistRepositoryProvider) as PlaylistRepository;
  return repo.fetchMemberships(trackId);
});

class PlaylistTrackRemoveController extends StateNotifier<AsyncValue<void>> {
  final Ref ref;
  final int playlistId;
  PlaylistTrackRemoveController(this.ref, this.playlistId) : super(const AsyncData(null));

  Future<void> remove(int trackId) async {
    state = const AsyncLoading();
    final repo = ref.read(playlistRepositoryProvider);
    try {
      await repo.removeTrack(playlistId, trackId);
      // invalidate tracks + detail for count update
      ref.invalidate(playlistTracksProvider(playlistId));
      ref.invalidate(playlistDetailProvider(playlistId));
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final playlistTrackRemoveControllerProvider = StateNotifierProvider.family<PlaylistTrackRemoveController, AsyncValue<void>, int>((ref, playlistId) {
  return PlaylistTrackRemoveController(ref, playlistId);
});
