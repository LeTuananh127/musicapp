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
  // ids currently animating (fading out) after tap
  final Set<int> _fading = {};
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
    // Map artist items; prefer cover_url if present
    final items = data
      .map((e) => {
        'id': e['id'],
        'name': e['name'] ?? e['title'] ?? 'Unknown',
        'cover_url': e['cover_url'] ?? e['cover'] ?? e['image'] ?? null,
        })
      .toList();
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

  String? _resolveMediaUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }

  // previous toggle behavior removed — UX uses tap-to-select-and-remove

  void _selectAndRemove(int id) async {
    if (_selected.contains(id) || _fading.contains(id)) return;
    setState(() => _fading.add(id));
    // short fade animation then remove from grid and mark selected
    await Future.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() {
      _fading.remove(id);
      _selected.add(id);
      _artists.removeWhere((a) => (a['id'] as int) == id);
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
    if (context.mounted) {
      context.go('/recommend');
    }
  }
    } catch (e) {
      setState(() => _error = 'Gửi lựa chọn thất bại');
    }
    setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Chọn nghệ sĩ yêu thích')),
      body: SafeArea(
        child: Padding(
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
                  : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.9,
                            ),
                            itemCount: _artists.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= _artists.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                              final a = _artists[i];
                              final id = a['id'] as int;
                              final coverRaw = a['cover_url'] as String?;
                              final resolvedCover = _resolveMediaUrl(coverRaw);
                              return GestureDetector(
                                onTap: () => _selectAndRemove(id),
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      AnimatedOpacity(
                                        duration: const Duration(milliseconds: 300),
                                        opacity: _fading.contains(id) ? 0.0 : 1.0,
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: Container(
                                            color: Colors.grey.shade200,
                                            child: resolvedCover != null
                                                ? ClipRRect(
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: Image.network(
                                                      resolvedCover,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                                    ),
                                                  )
                                                : const Center(child: Icon(Icons.person, size: 40, color: Colors.black45)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      AnimatedOpacity(
                                        duration: const Duration(milliseconds: 260),
                                        opacity: _fading.contains(id) ? 0.0 : 1.0,
                                        child: Text(a['name'], maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(onPressed: _loading ? null : _submit, child: const Text('Hoàn tất')),
          ),
        ),
      ),
    );

  }

  // Helper to compute threshold close to max scroll extent to trigger loadMore safely
  double _scroll_controller_maxExtentThreshold() {
    try {
      return _scrollController.position.maxScrollExtent - 200;
    } catch (_) {
      return double.infinity;
    }
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
