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
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        if (!_loading && _hasMore) _fetchArtists(loadMore: true);
      }
    });

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

  Future<void> _fetchArtists({bool loadMore = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final q = _searchCtrl.text.trim();
      final res = await dio.get(
        '${ref.read(appConfigProvider).apiBaseUrl}/artists',
        queryParameters: {
          'limit': _pageSize,
          'offset': _offset,
          if (q.isNotEmpty) 'q': q,
        },
      );

      final List data =
          res.data is Map ? res.data['value'] ?? res.data : res.data;

      final items = data
          .map((e) => {
                'id': e['id'],
                'name': e['name'] ?? 'Unknown',
                'cover_url': e['cover_url'] ?? e['image'] ?? null,
              })
          .toList();

      if (loadMore) {
        _artists.addAll(items);
      } else {
        _artists = items;
      }

      _offset += items.length;
      if (items.length < _pageSize) _hasMore = false;
    } catch (_) {
      _error = 'Không tải được danh sách nghệ sĩ';
    }

    setState(() => _loading = false);
  }

  String? _resolveMediaUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }

  void _selectAndRemove(int id) async {
    if (_selected.contains(id) || _fading.contains(id)) return;
    setState(() => _fading.add(id));
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

    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final auth = ref.read(authControllerProvider);
      await dio.post(
        '${ref.read(appConfigProvider).apiBaseUrl}/users/me/preferences/artists',
        data: {'artist_ids': _selected},
        options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}),
      );

      final artistParam = _selected.join(',');
      final res = await dio.get(
        '${ref.read(appConfigProvider).apiBaseUrl}/recommend/playlists',
        queryParameters: {'artists': artistParam},
      );

      final List data =
          res.data is Map ? res.data['value'] ?? res.data : res.data;
      final playlists = data
          .map((e) => {
                'id': e['id'],
                'name': e['name'],
                'score': e['score'],
              })
          .toList();

      ref.read(onboardingPlaylistsProvider.notifier).state = playlists;
      await ref.read(authControllerProvider.notifier).completeOnboarding();

      if (mounted) {
        context.go('/recommend');
      }
    } catch (_) {
      setState(() => _error = 'Gửi lựa chọn thất bại');
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Chọn nghệ sĩ yêu thích')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Text(
                'Chọn ít nhất 3 nghệ sĩ bạn thích để nhận gợi ý phù hợp',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm nghệ sĩ...',
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              Expanded(
                child: _artists.isEmpty && _loading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverPadding(
                            padding:
                                EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
                            sliver: SliverGrid.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                                childAspectRatio: 0.9, // ✅ Fix tràn chiều cao
                              ),
                              itemCount: _artists.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= _artists.length) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }

                                final a = _artists[i];
                                final id = a['id'] as int;
                                final cover = _resolveMediaUrl(a['cover_url']);

                                return GestureDetector(
                                  onTap: () => _selectAndRemove(id),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 300),
                                    opacity: _fading.contains(id) ? 0 : 1,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Container(
                                              color: Colors.grey.shade200,
                                              child: cover != null
                                                  ? Image.network(
                                                      cover,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(
                                                      Icons.person,
                                                      size: 40,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Flexible(
                                          child: Text(
                                            a['name'],
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
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
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: const Text('Hoàn tất'),
            ),
          ),
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
