import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/recommendation_repository.dart';

final recommendationPlaylistProvider = FutureProvider.family<Map<String, dynamic>?, int>((ref, userId) async {
  final repo = ref.watch(recommendationRepositoryProvider);
  final playlist = await repo.recommendPlaylistForUser(userId, nTracks: 20);
  return playlist;
});
