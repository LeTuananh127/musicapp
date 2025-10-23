import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/providers/dio_provider.dart';

abstract class IInteractionRepository {
  Future<void> logPlay({required int trackId, required int seconds, bool completed = false, int? milestone});
  Future<void> logExternalPlay({required String externalTrackId, required int seconds, bool completed = false, int? milestone});
  Future<void> flushQueue();
  Future<void> clearQueue();
}

class InteractionRepository implements IInteractionRepository {
  final Dio _dio; final String baseUrl;
  InteractionRepository(this._dio, this.baseUrl);
  static const _queueKey = 'interaction_queue_v1';

  Future<void> _enqueue(Map<String, dynamic> body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      final list = raw == null ? <String>[] : List<String>.from(jsonDecode(raw) as List);
      list.add(jsonEncode(body));
      await prefs.setString(_queueKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      final list = List<String>.from(jsonDecode(raw) as List);
      return list.map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }

  /// Public clear for client-initiated wipes (e.g., logout)
  Future<void> clearQueue() async {
    await _clearQueue();
  }

  @override
  Future<void> logPlay({required int trackId, required int seconds, bool completed = false, int? milestone}) async {
    final body = {
      'track_id': trackId,
      'seconds_listened': seconds,
      'is_completed': completed,
      'device': 'app',
      'context_type': 'manual',
    };
    if (milestone != null) body['milestone'] = milestone;
    try {
      final res = await _dio.post('$baseUrl/interactions/', data: body);
      // If server responds with non-2xx (e.g., 401/403/404) enqueue for retry later
      if (res.statusCode == null || res.statusCode! < 200 || res.statusCode! >= 300) {
        await _enqueue(body);
        return;
      }
    } catch (_) {
      // Network or other error: enqueue for retry
      try {
        await _enqueue(body);
      } catch (_) {}
    }
  }

  @override
  Future<void> logExternalPlay({required String externalTrackId, required int seconds, bool completed = false, int? milestone}) async {
    final body = {
      'external_track_id': externalTrackId,
      'seconds_listened': seconds,
      'is_completed': completed,
      'device': 'app',
      'context_type': 'manual',
    };
    if (milestone != null) body['milestone'] = milestone;
    try {
      final res = await _dio.post('$baseUrl/interactions/external', data: body);
      if (res.statusCode == null || res.statusCode! < 200 || res.statusCode! >= 300) {
        await _enqueue({'_external': true, '_body': body});
        return;
      }
    } catch (_) {
      try {
        await _enqueue({'_external': true, '_body': body});
      } catch (_) {}
    }
  }

  @override
  Future<void> flushQueue() async {
    final queued = await _readQueue();
    if (queued.isEmpty) return;
    for (final raw in queued) {
      try {
        if (raw.containsKey('_external') && raw['_external'] == true) {
          final body = Map<String, dynamic>.from(raw['_body'] as Map);
          final res = await _dio.post('$baseUrl/interactions/external', data: body);
          if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) continue;
        } else {
          final res = await _dio.post('$baseUrl/interactions/', data: raw);
          if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) continue;
        }
      } catch (_) {}
    }
    // Clear queue after attempt (we could keep failed ones but keep it simple)
    await _clearQueue();
  }
}

final interactionRepositoryProvider = Provider<IInteractionRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final cfg = ref.watch(appConfigProvider);
  return InteractionRepository(dio, cfg.apiBaseUrl);
});
