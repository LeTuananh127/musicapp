import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/recommendation_repository.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../recommend/presentation/virtual_playlist_screen.dart';

class MoodChatWidget extends ConsumerStatefulWidget {
  const MoodChatWidget({super.key});

  @override
  ConsumerState<MoodChatWidget> createState() => _MoodChatWidgetState();
}

class _MoodChatWidgetState extends ConsumerState<MoodChatWidget> {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = false;
  String? _mood;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  Future<void> _ask() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _loading = true; _mood = null; _results = []; _error = null; });
    try {
      // For demo: fetch a short set of candidate tracks from the backend
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      List candidates = [];
      // First, try to ask the backend to scan the DB and return results server-side
      // This avoids sending thousands of candidates from the client.
      try {
        final resp = await dio.post('$base/mood/recommend/from_db', data: {'user_text': text, 'top_k': 50, 'limit': 10000});
        if (resp.statusCode == 200 && resp.data is Map) {
          final Map data = Map<String, dynamic>.from(resp.data as Map);
          candidates = data['candidates'] is List ? data['candidates'] as List : (data['value'] ?? []);
        }
      } catch (e) {
        // ignore and fall back to retrieving a small sample or local list
      }

      if (candidates.isEmpty) {
        try {
          final r = await dio.get('$base/tracks/sample_for_mood');
          candidates = r.data is List ? r.data : r.data['value'] ?? r.data;
        } catch (e) {
          // backend sample endpoint not available — fall back to small static list
          candidates = [
            {'id': 21, 'title': 'My MP3 Track', 'valence': 0.9, 'arousal': 0.2, 'preview_url': '/tracks/21/preview', 'cover_url': '/static/covers/21.jpg'},
            {'id': 241068, 'title': 'There Was a Time', 'valence': 0.2, 'arousal': 0.9, 'preview_url': null, 'cover_url': null},
            {'id': 240652, 'title': 'Be Still', 'valence': 0.2, 'arousal': 0.1, 'preview_url': null, 'cover_url': null},
            {'id': 240645, 'title': 'The Bridge', 'valence': 0.8, 'arousal': 0.3, 'preview_url': null, 'cover_url': null},
          ];
          // note the fallback to help debugging
          try { debugPrint('MoodChatWidget: using local fallback candidates'); } catch (_) {}
        }
      }
      // helper to normalize preview/cover URLs so relative paths like '/static/...' become absolute
      String? normalizeUrl(String? raw) {
        if (raw == null) return null;
        final s = raw.toString();
        if (s.isEmpty) return null;
        if (s.startsWith('http')) return s;
        // if the API returned a path like '/static/..' or 'static/..' or '/tracks/..',
        // ensure we prefix with base (backend api url)
        return '$base${s.startsWith('/') ? '' : '/'}$s';
      }

      final candidateTracks = candidates.map((e) => {
        'id': e['id'],
        'title': e['title'],
        'valence': e['valence'] ?? 0.5,
        'arousal': e['arousal'] ?? 0.5,
        'preview_url': normalizeUrl(e['preview_url'] ?? e['preview']),
        'cover_url': normalizeUrl(e['cover_url'] ?? e['cover'] ?? e['album_cover_url']),
      }).toList().cast<Map<String, dynamic>>();

      final repo = ref.read(recommendationRepositoryProvider);
      Map<String, dynamic>? resp;
      try {
        resp = await repo.recommendByMood(text, candidateTracks, topK: 20);
      } catch (e) {
        // server offline or API error — fall back to simple client-side selection
        try { debugPrint('MoodChatWidget: recommendByMood failed: $e'); } catch (_) {}
        resp = null;
      }

      if (resp != null) {
        setState(() { _mood = resp!['mood'] as String?; _results = List<Map<String, dynamic>>.from(resp!['candidates'] ?? []); });
      } else {
        // client-side fallback: heuristic mapping and filter local candidates
        final mood = _heuristicMoodFromText(text);
        final filtered = candidateTracks.where((c) {
          final m = _mapNumericToMood((c['valence'] as num).toDouble(), (c['arousal'] as num).toDouble());
          return m == mood;
        }).toList();
        setState(() { _mood = mood; _results = filtered; _error = 'Used local fallback (server unavailable)'; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _heuristicMoodFromText(String text) {
    final t = text.toLowerCase();
    if (t.contains('vui') || t.contains('happy') || t.contains('energetic') || t.contains('năng lượng')) return 'energetic';
    if (t.contains('thư giãn') || t.contains('chill') || t.contains('relax')) return 'relaxed';
    if (t.contains('giận') || t.contains('angry') || t.contains('hard') || t.contains('rock')) return 'angry';
    if (t.contains('buồn') || t.contains('sad') || t.contains('melanch')) return 'sad';
    return 'relaxed';
  }

  String _mapNumericToMood(double v, double a) {
    if (v >= 0.5 && a >= 0.5) return 'energetic';
    if (v >= 0.5 && a < 0.5) return 'relaxed';
    if (v < 0.5 && a >= 0.5) return 'angry';
    return 'sad';
  }

  @override
  Widget build(BuildContext context) {
    // Add outer padding so content is not hidden by the rounded modal top or system UI
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: <Widget>[
            // Input row
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: InputDecoration(
                      hintText: 'Hôm nay bạn muốn nghe thế nào?',
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: _loading
                      ? const SizedBox(width: 36, height: 36, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.send), onPressed: _ask),
                ),
              ],
            ),

            // Error / mood / help text
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Lỗi: $_error', style: const TextStyle(color: Colors.red)),
              ),

            if (_mood != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Detected mood: $_mood', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),

            if (!_loading && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: const <Widget>[
                    Text('Gợi ý sẽ hiện tại đây.'),
                    SizedBox(height: 8),
                    Text('Nhập mô tả ngắn (ví dụ: "chill", "muốn nghe EDM") và nhấn gửi để nhận playlist'),
                  ],
                ),
              ),

            // Results list
            if (_results.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final t = _results[i];
                    return ListTile(
                      leading: SizedBox(
                        width: 56,
                        height: 56,
                        child: t['cover_url'] != null
                            ? ClipOval(
                                child: Image.network(
                                  t['cover_url'],
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(width: 48, height: 48, color: Colors.grey.shade200),
                                ),
                              )
                            : const Center(child: Icon(Icons.music_note)),
                      ),
                      title: Text(t['title'] ?? 'Track'),
                      subtitle: t['predicted_mood'] != null ? Text('Mood: ${t['predicted_mood']}') : null,
                      onTap: () {
                        // open as virtual playlist containing this and neighbors
                        final tracks = _results
                            .map((e) => {
                                  'id': e['id'],
                                  'title': e['title'],
                                  'artist_name': e['artist_name'] ?? '',
                                  'duration_ms': e['duration_ms'] ?? 30000,
                                  'preview_url': e['preview_url'],
                                  'cover_url': e['cover_url'],
                                })
                            .toList();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => VirtualPlaylistScreen(tracks: tracks, title: 'For you ($_mood)')));
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
