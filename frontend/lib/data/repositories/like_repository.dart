import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/dio_provider.dart';

abstract class ILikeRepository {
  Future<Set<int>> fetchLiked();
  Future<void> like(int trackId);
  Future<void> unlike(int trackId);
}

class LikeRepository implements ILikeRepository {
  final Dio _dio;
  final String baseUrl;
  LikeRepository(this._dio, this.baseUrl);

  @override
  Future<Set<int>> fetchLiked() async {
    final res = await _dio.get('$baseUrl/tracks/liked');
    if (res.statusCode != 200) return {};
    final data = res.data;
    // Backend historically returned a raw list of ids (e.g. [1,2,3])
    // Older client expected { liked: [...] }. Accept both shapes for compatibility.
    if (data is List) {
      return data.map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toSet();
    }
    if (data is Map && data['liked'] is List) {
      return (data['liked'] as List).map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toSet();
    }
    return {};
  }

  @override
  Future<void> like(int trackId) async {
    await _dio.post('$baseUrl/tracks/$trackId/like');
  }

  @override
  Future<void> unlike(int trackId) async {
    await _dio.delete('$baseUrl/tracks/$trackId/like');
  }
}

final likeRepositoryProvider = Provider<ILikeRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final cfg = ref.watch(appConfigProvider);
  return LikeRepository(dio, cfg.apiBaseUrl);
});