import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/dio_provider.dart';

class ArtistTracksScreen extends ConsumerStatefulWidget {
  final List<int> artistIds;
  final String title;
  const ArtistTracksScreen({super.key, required this.artistIds, required this.title});

  @override
  ConsumerState<ArtistTracksScreen> createState() => _ArtistTracksScreenState();
}

class _ArtistTracksScreenState extends ConsumerState<ArtistTracksScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tracks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
  final base = ref.read(appConfigProvider).apiBaseUrl;
      final artistsParam = widget.artistIds.join(',');
      final res = await dio.get('$base/artists/tracks', queryParameters: {'artists': artistsParam});
      final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      setState(() {
        _tracks = data.map((e) => {
          'id': e['id'],
          'title': e['title'] ?? 'Track ${e['id']}',
          'artist_name': e['artist_name'] ?? '',
          'duration_ms': e['duration_ms'] ?? 0,
        }).toList().cast<Map<String, dynamic>>();
      });
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
    setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null
          ? Center(child: Text('Lỗi: \\$_error'))
          : _tracks.isEmpty ? const Center(child: Text('Không có bài hát'))
          : ListView.separated(
              itemCount: _tracks.length,
              separatorBuilder: (_,__) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final t = _tracks[i];
                return ListTile(
                  title: Text(t['title']),
                  subtitle: Text(t['artist_name']),
                );
              },
            ),
    );
  }
}
