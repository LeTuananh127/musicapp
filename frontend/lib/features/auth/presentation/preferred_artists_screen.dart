import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/dio_provider.dart';
import 'package:dio/dio.dart';
import '../../auth/application/auth_providers.dart';
import 'dart:async';

class PreferredArtistsScreen extends ConsumerStatefulWidget {
  const PreferredArtistsScreen({super.key});
  @override
  ConsumerState<PreferredArtistsScreen> createState() => _PreferredArtistsScreenState();
}

class _PreferredArtistsScreenState extends ConsumerState<PreferredArtistsScreen> {
  List<Map<String, dynamic>> _selected = [];
  List<Map<String, dynamic>> _artists = [];
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  int _offset = 0;
  final int _pageSize = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadPreferred();
    _fetchArtists();
    _searchCtrl.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        _offset = 0;
        _artists = [];
        _hasMore = true;
        _fetchArtists();
      });
    });
  }

  Future<void> _loadPreferred() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final res = await dio.get('${ref.read(appConfigProvider).apiBaseUrl}/users/me/preferences/artists', options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      final List ids = res.data is List ? res.data : res.data['value'] ?? [];
      _selected = ids.map((e) => {'id': e, 'name': 'Artist #$e'}).toList();
      setState(() {});
    } catch (e) {
      // ignore network errors for initial load; user can search to add artists
      // Optionally log error for debugging
      // print('preferred load error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _fetchArtists({bool loadMore = false}) async {
    if (!_hasMore && loadMore) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final q = _searchCtrl.text.trim();
      final res = await dio.get('${ref.read(appConfigProvider).apiBaseUrl}/artists', queryParameters: {'limit': _pageSize, 'offset': _offset, if (q.isNotEmpty) 'q': q});
      final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      final items = data.map((e) => {'id': e['id'], 'name': e['name']}).toList();
      if (loadMore) _artists.addAll(items);
      else _artists = items;
      _offset += items.length;
      if (items.length < _pageSize) _hasMore = false;
    } catch (e) {
      // ignore fetch errors for incremental loading
      // print('artists fetch error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      final ids = _selected.map((e) => e['id']).toList();
      await dio.post('${ref.read(appConfigProvider).apiBaseUrl}/users/me/preferences/artists', data: {'artist_ids': ids}, options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lưu thành công')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nghệ sĩ yêu thích')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(controller: _searchCtrl, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm nghệ sĩ')),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _artists.length + (_hasMore ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i >= _artists.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                  final a = _artists[i];
                  final selected = _selected.any((s) => s['id'] == a['id']);
                  return ListTile(
                    title: Text(a['name']),
                    trailing: IconButton(icon: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank), onPressed: () {
                      setState(() {
                        if (selected) _selected.removeWhere((s) => s['id'] == a['id']);
                        else _selected.add(a);
                      });
                    }),
                    onTap: () {
                      setState(() {
                        if (selected) _selected.removeWhere((s) => s['id'] == a['id']);
                        else _selected.add(a);
                      });
                    },
                  );
                },
              ),
            ),
            ElevatedButton(onPressed: _loading ? null : _save, child: const Text('Lưu')),
          ],
        ),
      ),
    );
  }
}
