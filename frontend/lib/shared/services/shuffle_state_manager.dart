import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent shuffle state for playlists
/// Shuffle order is maintained across navigation but resets on app restart
class ShuffleStateManager {
  static const String _prefix = 'shuffle_state_';
  static const String _sessionKey = 'app_session_id';

  static SharedPreferences? _prefs;
  static String? _currentSessionId;

  /// Initialize the manager - call this in main()
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    // Generate new session ID for this app launch
    final oldSessionId = _prefs?.getString(_sessionKey);
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

    // Clear all shuffle states from previous session
    if (oldSessionId != null && oldSessionId != _currentSessionId) {
      await _clearAllShuffleStates();
    }

    // Save new session ID
    await _prefs?.setString(_sessionKey, _currentSessionId!);
  }

  /// Save shuffle state for a specific playlist/screen
  static Future<void> saveShuffleState(
    String screenKey,
    List<Map<String, dynamic>> shuffled,
    int pageIndex,
  ) async {
    if (_prefs == null) return;

    final key = '$_prefix$screenKey';
    final data = {
      'shuffled': shuffled,
      'pageIndex': pageIndex,
      'sessionId': _currentSessionId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _prefs!.setString(key, jsonEncode(data));
  }

  /// Load shuffle state for a specific playlist/screen
  /// Returns null if no state exists or if it's from a different session
  static Map<String, dynamic>? loadShuffleState(String screenKey) {
    if (_prefs == null) return null;

    final key = '$_prefix$screenKey';
    final jsonStr = _prefs!.getString(key);

    if (jsonStr == null) return null;

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Check if state is from current session
      if (data['sessionId'] != _currentSessionId) {
        return null;
      }

      return {
        'shuffled': (data['shuffled'] as List).cast<Map<String, dynamic>>(),
        'pageIndex': data['pageIndex'] as int,
      };
    } catch (e) {
      print('❌ Failed to load shuffle state for $screenKey: $e');
      return null;
    }
  }

  /// Clear shuffle state for a specific screen
  static Future<void> clearShuffleState(String screenKey) async {
    if (_prefs == null) return;
    final key = '$_prefix$screenKey';
    await _prefs!.remove(key);
  }

  /// Clear all shuffle states (called on session change)
  static Future<void> _clearAllShuffleStates() async {
    if (_prefs == null) return;

    final keys = _prefs!.getKeys();
    final shuffleKeys = keys.where((k) => k.startsWith(_prefix));

    for (final key in shuffleKeys) {
      await _prefs!.remove(key);
    }
  }

  /// Generate screen key for virtual playlist
  static String virtualPlaylistKey(String title, List<int>? artistIds) {
    if (artistIds != null && artistIds.isNotEmpty) {
      return 'virtual_${artistIds.join('_')}';
    }
    return 'virtual_${title.hashCode}';
  }

  /// Generate screen key for playlist detail
  static String playlistDetailKey(int playlistId) {
    return 'playlist_$playlistId';
  }

  /// Generate screen key for liked songs
  static String get likedSongsKey => 'liked_songs';
}
