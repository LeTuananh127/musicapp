import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/app_env.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../data/auth_repository.dart';
import '../../like/application/like_providers.dart';
import '../../recommend/application/recommend_controller.dart';
import '../../player/application/player_providers.dart';

const _kTokenKey = 'auth_token';
const _kUserIdKey = 'auth_user_id';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final cfg = AppConfig.dev; // later dynamic
  return AuthRepository(dio, cfg.apiBaseUrl);
});

class AuthState {
  final String? token;
  final int? userId;
  final bool loading;
  final String? error;
  final String? displayName;
  final bool needsOnboarding;
  const AuthState({this.token, this.userId, this.loading = false, this.error, this.displayName, this.needsOnboarding = false});
  AuthState copyWith({String? token, int? userId, bool? loading, String? error, String? displayName, bool? needsOnboarding}) =>
      AuthState(token: token ?? this.token, userId: userId ?? this.userId, loading: loading ?? this.loading, error: error, displayName: displayName ?? this.displayName, needsOnboarding: needsOnboarding ?? this.needsOnboarding);
  bool get isAuthed => token != null && userId != null;
}

class AuthController extends StateNotifier<AuthState> {
  final Ref ref;
  AuthController(this.ref) : super(const AuthState());

  Future<void> loadFromStorage() async {
    final storage = ref.read(secureStorageProvider);
    final t = await storage.read(key: _kTokenKey);
    final uid = await storage.read(key: _kUserIdKey);
    if (t != null && uid != null) {
      state = state.copyWith(token: t, userId: int.tryParse(uid));
      // fetch profile
      final repo = ref.read(authRepositoryProvider);
      final me = await repo.me(t);
      if (me != null) {
        state = state.copyWith(displayName: me['display_name'] as String?);
      }
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    final repo = ref.read(authRepositoryProvider);
    try {
      final res = await repo.login(email, password);
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: _kTokenKey, value: res.token);
      await storage.write(key: _kUserIdKey, value: res.userId.toString());
  String? displayName;
  final me = await repo.me(res.token);
  if (me != null) displayName = me['display_name'] as String?;
      state = AuthState(token: res.token, userId: res.userId, loading: false, displayName: displayName);
      // Flush any queued interactions now that we have a valid token
      try {
        await ref.read(interactionRepositoryProvider).flushQueue();
      } catch (_) {}
      // Preload liked tracks so UI updates immediately after login
      try {
        await ref.read(likedTracksProvider.notifier).ensureLoaded();
      } catch (_) {}
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> register(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    final repo = ref.read(authRepositoryProvider);
    try {
      final res = await repo.register(email, password);
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: _kTokenKey, value: res.token);
      await storage.write(key: _kUserIdKey, value: res.userId.toString());
  String? displayName;
  final me = await repo.me(res.token);
  if (me != null) displayName = me['display_name'] as String?;
  // mark that this freshly-registered user still needs to complete onboarding
  state = AuthState(token: res.token, userId: res.userId, loading: false, displayName: displayName, needsOnboarding: true);
      // Flush queued interactions after register
      try {
        await ref.read(interactionRepositoryProvider).flushQueue();
      } catch (_) {}
      // Preload liked tracks after register
      try {
        await ref.read(likedTracksProvider.notifier).ensureLoaded();
      } catch (_) {}
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  /// Update local state for display name after server-side change.
  void setDisplayName(String? displayName) {
    state = state.copyWith(displayName: displayName);
  }

  /// Mark onboarding as completed on the client so router won't redirect away from onboarding flow.
  Future<void> completeOnboarding() async {
    state = state.copyWith(needsOnboarding: false);
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _kTokenKey);
    await storage.delete(key: _kUserIdKey);
    // Clear related client-side state to avoid leaking between accounts
    try {
      // Clear pending interaction queue
      await ref.read(interactionRepositoryProvider).clearQueue();
    } catch (_) {}
    try {
      await ref.read(likedTracksProvider.notifier).clear();
    } catch (_) {}
    try {
      // Stop playback and remove persisted player state so previous user's queue isn't restored
      await ref.read(playerControllerProvider.notifier).clearPersisted();
    } catch (_) {}
    // Clear onboarding playlist suggestions
    try {
      ref.read(onboardingPlaylistsProvider.notifier).state = null;
    } catch (_) {}
    state = const AuthState();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final c = AuthController(ref);
  c.loadFromStorage();
  return c;
});
