import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/dio_provider.dart';

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

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = null; _results = []; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('${ref.read(appConfigProvider).apiBaseUrl}/tracks/search', queryParameters: {'q': q, 'limit': 50});
      final data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      final list = (data as List).map((e) => {
        'id': e['id'],
        'title': e['title'],
        'artist': e['artist_name'] ?? e['artist'],
        'duration_ms': e['duration_ms'] ?? e['durationMs'] ?? 0,
        'preview_url': e['preview_url'] ?? e['preview'],
        'cover_url': e['cover_url'] ?? e['cover'],
      }).toList();
      setState(() { _results = List<Map<String, dynamic>>.from(list); });
    } catch (e) {
      setState(() { _error = 'L lỗi khi tìm kiếm'; });
    }
    setState(() { _loading = false; });
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loading ? null : _search, child: const Text('Tìm')),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (c, i) {
                  final r = _results[i];
                  return ListTile(
                    leading: r['cover_url'] != null ? Image.network(r['cover_url'], width: 48, height: 48, fit: BoxFit.cover) : const Icon(Icons.music_note),
                    title: Text(r['title'] ?? ''),
                    subtitle: Text(r['artist'] ?? ''),
                    onTap: () {
                      // TODO: play track or open detail
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
