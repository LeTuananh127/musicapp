import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/track.dart';
import '../../shared/providers/dio_provider.dart';
import 'track_repository.dart';

abstract class IRecommendationRepository {
  Future<List<Track>> recommendForUser(int userId, {int limit});
}

class RecommendationRepository implements IRecommendationRepository {
  final Dio _dio;
  final ITrackRepository trackRepo;
  final String baseUrl;
  RecommendationRepository(this._dio, this.trackRepo, this.baseUrl);

  @override
  Future<List<Track>> recommendForUser(int userId, {int limit = 10}) async {
    final res = await _dio.get('$baseUrl/recommend/user/$userId', queryParameters: {'limit': limit});
    if (res.statusCode == 200 && res.data is List) {
      final recs = <Track>[];
      final tracks = await trackRepo.fetchAll();
      for (final item in (res.data as List)) {
        final tid = item['track_id'];
        final t = tracks.firstWhere(
          (tr) => tr.id == tid.toString(),
          orElse: () => Track(id: tid.toString(), title: 'Track $tid', artistName: 'Unknown', durationMs: 0, previewUrl: null),
        );
        recs.add(t);
      }
      return recs;
    }
    return [];
  }
}

final recommendationRepositoryProvider = Provider<IRecommendationRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final trackRepo = ref.watch(trackRepositoryProvider);
  final cfg = ref.watch(appConfigProvider);
  return RecommendationRepository(dio, trackRepo, cfg.apiBaseUrl);
});
