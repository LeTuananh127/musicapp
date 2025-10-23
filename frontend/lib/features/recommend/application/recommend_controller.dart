import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/recommendation_repository.dart';
import '../../auth/application/auth_providers.dart';

final recommendedTracksProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final repo = ref.watch(recommendationRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final uid = auth.userId ?? 1; // fallback 1
  return repo.recommendForUser(uid, limit: 5);
});

// Temporary provider to hold playlist suggestions produced by onboarding flow.
final onboardingPlaylistsProvider = StateProvider<List<Map<String, dynamic>>?>((ref) => null);
