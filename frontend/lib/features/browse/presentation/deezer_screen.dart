import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/data/deezer_service.dart';
import '../../../data/models/track.dart';
import '../../player/application/player_providers.dart';

class DeezerScreen extends ConsumerStatefulWidget {
  const DeezerScreen({super.key});

  @override
  ConsumerState<DeezerScreen> createState() => _DeezerScreenState();
}

class _DeezerScreenState extends ConsumerState<DeezerScreen> {
  final _svc = DeezerService('http://10.0.2.2:8000');
  final _controller = TextEditingController(text: 'test');
  List<dynamic> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() => _loading = true);
    List<dynamic>? found;
    Object? error;
    try {
      found = await _svc.search(_controller.text, limit: 10);
    } catch (e) {
      error = e;
    }

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $error')));
    } else {
      setState(() => _results = found ?? []);
    }
    setState(() => _loading = false);
  }

  Future<void> _playPreview(dynamic item) async {
    final id = item['id'];
    // Build a Track model that the global player controller understands.
    final durationSec = item['duration'] ?? 30;
    final t = Track(
      id: id.toString(),
      title: item['title'] ?? '',
      artistName: item['artist']?['name'] ?? '',
      durationMs: (durationSec as int) * 1000,
      albumId: item['album']?['id']?.toString(),
      previewUrl: 'http://10.0.2.2:8000/deezer/stream/$id',
  coverUrl: item['album']?['cover'],
    );

    try {
      // Use global player controller so mini player and queue update
      await ref.read(playerControllerProvider.notifier).playTrack(t);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Play failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deezer Search & Preview')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: TextField(controller: _controller)),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _search, child: const Text('Search')),
            ]),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (c, i) {
                  final it = _results[i];
                  return ListTile(
                    title: Text(it['title'] ?? ''),
                    subtitle: Text(it['artist']?['name'] ?? ''),
                    trailing: IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => _playPreview(it)),
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
