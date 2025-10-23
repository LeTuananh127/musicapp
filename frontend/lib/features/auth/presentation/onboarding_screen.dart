import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../recommend/application/recommend_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final List<int> _selected = [];
  List<Map<String, dynamic>> _artists = [];
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _offset = 0;
  final int _pageSize = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchArtists();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 200) {
        if (!_loading && _hasMore) _fetchArtists(loadMore: true);
      }
    });
    _searchCtrl.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        // new search
        _offset = 0;
        _artists = [];
        _hasMore = true;
        _fetchArtists();
      });
    });
  }

  Future<void> _fetchArtists({bool loadMore = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      setState(() => _loading = true);
      final dio = ref.read(dioProvider);
      final q = _searchCtrl.text.trim();
      final res = await dio.get('${ref.read(appConfigProvider).apiBaseUrl}/artists', queryParameters: {
        'limit': _pageSize,
        'offset': _offset,
        if (q.isNotEmpty) 'q': q,
      });
      final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
      final items = data.map((e) => {'id': e['id'], 'name': e['name'] ?? e['title'] ?? 'Unknown'}).toList();
      if (loadMore) { // Added loadMore parameter to the method signature
        _artists.addAll(items);
      } else {
        _artists = items;
      }
      _offset += items.length;
      if (items.length < _pageSize) _hasMore = false;
    } catch (e) {
      _error = 'Không tải được danh sách nghệ sĩ';
    }
    setState(() { _loading = false; });
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) _selected.remove(id);
      else _selected.add(id);
    });
  }

  Future<void> _submit() async {
    if (_selected.length < 3) {
      setState(() => _error = 'Vui lòng chọn ít nhất 3 nghệ sĩ');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      await dio.post('${ref.read(appConfigProvider).apiBaseUrl}/users/me/preferences/artists',
          data: {'artist_ids': _selected}, options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}));
  // After saving preferences, fetch playlist recommendations and show results
  final artistParam = _selected.join(',');
  final res = await dio.get('${ref.read(appConfigProvider).apiBaseUrl}/recommend/playlists', queryParameters: {'artists': artistParam});
  final List data = res.data is Map ? res.data['value'] ?? res.data : res.data;
  final playlists = data.map((e) => {'id': e['id'], 'name': e['name'], 'score': e['score']}).toList();
  // store in provider so RecommendScreen can render them
  ref.read(onboardingPlaylistsProvider.notifier).state = playlists;
  // Mark onboarding as completed so router/redirect won't override navigation
  try {
    await ref.read(authControllerProvider.notifier).completeOnboarding();
  } catch (_) {}
  // Show a short debug snackbar with the number of playlists suggested
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${playlists.length} playlist(s) suggested'),
      duration: const Duration(seconds: 2),
    ));
  }
  if (context.mounted) context.go('/recommend');
    } catch (e) {
      setState(() => _error = 'Gửi lựa chọn thất bại');
    }
    setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn nghệ sĩ yêu thích')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            const Text('Chọn ít nhất 3 nghệ sĩ bạn thích để nhận gợi ý phù hợp', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm nghệ sĩ...'),
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _artists.isEmpty && _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _artists.length + (_hasMore ? 1 : 0),
                      itemBuilder: (c, i) {
                        if (i >= _artists.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                        final a = _artists[i];
                        final id = a['id'] as int;
                        final selected = _selected.contains(id);
                        return ListTile(
                          title: Text(a['name']),
                          trailing: IconButton(
                            icon: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank),
                            onPressed: () => _toggle(id),
                          ),
                          onTap: () => _toggle(id),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loading ? null : _submit, child: const Text('Hoàn tất'))
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
