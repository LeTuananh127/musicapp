import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'features/auth/application/auth_providers.dart';

/// Ensure the auth token is loaded from secure storage before the app starts
/// so that Dio interceptors can attach Authorization headers on first requests.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create a ProviderContainer so we can call the auth loader before runApp
  final container = ProviderContainer();
  // Load auth token (reads secure storage and updates state)
  await container.read(authControllerProvider.notifier).loadFromStorage();

  runApp(UncontrolledProviderScope(container: container, child: const AppRoot()));
}

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = AppRouter.create(ref);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Music App',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}
