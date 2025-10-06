import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/dio_provider.dart';

abstract class IInteractionRepository {
  Future<void> logPlay({required int trackId, required int seconds, bool completed = false, int? milestone});
}

class InteractionRepository implements IInteractionRepository {
  final Dio _dio; final String baseUrl;
  InteractionRepository(this._dio, this.baseUrl);

  @override
  Future<void> logPlay({required int trackId, required int seconds, bool completed = false, int? milestone}) async {
    try {
      final body = {
        'track_id': trackId,
        'seconds_listened': seconds,
        'is_completed': completed,
        'device': 'app',
        'context_type': 'manual',
      };
      if (milestone != null) body['milestone'] = milestone;
      await _dio.post('$baseUrl/interactions/', data: body);
    } catch (_) {
      // swallow for now; could queue for retry
    }
  }
}

final interactionRepositoryProvider = Provider<IInteractionRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final cfg = ref.watch(appConfigProvider);
  return InteractionRepository(dio, cfg.apiBaseUrl);
});
