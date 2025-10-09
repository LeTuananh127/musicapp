import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../features/browse/presentation/home_screen.dart';
import '../../features/browse/presentation/deezer_screen.dart';
import '../../features/recommend/presentation/recommend_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/playlist/presentation/playlist_screen.dart';
import '../../features/playlist/presentation/playlist_detail_screen.dart';
import '../../features/player/presentation/mini_player_bar.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/player/presentation/queue_screen.dart';

class ShellScaffold extends ConsumerWidget {
  final Widget child;
  const ShellScaffold({super.key, required this.child});

  int _indexForLocation(String location) {
    if (location.startsWith('/recommend')) return 1;
    if (location.startsWith('/playlists')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(loc);
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          const MiniPlayerBar(),
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
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'For You'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), label: 'Playlists'),
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
          if (!auth.isAuthed) {
            return loggingIn ? null : '/login';
          }
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
              GoRoute(path: '/recommend', builder: (c, s) => const RecommendScreen()),
              GoRoute(path: '/playlists', builder: (c, s) => const PlaylistScreen()),
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
            ],
          ),
          // Fullscreen overlays outside bottom nav shell
          GoRoute(path: '/now-playing', builder: (c, s) => const NowPlayingScreen()),
          GoRoute(path: '/queue', builder: (c, s) => const QueueScreen()),
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
