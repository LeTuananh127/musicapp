import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/config/app_env.dart';
import '../services/http_client.dart';
import '../../features/auth/application/auth_providers.dart';

// Single source for config; no hard-coded localhost here.
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.dev);

final dioProvider = Provider((ref) {
  final cfg = ref.watch(appConfigProvider);
  final dio = HttpClientFactory.create(cfg.apiBaseUrl);
  dio.interceptors.add(
    InterceptorsWrapper(onRequest: (options, handler) {
      final auth = ref.read(authControllerProvider);
      if (auth.token != null) {
        options.headers['Authorization'] = 'Bearer ${auth.token}';
      }
      handler.next(options);
    }),
  );
  return dio;
});
