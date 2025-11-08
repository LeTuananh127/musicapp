import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/providers/dio_provider.dart';
import 'package:dio/dio.dart';
import '../../auth/application/auth_providers.dart';

class PreferredArtistsScreen extends ConsumerStatefulWidget {
  const PreferredArtistsScreen({super.key});
  @override
  ConsumerState<PreferredArtistsScreen> createState() => _PreferredArtistsScreenState();
}

class _PreferredArtistsScreenState extends ConsumerState<PreferredArtistsScreen> {
  List<Map<String, dynamic>> _selected = [];
  List<Map<String, dynamic>> _available = [];
  // IDs as returned from server on last authoritative load
  Set<int> _serverSelectedIds = {};
  bool _loading = false;
  bool _saving = false;
  static const _kLocalPrefsKey = 'preferred_artists_cache_v2';

  @override
  void initState() {
    super.initState();
    _clearCacheThenLoad();
  }

  /// Clear cached preferred artists (local) and then load authoritative list
  Future<void> _clearCacheThenLoad() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kLocalPrefsKey);
    } catch (_) {
      // ignore errors when clearing cache
    }
    await _loadPreferred();
  }

  Future<void> _loadPreferred() async {
    setState(() => _loading = true);

    final dio = ref.read(dioProvider);
    final auth = ref.read(authControllerProvider);

    // Always fetch authoritative selection from server on screen load.
    // Do NOT use local cache as the primary source. If the network call
    // fails, we leave `_selected` empty so the UI reflects server state.
    try {
      final res = await dio.get(
        '${ref.read(appConfigProvider).apiBaseUrl}/users/me/preferences/artists',
        options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}),
      );

      final ids = List<int>.from(res.data);
      _serverSelectedIds = ids.toSet();
      await _fetchArtistsDetails(ids);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Failed to load preferred artists from server: $e');
      }
      // keep _selected as empty list — do not fallback to local cache
      _selected = [];
    }

    await _loadAvailableArtists();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchArtistsDetails(List<int> ids) async {
    if (ids.isEmpty) {
      _selected = [];
      return;
    }

    final dio = ref.read(dioProvider);

    try {
      final artistsRes = await dio.get(
        '${ref.read(appConfigProvider).apiBaseUrl}/artists',
        queryParameters: {'ids': ids.join(',')},
      );

      // Ensure only valid artists from the database are included in _selected
      final validArtists = (artistsRes.data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final validArtistIds = validArtists.map((a) => a['id']).toSet();
      _selected = ids
          .where((id) => validArtistIds.contains(id))
          .map((id) => validArtists.firstWhere((a) => a['id'] == id))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch artist details: $e');
      }
      _selected = []; // Clear selected if fetching fails
    }
  }

  Future<void> _loadAvailableArtists() async {
    final dio = ref.read(dioProvider);
    final auth = ref.read(authControllerProvider);

    final res = await dio.get(
      '${ref.read(appConfigProvider).apiBaseUrl}/artists',
      queryParameters: {'limit': 200},
      options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}),
    );

    final List all = res.data is List ? res.data : res.data['value'] ?? [];
    final selectedIds = _selected.map((e) => e['id']).toSet();

    _available = all
        .map((e) => Map<String, dynamic>.from(e))
        .where((a) => !selectedIds.contains(a['id']))
        .toList();

    if (mounted) setState(() {});
  }

  /// ✅ Add to selected
  Future<void> _addArtist(Map<String, dynamic> artist) async {
    if (_saving) return;

    // Local optimistic move: add to selected UI and remove from available.
    setState(() {
      _available.removeWhere((a) => a['id'] == artist['id']);
      _selected.insert(0, artist);
      // ensure uniqueness
      _selected = _selected.toSet().toList();
    });
  }

  /// Show confirmation and remove from selected (server-side)
  Future<void> _confirmAndRemoveArtist(int id) async {
    final should = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text('Bạn có muốn xóa nghệ sĩ khỏi danh sách yêu thích không?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('OK')),
        ],
      ),
    );

    if (should != true) return;

    // Local move: remove from selected and put back into available at the original position
    final removed = _selected.firstWhere((e) => e['id'] == id, orElse: () => <String, dynamic>{});
    setState(() {
      _selected.removeWhere((e) => e['id'] == id);
      if (removed.isNotEmpty && !_available.any((a) => a['id'] == id)) {
        // Insert back into available at the original position
        final originalIndex = _available.indexWhere((a) => a['id'] > id);
        if (originalIndex == -1) {
          _available.add(removed);
        } else {
          _available.insert(originalIndex, removed);
        }
      }
    });
  }

  // NOTE: local-only auto-save removed from add/remove flows so the top row
  // only reflects server-authoritative selection. Cache helpers remain used
  // only as a fallback when the initial GET fails.

  /// ✅ Save to backend
  Future<void> _save() async {
    setState(() => _saving = true);

    final dio = ref.read(dioProvider);
    final auth = ref.read(authControllerProvider);

    final currentIds = _selected.map((e) => e['id'] as int).toSet();

    // compute diffs for informational purposes (which to add / which to remove)
    final toAdd = currentIds.difference(_serverSelectedIds).toList();
    final toRemove = _serverSelectedIds.difference(currentIds).toList();
    if (kDebugMode) {
      // debug info only
      // ignore: avoid_print
      print('PreferredArtists save diff -> add:${toAdd.length} remove:${toRemove.length}');
    }

    try {
      // Use bulk save endpoint to set the authoritative list on server.
      final allIds = currentIds.toList();
      final res = await dio.post(
        '${ref.read(appConfigProvider).apiBaseUrl}/users/me/preferences/artists',
        data: {'artist_ids': allIds},
        options: Options(headers: {'Authorization': 'Bearer ${auth.token}'}),
      );

      // If server returns authoritative ids, use them. Otherwise assume
      // success and keep local selection as authoritative.
      if (res.data is List) {
        final returnedIds = (res.data as List).map((e) => e as int).toList();
        _serverSelectedIds = returnedIds.toSet();
        await _fetchArtistsDetails(returnedIds);
      } else if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        // optimistic: server accepted, update snapshot to currentIds
        _serverSelectedIds = currentIds;
      } else {
        throw Exception('Save failed with status ${res.statusCode}');
      }

      // Sort available artists to maintain original order
      _available.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Đã lưu thành công")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu thất bại. Vui lòng thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
      // Refresh available list to reflect current selection without
      // overwriting the user's current `_selected` unless server returned
      // authoritative IDs above.
      await _loadAvailableArtists();
    }
  }

  // Local cache removed: we no longer persist preferred artists locally.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nghệ sĩ yêu thích"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              // If there's no pop entry, go back to profile as a safe default
              context.go('/profile');
            }
          },
        ),
      ),
    // Wrap body with SafeArea so content won't be obscured by system UI or
    // the bottom navigation button. Also add extra bottom padding for the
    // GridView so its content can't underflow behind the bottom bar.
    body: SafeArea(
    top: false,
    bottom: true,
    child: _loading
      ? const Center(child: CircularProgressIndicator())
      : Column(
              children: [
                /// ✅ Selected Artists
                SizedBox(
                  // Slightly reduced height to give more vertical space on small screensr
                  height: 140,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selected.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (_, i) {
                      final a = _selected[i];
                      return Column(
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  a['cover_url'] ?? "https://via.placeholder.com/80",
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => _confirmAndRemoveArtist(a['id']),
                                  child: const CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              a['name'],
                              maxLines: 2,
                              textAlign: TextAlign.center,
                            ),
                          )
                        ],
                      );
                    },
                  ),
                ),

                const Divider(),

                /// ✅ Grid available artists
                Expanded(
                  child: GridView.builder(
                    itemCount: _available.length,
                    // add extra bottom padding so grid doesn't get clipped by the
                    // Scaffold's bottomNavigationBar (and leaves breathing room)
                    // increase bottom padding to ensure grid never underflows
                    padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).viewPadding.bottom + 160),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                    itemBuilder: (_, i) {
                      final a = _available[i];
                      return InkWell(
                        onTap: () => _addArtist(a),
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  a['cover_url'] ?? "https://via.placeholder.com/150",
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Text(
                              a['name'],
                              maxLines: 2,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
    ),
    ),
  bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text("Lưu"),
        ),
      ),
    );
  }
}
