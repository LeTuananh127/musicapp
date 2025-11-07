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

/// Conversational Music Chat Widget with AI
class ConversationalMoodChatWidget extends ConsumerStatefulWidget {
  const ConversationalMoodChatWidget({super.key});

  @override
  ConsumerState<ConversationalMoodChatWidget> createState() =>
      _ConversationalMoodChatWidgetState();
}

class _ConversationalMoodChatWidgetState
    extends ConsumerState<ConversationalMoodChatWidget> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String _provider =
      'groq'; // openai, gemini, or groq (default: groq - free & fast)
  final Map<String, List<Track>> _moodTracksCache = {}; // Cache tracks by mood

  // Get session ID from provider (persistent across widget rebuilds)
  String get _sessionId => ref.read(chatStateProvider).sessionId;

  @override
  void initState() {
    super.initState();
    debugPrint('🔵 ChatWidget initState - Session: $_sessionId');
    // Load conversation history when widget opens
    _loadConversationHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConversationHistory() async {
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;

      debugPrint('🔄 Loading chat history for session: $_sessionId');
      final response = await dio.get('$base/chat/history/$_sessionId');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final messagesData =
            (data['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        debugPrint('📨 Loaded ${messagesData.length} messages from history');

        final loadedMessages =
            messagesData.map((m) => ChatMessage.fromJson(m)).toList();

        // Update messages in provider
        ref.read(chatStateProvider.notifier).setMessages(loadedMessages);
        debugPrint('✅ Messages set in provider: ${loadedMessages.length}');

        // Try to detect mood from last messages
        for (var msg in loadedMessages.reversed) {
          if (msg.role == 'assistant') {
            final detected = _extractMoodFromResponse(msg.content);
            if (detected != null) {
              ref.read(chatStateProvider.notifier).setMood(detected);
              debugPrint('🎭 Detected mood from history: $detected');
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load history: $e');
      // Don't show error to user - just start fresh
    }
  }

  String? _extractMoodFromResponse(String text) {
    // Try to extract mood from JSON response first
    try {
      final jsonMatch =
          RegExp(r'\{[^}]*"mood"\s*:\s*"([^"]+)"[^}]*\}').firstMatch(text);
      if (jsonMatch != null) {
        return jsonMatch.group(1)?.toLowerCase();
      }
    } catch (_) {}

    // Try keyword detection with more specific patterns
    final lower = text.toLowerCase();

    // Check for specific mood keywords (order matters - most specific first)
    if (lower.contains(RegExp(r'\bangry\b'))) return 'angry';
    if (lower.contains(RegExp(r'\bsad\b'))) return 'sad';
    if (lower.contains(RegExp(r'\brelaxed\b')) ||
        lower.contains(RegExp(r'\bcalm\b'))) {
      return 'relaxed';
    }
    if (lower.contains(RegExp(r'\benergetic\b'))) return 'energetic';
    if (lower.contains(RegExp(r'\bhappy\b')) ||
        lower.contains(RegExp(r'\bjoyful\b'))) {
      return 'happy';
    }

    return null;
  }

  Future<void> _sendMessage() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    // Add user message to UI via provider
    final userMsg = ChatMessage(role: 'user', content: text);
    ref.read(chatStateProvider.notifier).addMessage(userMsg);
    ref.read(chatStateProvider.notifier).setLoading(true);
    _ctrl.clear();

    // Scroll to bottom
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

        // Add message via provider
        ref.read(chatStateProvider.notifier).addMessage(assistantMsg);
        ref.read(chatStateProvider.notifier).setLoading(false);

        // Update detected mood - prioritize user input first, then backend mood
        final currentMood = ref.read(chatStateProvider).detectedMood;
        String? detectedMood =
            _extractMoodFromResponse(text); // Check user's message
        if (detectedMood == null && data['mood'] != null) {
          detectedMood =
              (data['mood'] as String).toLowerCase(); // Fallback to backend
        }
        if (detectedMood != null) {
          // Clear cache only when mood changes
          if (currentMood != null && currentMood != detectedMood) {
            _moodTracksCache.remove(currentMood);
          }
          ref.read(chatStateProvider.notifier).setMood(detectedMood);
        }

        // If action is 'search_mood', trigger music search
        if (data['suggested_action'] == 'search_mood' &&
            ref.read(chatStateProvider).detectedMood != null) {
          _showMusicRecommendations();
        }

        // Scroll to bottom
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

    // Check cache first - reuse if available
    if (_moodTracksCache.containsKey(detectedMood)) {
      // Show bottom sheet with cached tracks immediately
      _showMusicBottomSheetWithTracks(
          detectedMood, _moodTracksCache[detectedMood]!);
    } else {
      // Show bottom sheet with loading state and fetch new tracks
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
        onSaveAsPlaylist: (tracks) async => await _saveAsPlaylist(tracks),
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
        onSaveAsPlaylist: (tracks) async => await _saveAsPlaylist(tracks),
      ),
    );
  }

  Future<List<Track>> _fetchMusicForMood(String mood) async {
    try {
      final dio = ref.read(dioProvider);
      final base = ref.read(appConfigProvider).apiBaseUrl;

      // Fetch mood-based recommendations with extended timeout
      final response = await dio.post(
        '$base/mood/recommend/from_db',
        data: {
          'user_text': mood,
          'top_k': 100, // Get 100 candidates for randomization
          'limit': 500, // Balanced: enough variety without timeout
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 60), // Extended timeout
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final tracksData =
            (data['candidates'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        if (tracksData.isNotEmpty) {
          // Convert to Track models - fix id type issue and proxy URLs
          final allTracks = tracksData.map((t) {
            // Convert id to String if it's int
            final trackData = Map<String, dynamic>.from(t);
            if (trackData['id'] is int) {
              trackData['id'] = trackData['id'].toString();
            }

            // Ensure required fields exist with defaults
            trackData['title'] = trackData['title'] ?? 'Unknown';
            trackData['artistName'] = trackData['artist_name'] ??
                trackData['artistName'] ??
                'Unknown Artist';
            trackData['durationMs'] =
                trackData['duration_ms'] ?? trackData['durationMs'] ?? 0;

            // Fix preview URL - add Deezer proxy for streaming
            final rawPreview =
                trackData['preview_url'] ?? trackData['previewUrl'];
            if (rawPreview != null) {
              final previewStr = rawPreview.toString();
              if (previewStr.contains('cdnt-preview.dzcdn.net') ||
                  previewStr.contains('cdns-preview.dzcdn.net') ||
                  previewStr.contains('dzcdn.net')) {
                // Use deezer stream proxy
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

            // Fix cover URL
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

          // Shuffle and take random 20 tracks for variety
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
                              'You don\'t have any playlists. Create one in the Playlists tab.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              // Navigate to playlists if possible
                            },
                            child: const Text('Go to Playlists'),
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
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Invalid track ID')),
                              );
                            }
                            return;
                          }
                          try {
                            await repo.addTrack(p.id, tid);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Added "${track.title}" to ${p.name}')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Error adding to playlist: $e')),
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
                  child: Text('Error loading playlists: $e'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _saveAsPlaylist(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    final detectedMood = ref.read(chatStateProvider).detectedMood;

    // Show dialog to enter playlist name
    final playlistName = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(
          text:
              '${detectedMood?.toUpperCase()} Music - ${DateTime.now().toString().substring(0, 10)}',
        );
        return AlertDialog(
          title: const Text('Save as Playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Playlist Name',
              hintText: 'Enter playlist name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (playlistName == null || playlistName.trim().isEmpty) return;

    try {
      // Create new playlist
      final repo = ref.read(playlistRepositoryProvider);
      final newPlaylist = await repo.create(playlistName.trim());

      // Add all tracks to playlist
      for (final track in tracks) {
        final trackId = int.tryParse(track.id);
        if (trackId != null) {
          await repo.addTrack(newPlaylist.id, trackId);
        }
      }

      // Invalidate playlists to refresh
      ref.invalidate(myPlaylistsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ${tracks.length} tracks to "$playlistName"'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // TODO: Navigate to playlist detail
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save playlist: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      default:
        return Icons.music_note;
    }
  }

  void _clearConversation() {
    // Reset chat state in provider
    ref.read(chatStateProvider.notifier).reset();

    // Clear local cache
    _moodTracksCache.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Watch chat state from provider
    final chatState = ref.watch(chatStateProvider);

    debugPrint(
        '🔧 Building chat widget - Messages: ${chatState.messages.length}, Mood: ${chatState.detectedMood}, Loading: ${chatState.isLoading}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Chat 🎵'),
        actions: [
          // Provider selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.smart_toy),
            onSelected: (value) => setState(() => _provider = value),
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
                    ),
                    const SizedBox(width: 8),
                    const Text('Groq (Llama 3)'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearConversation,
            tooltip: 'Clear conversation',
          ),
        ],
      ),
      body: Column(
        children: [
          // Detected mood indicator
          if (chatState.detectedMood != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(_getMoodIcon(chatState.detectedMood!)),
                  const SizedBox(width: 8),
                  Text(
                    'Detected mood: ${chatState.detectedMood!.toUpperCase()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.music_note, size: 16),
                    label: const Text('Show Music'),
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
                          'Start chatting about your music mood!',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try: "I\'m feeling tired" or "Something to focus"',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor,
                                child: const Icon(Icons.smart_toy,
                                    color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  msg.content,
                                  style: TextStyle(
                                    color:
                                        isUser ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            if (isUser) ...[
                              const SizedBox(width: 8),
                              CircleAvatar(
                                backgroundColor: Colors.grey[300],
                                child: const Icon(Icons.person,
                                    color: Colors.white),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Loading indicator
          if (chatState.isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: const Icon(Icons.smart_toy, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text('Thinking...'),
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            ),

          // Input field
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: 'How are you feeling?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    enabled: !chatState.isLoading,
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: chatState.isLoading ? null : _sendMessage,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stateful widget to load music with proper lifecycle management
class _MusicLoadingSheet extends StatefulWidget {
  final String mood;
  final Function(List<Track>) onTracksLoaded;
  final Future<List<Track>> Function(String) fetchMusicForMood;
  final void Function(Track, List<Track>, int) onPlayTrack;
  final void Function(Track) onAddToPlaylist;
  final Future<void> Function(List<Track>)? onSaveAsPlaylist;

  const _MusicLoadingSheet({
    required this.mood,
    required this.onTracksLoaded,
    required this.fetchMusicForMood,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    this.onSaveAsPlaylist,
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
                        '${widget.mood.toUpperCase()} Music${_isLoading ? " - Loading..." : _tracks != null ? " (${_tracks!.length} tracks)" : ""}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!_isLoading && _tracks != null && _tracks!.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.playlist_add, color: Colors.white),
                        tooltip: 'Save as playlist',
                        onPressed: () async {
                          // Save the loaded tracks as a playlist via parent callback
                          try {
                            if (widget.onSaveAsPlaylist != null && _tracks != null && _tracks!.isNotEmpty) {
                              await widget.onSaveAsPlaylist!(_tracks!);
                              if (mounted) Navigator.pop(context);
                            }
                          } catch (e) {
                            // ignore - _loadTracks will show errors if needed
                          }
                        },
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
                            Text('Finding the perfect tracks for you...'),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 48, color: Colors.red),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Error: $_error',
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _isLoading = true;
                                        _error = null;
                                      });
                                      _loadTracks();
                                    },
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _tracks == null || _tracks!.isEmpty
                            ? const Center(child: Text('No tracks found'))
                            : Consumer(
                                builder: (context, ref, _) {
                                  final likedTracks =
                                      ref.watch(likedTracksProvider);

                                  return ListView.builder(
                                    controller: scrollController,
                                    itemCount: _tracks!.length,
                                    itemBuilder: (context, index) {
                                      final track = _tracks![index];
                                      final trackId =
                                          int.tryParse(track.id) ?? -1;
                                      final isLiked =
                                          likedTracks.contains(trackId);

                                      return ListTile(
                                        leading: track.coverUrl != null
                                            ? Image.network(
                                                track.coverUrl!,
                                                width: 48,
                                                height: 48,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(Icons.music_note,
                                                        size: 48),
                                              )
                                            : const Icon(Icons.music_note,
                                                size: 48),
                                        title: Text(track.title),
                                        subtitle: Text(track.artistName),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                isLiked
                                                    ? Icons.favorite
                                                    : Icons.favorite_border,
                                                color:
                                                    isLiked ? Colors.red : null,
                                              ),
                                              tooltip:
                                                  isLiked ? 'Unlike' : 'Like',
                                              onPressed: () {
                                                ref
                                                    .read(likedTracksProvider
                                                        .notifier)
                                                    .toggle(trackId);
                                              },
                                            ),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert),
                                              tooltip: 'More options',
                                              onSelected: (value) {
                                                if (value ==
                                                    'add_to_playlist') {
                                                  widget.onAddToPlaylist(track);
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'add_to_playlist',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.playlist_add),
                                                      SizedBox(width: 8),
                                                      Text('Add to Playlist'),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        onTap: () => widget.onPlayTrack(
                                            track, _tracks!, index),
                                      );
                                    },
                                  );
                                },
                              ),
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

/// Widget to display cached music tracks
class _CachedMusicSheet extends ConsumerWidget {
  final String mood;
  final List<Track> tracks;
  final VoidCallback onRefresh;
  final void Function(Track, List<Track>, int) onPlayTrack;
  final void Function(Track) onAddToPlaylist;
  final Future<void> Function(List<Track>)? onSaveAsPlaylist;

  const _CachedMusicSheet({
    required this.mood,
    required this.tracks,
    required this.onRefresh,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    this.onSaveAsPlaylist,
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
                    '${mood.toUpperCase()} Music (${tracks.length} tracks)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.playlist_add, color: Colors.white),
                  tooltip: 'Save as playlist',
                  onPressed: () async {
                    try {
                      if (onSaveAsPlaylist != null) {
                        await onSaveAsPlaylist!(tracks);
                        Navigator.pop(context);
                      }
                    } catch (_) {}
                  },
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
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.music_note, size: 48),
                        )
                      : const Icon(Icons.music_note, size: 48),
                  title: Text(track.title),
                  subtitle: Text(track.artistName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? Colors.red : null,
                        ),
                        tooltip: isLiked ? 'Unlike' : 'Like',
                        onPressed: () {
                          ref
                              .read(likedTracksProvider.notifier)
                              .toggle(trackId);
                        },
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'More options',
                        onSelected: (value) {
                          if (value == 'add_to_playlist') {
                            onAddToPlaylist(track);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'add_to_playlist',
                            child: Row(
                              children: [
                                Icon(Icons.playlist_add),
                                SizedBox(width: 8),
                                Text('Add to Playlist'),
                              ],
                            ),
                          ),
                        ],
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
