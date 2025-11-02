import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../shared/providers/dio_provider.dart';
import '../../../data/models/track.dart';
import '../../player/application/player_providers.dart';
import '../../playlist/application/playlist_providers.dart';
import '../../../data/repositories/playlist_repository.dart';
import '../application/chat_session_provider.dart';
import '../../like/application/like_providers.dart';

/// Floating AI Chat Assistant - Fixed at bottom right corner
class FloatingChatAssistant extends ConsumerStatefulWidget {
  const FloatingChatAssistant({super.key});

  @override
  ConsumerState<FloatingChatAssistant> createState() =>
      _FloatingChatAssistantState();
}

class _FloatingChatAssistantState extends ConsumerState<FloatingChatAssistant>
    with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final DraggableScrollableController _dragController =
      DraggableScrollableController();

  String _provider = 'groq';
  final Map<String, List<Track>> _moodTracksCache = {};
  bool _isExpanded = false;

  String get _sessionId => ref.read(chatStateProvider).sessionId;

  @override
  void initState() {
    super.initState();
    _loadConversationHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _dragController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationHistory() async {
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;

      final response = await dio.get('$base/chat/history/$_sessionId');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final messagesData =
            (data['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        final loadedMessages =
            messagesData.map((m) => ChatMessage.fromJson(m)).toList();

        ref.read(chatStateProvider.notifier).setMessages(loadedMessages);

        for (var msg in loadedMessages.reversed) {
          if (msg.role == 'assistant') {
            final detected = _extractMoodFromResponse(msg.content);
            if (detected != null) {
              ref.read(chatStateProvider.notifier).setMood(detected);
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load history: $e');
    }
  }

  String? _extractMoodFromResponse(String text) {
    try {
      final jsonMatch =
          RegExp(r'\{[^}]*"mood"\s*:\s*"([^"]+)"[^}]*\}').firstMatch(text);
      if (jsonMatch != null) {
        return jsonMatch.group(1)?.toLowerCase();
      }
    } catch (_) {}

    final lower = text.toLowerCase();

    if (lower.contains(RegExp(r'\bangry\b'))) return 'angry';
    if (lower.contains(RegExp(r'\bsad\b'))) return 'sad';
    if (lower.contains(RegExp(r'\brelaxed\b')) ||
        lower.contains(RegExp(r'\bcalm\b'))) return 'relaxed';
    if (lower.contains(RegExp(r'\benergetic\b'))) return 'energetic';
    if (lower.contains(RegExp(r'\bhappy\b')) ||
        lower.contains(RegExp(r'\bjoyful\b'))) return 'happy';

    return null;
  }

  Future<void> _sendMessage() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    final userMsg = ChatMessage(role: 'user', content: text);
    ref.read(chatStateProvider.notifier).addMessage(userMsg);
    ref.read(chatStateProvider.notifier).setLoading(true);
    _ctrl.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;

      final response = await dio.post(
        '$base/chat/send',
        data: {
          'session_id': _sessionId,
          'message': text,
          'provider': _provider,
          'include_music_context': true,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final assistantMsg = ChatMessage(
          role: 'assistant',
          content: data['message'] as String,
        );

        ref.read(chatStateProvider.notifier).addMessage(assistantMsg);
        ref.read(chatStateProvider.notifier).setLoading(false);

        final currentMood = ref.read(chatStateProvider).detectedMood;
        String? detectedMood = _extractMoodFromResponse(text);
        if (detectedMood == null && data['mood'] != null) {
          detectedMood = (data['mood'] as String).toLowerCase();
        }
        if (detectedMood != null) {
          if (currentMood != null && currentMood != detectedMood) {
            _moodTracksCache.remove(currentMood);
          }
          ref.read(chatStateProvider.notifier).setMood(detectedMood);
        }

        if (data['suggested_action'] == 'search_mood' &&
            ref.read(chatStateProvider).detectedMood != null) {
          _showMusicRecommendations();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      ref.read(chatStateProvider.notifier).setLoading(false);
      ref.read(chatStateProvider.notifier).addMessage(ChatMessage(
            role: 'assistant',
            content: '❌ Sorry, I encountered an error: ${e.toString()}',
          ));
    }
  }

  Future<void> _showMusicRecommendations() async {
    final detectedMood = ref.read(chatStateProvider).detectedMood;
    if (detectedMood == null) return;

    if (_moodTracksCache.containsKey(detectedMood)) {
      _showMusicBottomSheetWithTracks(
          detectedMood, _moodTracksCache[detectedMood]!);
    } else {
      _showMusicBottomSheetWithLoading(detectedMood);
    }
  }

  void _showMusicBottomSheetWithTracks(String mood, List<Track> tracks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) => _CachedMusicSheet(
        mood: mood,
        tracks: tracks,
        onRefresh: () {
          _moodTracksCache.remove(mood);
          Navigator.pop(context);
          _showMusicRecommendations();
        },
        onPlayTrack: _playTrack,
        onAddToPlaylist: _showAddToPlaylistDialog,
      ),
    );
  }

  void _showMusicBottomSheetWithLoading(String mood) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) => _MusicLoadingSheet(
        mood: mood,
        onTracksLoaded: (tracks) {
          _moodTracksCache[mood] = tracks;
        },
        fetchMusicForMood: _fetchMusicForMood,
        onPlayTrack: _playTrack,
        onAddToPlaylist: _showAddToPlaylistDialog,
      ),
    );
  }

  Future<List<Track>> _fetchMusicForMood(String mood) async {
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;

      final response = await dio.post(
        '$base/mood/recommend/from_db',
        data: {
          'user_text': mood,
          'top_k': 100,
          'limit': 500,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final tracksData =
            (data['candidates'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        if (tracksData.isNotEmpty) {
          final allTracks = tracksData.map((t) {
            final trackData = Map<String, dynamic>.from(t);
            if (trackData['id'] is int) {
              trackData['id'] = trackData['id'].toString();
            }

            trackData['title'] = trackData['title'] ?? 'Unknown';
            trackData['artistName'] = trackData['artist_name'] ??
                trackData['artistName'] ??
                'Unknown Artist';
            trackData['durationMs'] =
                trackData['duration_ms'] ?? trackData['durationMs'] ?? 0;

            final rawPreview =
                trackData['preview_url'] ?? trackData['previewUrl'];
            if (rawPreview != null) {
              final previewStr = rawPreview.toString();
              if (previewStr.contains('cdnt-preview.dzcdn.net') ||
                  previewStr.contains('cdns-preview.dzcdn.net') ||
                  previewStr.contains('dzcdn.net')) {
                trackData['previewUrl'] =
                    '$base/deezer/stream/${trackData['id']}';
              } else if (previewStr.startsWith('http')) {
                trackData['previewUrl'] = previewStr;
              } else {
                trackData['previewUrl'] = base + previewStr;
              }
            } else {
              trackData['previewUrl'] = null;
            }

            final rawCover = trackData['cover_url'] ?? trackData['coverUrl'];
            if (rawCover != null) {
              final coverStr = rawCover.toString();
              if (coverStr.startsWith('http')) {
                if (coverStr.contains('/deezer/image') ||
                    coverStr.contains('/deezer/stream')) {
                  trackData['coverUrl'] = coverStr;
                } else if (coverStr.contains('api.deezer.com')) {
                  trackData['coverUrl'] =
                      '$base/deezer/image?url=${Uri.encodeComponent(coverStr)}';
                } else {
                  trackData['coverUrl'] = coverStr;
                }
              } else {
                trackData['coverUrl'] = base + coverStr;
              }
            } else {
              trackData['coverUrl'] = null;
            }

            return Track.fromJson(trackData);
          }).toList();

          allTracks.shuffle();
          return allTracks.take(20).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching music: $e');
      throw Exception('Failed to load music: $e');
    }
  }

  Future<void> _playTrack(Track track, List<Track> allTracks, int index) async {
    final detectedMood = ref.read(chatStateProvider).detectedMood;

    try {
      await ref.read(playerControllerProvider.notifier).playQueue(
        allTracks,
        index,
        origin: {
          'type': 'mood_recommendation',
          'mood': detectedMood ?? 'unknown',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing: ${track.title}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddToPlaylistDialog(Track track) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Consumer(
          builder: (c, r, _) {
            final asyncLists = r.watch(myPlaylistsProvider);
            return SafeArea(
              child: asyncLists.when(
                data: (lists) {
                  if (lists.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                              'Bạn chưa có playlist. Hãy tạo mới ở tab Playlists.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Đóng'),
                          )
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: lists.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c2, i) {
                      final p = lists[i];
                      return ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(p.name),
                        subtitle:
                            p.description != null && p.description!.isNotEmpty
                                ? Text(p.description!)
                                : null,
                        onTap: () async {
                          final repo = r.read(playlistRepositoryProvider);
                          final tid = int.tryParse(track.id);
                          if (tid == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('ID bài hát không hợp lệ')),
                            );
                            return;
                          }
                          try {
                            await repo.addTrack(p.id, tid);
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Đã thêm "${track.title}" vào ${p.name}')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Lỗi thêm vào playlist: $e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Lỗi tải playlists: $e'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _getMoodIcon(String mood) {
    switch (mood.toLowerCase()) {
      case 'energetic':
        return Icons.bolt;
      case 'relaxed':
        return Icons.spa;
      case 'angry':
        return Icons.local_fire_department;
      case 'sad':
        return Icons.cloud;
      case 'happy':
        return Icons.sentiment_very_satisfied;
      default:
        return Icons.music_note;
    }
  }

  void _clearConversation() {
    ref.read(chatStateProvider.notifier).reset();
    _moodTracksCache.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatStateProvider);

    return Stack(
      children: [
        // Floating button
        if (!_isExpanded)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _isExpanded = true;
                });
              },
              icon: const Icon(Icons.smart_toy),
              label: const Text('AI Chat'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),

        // Draggable chat panel
        if (_isExpanded)
          Positioned.fill(
            child: DraggableScrollableSheet(
              controller: _dragController,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [0.4, 0.6, 0.92],
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      GestureDetector(
                        onTap: () {
                          // Toggle between sizes when tapping handle
                          if (_dragController.size < 0.5) {
                            _dragController.animateTo(
                              0.6,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else if (_dragController.size < 0.8) {
                            _dragController.animateTo(
                              0.92,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _dragController.animateTo(
                              0.4,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.smart_toy, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'AI Music Chat',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            // Provider selector
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.settings, size: 18),
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              onSelected: (value) =>
                                  setState(() => _provider = value),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'openai',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check,
                                        color: _provider == 'openai'
                                            ? Colors.green
                                            : Colors.transparent,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('OpenAI GPT'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'gemini',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check,
                                        color: _provider == 'gemini'
                                            ? Colors.green
                                            : Colors.transparent,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Google Gemini'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'groq',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check,
                                        color: _provider == 'groq'
                                            ? Colors.green
                                            : Colors.transparent,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Groq (Llama 3)'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep, size: 18),
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _clearConversation,
                              tooltip: 'Clear conversation',
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _isExpanded = false;
                                });
                              },
                              tooltip: 'Minimize',
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Detected mood indicator
                      if (chatState.detectedMood != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.1),
                          child: Row(
                            children: [
                              Icon(_getMoodIcon(chatState.detectedMood!),
                                  size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Mood: ${chatState.detectedMood!.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.music_note, size: 12),
                                label: const Text('Music',
                                    style: TextStyle(fontSize: 11)),
                                onPressed: _showMusicRecommendations,
                              ),
                            ],
                          ),
                        ),

                      // Chat messages
                      Expanded(
                        child: chatState.messages.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Xin chào! Hôm nay bạn cảm thấy thế nào?',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.all(16),
                                itemCount: chatState.messages.length,
                                itemBuilder: (context, index) {
                                  final msg = chatState.messages[index];
                                  final isUser = msg.role == 'user';

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      mainAxisAlignment: isUser
                                          ? MainAxisAlignment.end
                                          : MainAxisAlignment.start,
                                      children: [
                                        if (!isUser)
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                Theme.of(context).primaryColor,
                                            child: const Icon(Icons.smart_toy,
                                                color: Colors.white, size: 16),
                                          ),
                                        if (!isUser) const SizedBox(width: 8),
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isUser
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              msg.content,
                                              style: TextStyle(
                                                color: isUser
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (isUser) const SizedBox(width: 8),
                                        if (isUser)
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: Colors.grey[300],
                                            child: const Icon(Icons.person,
                                                color: Colors.black54,
                                                size: 16),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Loading indicator
                      if (chatState.isLoading)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: Theme.of(context).primaryColor,
                                child: const Icon(Icons.smart_toy,
                                    color: Colors.white, size: 10),
                              ),
                              const SizedBox(width: 8),
                              const Text('Thinking...',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          ),
                        ),

                      // Input field
                      SafeArea(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _ctrl,
                                  decoration: InputDecoration(
                                    hintText: 'Nhập tâm trạng của bạn...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                  enabled: !chatState.isLoading,
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FloatingActionButton.small(
                                onPressed:
                                    chatState.isLoading ? null : _sendMessage,
                                child: const Icon(Icons.send, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// Music loading sheet widget
class _MusicLoadingSheet extends StatefulWidget {
  final String mood;
  final Function(List<Track>) onTracksLoaded;
  final Future<List<Track>> Function(String) fetchMusicForMood;
  final void Function(Track, List<Track>, int) onPlayTrack;
  final void Function(Track) onAddToPlaylist;

  const _MusicLoadingSheet({
    required this.mood,
    required this.onTracksLoaded,
    required this.fetchMusicForMood,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  State<_MusicLoadingSheet> createState() => _MusicLoadingSheetState();
}

class _MusicLoadingSheetState extends State<_MusicLoadingSheet> {
  List<Track>? _tracks;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      final result = await widget.fetchMusicForMood(widget.mood);
      if (mounted) {
        setState(() {
          _tracks = result;
          _isLoading = false;
        });
        widget.onTracksLoaded(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(_getMoodIcon(widget.mood), color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${widget.mood.toUpperCase()} Music',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading music...'),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 48, color: Colors.red),
                                const SizedBox(height: 16),
                                Text('Error: $_error'),
                              ],
                            ),
                          )
                        : _tracks != null && _tracks!.isNotEmpty
                            ? ListView.builder(
                                controller: scrollController,
                                itemCount: _tracks!.length,
                                itemBuilder: (context, index) {
                                  final track = _tracks![index];
                                  return ListTile(
                                    leading: track.coverUrl != null
                                        ? Image.network(
                                            track.coverUrl!,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(Icons.music_note,
                                            size: 48),
                                    title: Text(track.title),
                                    subtitle: Text(track.artistName),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.playlist_add),
                                      onPressed: () =>
                                          widget.onAddToPlaylist(track),
                                    ),
                                    onTap: () => widget.onPlayTrack(
                                        track, _tracks!, index),
                                  );
                                },
                              )
                            : const Center(child: Text('No tracks found')),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getMoodIcon(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy':
        return Icons.sentiment_very_satisfied;
      case 'sad':
        return Icons.sentiment_dissatisfied;
      case 'energetic':
        return Icons.bolt;
      case 'calm':
        return Icons.spa;
      case 'angry':
        return Icons.whatshot;
      case 'romantic':
        return Icons.favorite;
      default:
        return Icons.music_note;
    }
  }
}

// Cached music sheet widget
class _CachedMusicSheet extends ConsumerWidget {
  final String mood;
  final List<Track> tracks;
  final VoidCallback onRefresh;
  final void Function(Track, List<Track>, int) onPlayTrack;
  final void Function(Track) onAddToPlaylist;

  const _CachedMusicSheet({
    required this.mood,
    required this.tracks,
    required this.onRefresh,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likedTracks = ref.watch(likedTracksProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(_getMoodIcon(mood), color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${mood.toUpperCase()} Music',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Shuffle new tracks',
                  onPressed: onRefresh,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final trackId = int.tryParse(track.id) ?? -1;
                final isLiked = likedTracks.contains(trackId);

                return ListTile(
                  leading: track.coverUrl != null
                      ? Image.network(
                          track.coverUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.music_note, size: 48),
                  title: Text(track.title),
                  subtitle: Text(track.artistName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLiked)
                        const Icon(Icons.favorite, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => onAddToPlaylist(track),
                      ),
                    ],
                  ),
                  onTap: () => onPlayTrack(track, tracks, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getMoodIcon(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy':
        return Icons.sentiment_very_satisfied;
      case 'sad':
        return Icons.sentiment_dissatisfied;
      case 'energetic':
        return Icons.bolt;
      case 'calm':
        return Icons.spa;
      case 'angry':
        return Icons.whatshot;
      case 'romantic':
        return Icons.favorite;
      default:
        return Icons.music_note;
    }
  }
}
