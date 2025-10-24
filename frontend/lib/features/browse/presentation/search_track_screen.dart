import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../../data/models/track.dart';
import '../../../features/player/application/player_providers.dart';

class SearchTrackScreen extends ConsumerStatefulWidget {
  const SearchTrackScreen({super.key});
  @override
  ConsumerState<SearchTrackScreen> createState() => _SearchTrackScreenState();
}

class _SearchTrackScreenState extends ConsumerState<SearchTrackScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _results = [];
  String? _error;
  final ScrollController _scroll = ScrollController();
  int _offset = 0;
  final int _pageSize = 25;
  bool _hasMore = true;
  bool _loadingMore = false;
  Timer? _debounce;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true; _error = null; _results = []; _offset = 0; _hasMore = true;
    });
    await _loadPage(q);
    setState(() { _loading = false; });
  }

  Future<void> _loadPage(String q) async {
    if (!_hasMore) return;
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;
      final res = await dio.get('$base/tracks/search', queryParameters: {'q': q, 'limit': _pageSize, 'offset': _offset});
      final data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      final list = (data as List).map((e) {
        final rawPreview = e['preview_url'] ?? e['preview'];
        String? preview;
        if (rawPreview == null) {
          preview = null;
        } else {
          final rp = rawPreview.toString();
          if (rp.startsWith('http')) {
            if (rp.contains('cdnt-preview.dzcdn.net') || rp.contains('cdns-preview.dzcdn.net') || rp.contains('dzcdn.net')) {
              preview = '$base/deezer/stream/${e['id']}';
            } else {
              preview = rp;
            }
          } else {
            preview = base + rp;
          }
        }
        final rawCover = e['cover_url'] ?? e['cover'];
        final cover = rawCover == null ? null : (rawCover.toString().startsWith('http') ? rawCover : (base + rawCover.toString()));
        return {
          'id': e['id'],
          'title': e['title'],
          'artist': e['artist_name'] ?? e['artist'] ?? (e['artistName'] ?? ''),
          'duration_ms': e['duration_ms'] ?? e['duration'] ?? 0,
          'preview_url': preview,
          'cover_url': cover,
        };
      }).toList();
      setState(() {
        _results.addAll(List<Map<String, dynamic>>.from(list));
        _offset += (list as List).length;
        if ((list as List).length < _pageSize) _hasMore = false;
      });
    } catch (e) {
      setState(() { _error = 'Lỗi khi tìm kiếm'; });
    }
    _loadingMore = false;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tìm bài hát')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Nhập tên bài hát hoặc nghệ sĩ'),
              onSubmitted: (_) => _search(),
              onChanged: (s) {
                // debounce auto-search
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  final q = s.trim();
                  if (q.isEmpty) {
                    setState(() { _results = []; _hasMore = true; _offset = 0; });
                  } else {
                    _search();
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loading ? null : _search, child: const Text('Tìm')),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (sn) {
                  if (sn is ScrollEndNotification) {
                    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
                      final q = _ctrl.text.trim();
                      if (q.isNotEmpty) _loadPage(q);
                    }
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _results.length + (_hasMore ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (i >= _results.length) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                    final r = _results[i];
                    return ListTile(
                      leading: r['cover_url'] != null ? Image.network(r['cover_url'], width: 48, height: 48, fit: BoxFit.cover) : const Icon(Icons.music_note),
                      title: Text(r['title'] ?? ''),
                      subtitle: Text(r['artist'] ?? ''),
                      onTap: () {
                        final t = Track(
                          id: (r['id']).toString(),
                          title: r['title'] ?? 'Unknown',
                          artistName: r['artist'] ?? '',
                          durationMs: (r['duration_ms'] is int) ? r['duration_ms'] as int : (r['duration_ms'] is num ? (r['duration_ms'] as num).toInt() : 0),
                          previewUrl: r['preview_url'] as String?,
                          coverUrl: r['cover_url'] as String?,
                        );
                        try {
                          ref.read(playerControllerProvider.notifier).playTrack(t, origin: {'type': 'search', 'query': _ctrl.text.trim()});
                        } catch (_) {}
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
