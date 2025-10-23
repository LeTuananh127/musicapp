import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../features/browse/presentation/home_screen.dart';
import '../../features/browse/presentation/deezer_screen.dart';
import '../../features/browse/presentation/track_detail_screen.dart';
import '../../features/recommend/presentation/recommend_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/auth/presentation/preferred_artists_screen.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/playlist/presentation/playlist_screen.dart';
import '../../features/playlist/presentation/playlist_detail_screen.dart';
import '../../features/recommend/presentation/artist_tracks_screen.dart';
import '../../features/recommend/presentation/virtual_playlist_screen.dart';
import '../../features/player/presentation/mini_player_bar.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/player/presentation/queue_screen.dart';
import '../../features/browse/presentation/search_track_screen.dart';

class ShellScaffold extends ConsumerWidget {
  final Widget child;
  const ShellScaffold({super.key, required this.child});

  int _indexForLocation(String location) {
    if (location.startsWith('/recommend')) return 1;
    if (location.startsWith('/playlists')) return 2;
    if (location.startsWith('/search')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(loc);
    final showMiniBar = !loc.startsWith('/track');
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          if (showMiniBar) const MiniPlayerBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/recommend');
              break;
            case 2:
              context.go('/playlists');
              break;
              case 3:
                context.go('/search');
                break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'For You'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), label: 'Playlists'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        ],
      ),
    );
  }
}

class AppRouter {
  static GoRouter create(WidgetRef ref) => GoRouter(
        initialLocation: '/home',
        refreshListenable: GoRouterRefreshStream(ref.watch(authControllerProvider.notifier).stream),
        redirect: (context, state) {
          final auth = ref.read(authControllerProvider);
          final loggingIn = state.matchedLocation == '/login';
          final onOnboarding = state.matchedLocation == '/onboarding';
          if (!auth.isAuthed) {
            return loggingIn ? null : '/login';
          }
          // If the just-registered user still needs onboarding, ensure they land on /onboarding
          if (auth.needsOnboarding && !onOnboarding) return '/onboarding';
          if (loggingIn && auth.isAuthed) return '/home';
          return null;
        },
        routes: [
          GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
          ShellRoute(
            builder: (context, state, child) => ShellScaffold(child: child),
            routes: [
              GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
              GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
              GoRoute(path: '/deezer', builder: (c, s) => const DeezerScreen()),
              GoRoute(path: '/recommend', builder: (c, s) {
                final extra = s.extra as Map<String, dynamic>?;
                final playlists = (extra != null && extra['playlists'] is List)
                    ? List<Map<String, dynamic>>.from(extra['playlists'])
                    : null;
                return RecommendScreen(playlists: playlists);
              }),
              GoRoute(path: '/playlists', builder: (c, s) => const PlaylistScreen()),
              GoRoute(path: '/search', builder: (c, s) => const SearchTrackScreen()),
              GoRoute(path: '/preferred-artists', builder: (c, s) => const PreferredArtistsScreen()),
              GoRoute(path: '/artist-tracks', builder: (c, s) {
                final extra = s.extra as Map<String, dynamic>?;
                final ids = extra != null && extra['artistIds'] is List ? List<int>.from(extra['artistIds']) : <int>[];
                final title = extra != null && extra['title'] is String ? extra['title'] as String : 'Tracks';
                return ArtistTracksScreen(artistIds: ids, title: title);
              }),
              GoRoute(path: '/virtual-playlist', builder: (c, s) {
                final extra = s.extra as Map<String, dynamic>?;
                final ids = extra != null && extra['artistIds'] is List ? List<int>.from(extra['artistIds']) : <int>[];
                final title = extra != null && extra['title'] is String ? extra['title'] as String : 'Playlist';
                final tracks = extra != null && extra['tracks'] is List ? List<Map<String, dynamic>>.from(extra['tracks']) : null;
                return VirtualPlaylistScreen(artistIds: ids.isEmpty ? null : ids, tracks: tracks, title: title);
              }),
              GoRoute(
                path: '/playlists/:id',
                builder: (c, s) {
                  final idParam = s.pathParameters['id'];
                  final pid = int.tryParse(idParam ?? '');
                  if (pid == null) {
                    return const Scaffold(body: Center(child: Text('Invalid playlist id')));
                  }
                  return PlaylistDetailScreen(playlistId: pid);
                },
              ),
              GoRoute(
                path: '/track/:id',
                builder: (c, s) {
                  final idParam = s.pathParameters['id'];
                  final tid = int.tryParse(idParam ?? '');
                  if (tid == null) return const Scaffold(body: Center(child: Text('Invalid track id')));
                  return TrackDetailScreen(trackId: tid);
                },
              ),
            ],
          ),
          // Fullscreen overlays outside bottom nav shell
          GoRoute(path: '/now-playing', builder: (c, s) => const NowPlayingScreen()),
          GoRoute(path: '/queue', builder: (c, s) => const QueueScreen()),
          GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
          // onboarding-result route removed; RecommendScreen handles playlists via /recommend extra
        ],
      );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListener = () => notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListener());
  }
  late final VoidCallback notifyListener;
  late final StreamSubscription<dynamic> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
