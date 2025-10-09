import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../data/models/track.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/track_repository.dart';

enum RepeatMode { off, all, one }

class PlayerStateModel {
  final Track? current;
  final bool playing;
  final Duration position;
  final List<Track> queue;
  final int currentIndex; // -1 if none
  final List<Track> originalQueue; // lưu thứ tự gốc để bỏ shuffle
  final bool shuffle;
  final RepeatMode repeatMode;
  const PlayerStateModel({this.current, this.playing = false, this.position = Duration.zero, this.queue = const [], this.currentIndex = -1, this.originalQueue = const [], this.shuffle = false, this.repeatMode = RepeatMode.off});
  PlayerStateModel copyWith({Track? current, bool? playing, Duration? position, List<Track>? queue, int? currentIndex, List<Track>? originalQueue, bool? shuffle, RepeatMode? repeatMode}) =>
      PlayerStateModel(
        current: current ?? this.current,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        queue: queue ?? this.queue,
        currentIndex: currentIndex ?? this.currentIndex,
        originalQueue: originalQueue ?? this.originalQueue,
        shuffle: shuffle ?? this.shuffle,
        repeatMode: repeatMode ?? this.repeatMode,
      );
  bool get hasNext => currentIndex >= 0 && currentIndex + 1 < queue.length;
  bool get hasPrevious => currentIndex > 0 && currentIndex < queue.length;
}

class PlayerController extends StateNotifier<PlayerStateModel> {
  final Ref ref;
  final AudioPlayer _audio = AudioPlayer();
  int? _loggedTrackId; // track id already logged for start
  Timer? _tick;
  Timer? _persistDebounce;
  static const _persistKey = 'player_state_v1';
  // TTL for persisted player state; after this we ignore stale saved state
  static const Duration persistTTL = Duration(hours: 24);
  PlayerController(this.ref) : super(const PlayerStateModel()) {
    _audio.positionStream.listen((p) {
      state = state.copyWith(position: p);
    });
    _audio.playerStateStream.listen((ps) {
      state = state.copyWith(playing: ps.playing);
      if (ps.processingState == ProcessingState.completed) {
        _logInteraction(completed: true);
      }
    });
    _hydrate();
  }

  Future<void> playTrack(Track track) async {
    await _audio.stop();
    if (track.previewUrl != null) {
      try {
        await _audio.setUrl(track.previewUrl!);
        await _audio.play();
      } catch (e) {
        // ignore: avoid_print
        print('Audio load failed (playTrack): ${track.previewUrl} -> $e');
      }
    }
    state = PlayerStateModel(current: track, playing: true, position: Duration.zero, queue: [track], currentIndex: 0);
    _loggedTrackId = null; // reset logging sentinel
    _logInteraction(); // initial log (0 seconds listened)
    _startTick(); // still used for milestone detection / simulation fallback
    _schedulePersist();
  }

  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) return;
    await _audio.stop();
    final original = List<Track>.from(tracks);
    List<Track> activeQueue = original;
    // nếu đang bật shuffle thì xào lại (đảm bảo bài bắt đầu ở vị trí đầu)
    if (state.shuffle) {
      final current = original[startIndex];
      final rest = [...original]..removeAt(startIndex);
      rest.shuffle();
      activeQueue = [current, ...rest];
      startIndex = 0; // current nằm ở đầu sau shuffle
    }
    final start = activeQueue[startIndex];
    state = PlayerStateModel(
      current: start,
      playing: true,
      position: Duration.zero,
      queue: activeQueue,
      currentIndex: startIndex,
      originalQueue: original,
      shuffle: state.shuffle,
      repeatMode: state.repeatMode,
    );
    if (start.previewUrl != null) {
      try { await _audio.setUrl(start.previewUrl!); await _audio.play(); } catch(e){
        // ignore: avoid_print
        print('Audio load failed (playQueue start): ${start.previewUrl} -> $e');
      }
    }
    _loggedTrackId = null;
    _logInteraction();
    _startTick();
    _schedulePersist();
  }

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    int nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.queue.length) {
      // Hết queue
      if (state.repeatMode == RepeatMode.all) {
        // lặp từ đầu (nếu shuffle đang bật thì xào lại dựa trên originalQueue)
        List<Track> newQueue;
        if (state.shuffle) {
          final original = [...state.originalQueue];
            original.shuffle();
          newQueue = original;
        } else {
          newQueue = state.originalQueue.isNotEmpty ? state.originalQueue : state.queue;
        }
        nextIndex = 0;
        state = state.copyWith(queue: newQueue);
      } else {
        // repeat off -> dừng
        state = state.copyWith(playing: false);
        _tick?.cancel();
        return;
      }
    }
    final nextTrack = state.queue[nextIndex];
    await _audio.stop();
    if (nextTrack.previewUrl != null) {
      try { await _audio.setUrl(nextTrack.previewUrl!); await _audio.play(); } catch(e){
        // ignore: avoid_print
        print('Audio load failed (next): ${nextTrack.previewUrl} -> $e');
      }
    }
    state = state.copyWith(current: nextTrack, position: Duration.zero, playing: true, currentIndex: nextIndex);
    _loggedTrackId = null;
    _logInteraction();
    _startTick();
    _schedulePersist();
  }

  Future<void> previous() async {
    if (!state.hasPrevious) return;
    final prevIndex = state.currentIndex - 1;
    final prevTrack = state.queue[prevIndex];
    await _audio.stop();
    if (prevTrack.previewUrl != null) {
      try { await _audio.setUrl(prevTrack.previewUrl!); await _audio.play(); } catch(e){
        // ignore: avoid_print
        print('Audio load failed (previous): ${prevTrack.previewUrl} -> $e');
      }
    }
    state = state.copyWith(current: prevTrack, position: Duration.zero, playing: true, currentIndex: prevIndex);
    _loggedTrackId = null;
    _logInteraction();
    _startTick();
  }

  Future<void> jumpTo(int index, {bool autoplay = true}) async {
    if (index < 0 || index >= state.queue.length) return;
    final track = state.queue[index];
    await _audio.stop();
    if (track.previewUrl != null) {
      try { await _audio.setUrl(track.previewUrl!); if (autoplay) await _audio.play(); } catch(e){
        // ignore: avoid_print
        print('Audio load failed (jumpTo): ${track.previewUrl} -> $e');
      }
    }
    state = state.copyWith(current: track, position: Duration.zero, playing: autoplay, currentIndex: index);
    _loggedTrackId = null;
    if (autoplay) {
      _logInteraction();
      _startTick();
    }
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.queue.length) return;
    final isCurrent = index == state.currentIndex;
    final newQueue = [...state.queue]..removeAt(index);
    int newCurrentIndex = state.currentIndex;
    Track? newCurrent = state.current;
    if (newQueue.isEmpty) {
      state = state.copyWith(queue: [], currentIndex: -1, current: null, playing: false, position: Duration.zero);
      _tick?.cancel();
      return;
    }
    if (isCurrent) {
      // nếu remove bài hiện tại -> phát bài ở cùng index (hoặc cuối nếu index >= length)
      if (index >= newQueue.length) {
        newCurrentIndex = newQueue.length - 1;
      } else {
        newCurrentIndex = index;
      }
      newCurrent = newQueue[newCurrentIndex];
    } else if (index < state.currentIndex) {
      // dịch currentIndex về trước 1
      newCurrentIndex = state.currentIndex - 1;
    }
    state = state.copyWith(queue: newQueue, currentIndex: newCurrentIndex, current: newCurrent);
    _schedulePersist();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    if (newIndex < 0 || newIndex >= state.queue.length) return;
    final list = [...state.queue];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    int cur = state.currentIndex;
    if (oldIndex == cur) {
      cur = newIndex;
    } else {
      if (oldIndex < cur && newIndex >= cur) {
        cur -= 1;
      } else if (oldIndex > cur && newIndex <= cur) {
        cur += 1;
      }
    }
    state = state.copyWith(queue: list, currentIndex: cur);
    _schedulePersist();
  }

  void toggleShuffle() {
    final newShuffle = !state.shuffle;
    if (state.queue.isEmpty) {
      state = state.copyWith(shuffle: newShuffle);
      return;
    }
    if (newShuffle) {
      // bật shuffle: xào lại ngoại trừ current ở đầu
      final current = state.current;
      final rest = [...state.queue];
      if (current != null) {
        rest.removeWhere((e) => e.id == current.id);
      }
      rest.shuffle();
      final newQueue = [if (current != null) current, ...rest];
      state = state.copyWith(queue: newQueue, shuffle: true, currentIndex: 0);
    } else {
      // tắt shuffle: khôi phục originalQueue và định vị current
      final current = state.current;
      List<Track> base = state.originalQueue.isNotEmpty ? state.originalQueue : state.queue;
      int idx = current == null ? -1 : base.indexWhere((t) => t.id == current.id);
      state = state.copyWith(queue: base, shuffle: false, currentIndex: idx);
    }
  }

  void cycleRepeatMode() {
    final nextMode = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeatMode: nextMode);
    _schedulePersist();
  }

  Future<void> seek(Duration position) async {
    final cur = state.current;
    if (cur == null) return;
    final dur = Duration(milliseconds: cur.durationMs == 0 ? 180000 : cur.durationMs);
    final clipped = position > dur ? dur : (position < Duration.zero ? Duration.zero : position);
    state = state.copyWith(position: clipped);
    _schedulePersist();
  }

  Future<void> togglePlay() async {
    if (state.current == null) return;
    if (state.playing) {
      await _audio.pause();
      state = state.copyWith(playing: false);
      _logInteraction();
      _tick?.cancel();
    } else {
      state = state.copyWith(playing: true);
      _logInteraction();
      _startTick();
    }
    _schedulePersist();
  }

  Future<void> stop() async {
    await _audio.stop();
    _logInteraction(completed: false);
    state = const PlayerStateModel();
    _tick?.cancel();
    _schedulePersist();
  }

  Future<void> _logInteraction({bool completed = false, int? milestone}) async {
    final track = state.current;
    if (track == null) return;
    final repo = ref.read(interactionRepositoryProvider);
    final seconds = state.position.inSeconds;
    // If previewUrl points to our Deezer proxy, send as external play
    if (track.previewUrl != null && track.previewUrl!.contains('/deezer/stream/')) {
      try {
        // extract external id from URL path /deezer/stream/{id}
        final uri = Uri.parse(track.previewUrl!);
        final segments = uri.pathSegments;
        String? extId;
        final idx = segments.indexOf('stream');
        if (idx >= 0 && idx + 1 < segments.length) extId = segments[idx + 1];
        if (extId != null) {
          await repo.logExternalPlay(externalTrackId: extId, seconds: seconds, completed: completed, milestone: milestone);
        }
      } catch (_) {}
      return;
    }
    try {
      await repo.logPlay(trackId: int.tryParse(track.id) ?? 0, seconds: seconds, completed: completed, milestone: milestone);
      _loggedTrackId ??= int.tryParse(track.id);
    } catch (_) {}
  }

  @override
  void dispose() {
    _audio.dispose();
    _tick?.cancel();
    _persistDebounce?.cancel();
    super.dispose();
  }

  void _startTick() {
    _tick?.cancel();
    // For real audio, positionStream updates position. We only need periodic milestone checks + fallback simulation.
    _tick = Timer.periodic(const Duration(seconds: 1), (t) async {
      final cur = state.current;
      if (cur == null || !state.playing) return;
      final totalMs = cur.durationMs == 0 ? 180000 : cur.durationMs;
      final dur = Duration(milliseconds: totalMs);
      var pos = state.position; // kept in sync by positionStream when real audio
      // Fallback: nếu just_audio chưa cập nhật (vd. load lỗi) mà position không tăng, tự tăng thủ công
      if (_audio.playing && _audio.duration == null) {
        // no duration yet; skip manual increment
      } else if (_audio.playing && _audio.position == Duration.zero && pos == Duration.zero) {
        // might still be buffering first second; allow
      } else if (!_audio.playing && state.playing && cur.previewUrl == null) {
        // simulated track (no real audio) -> increment
        pos += const Duration(seconds: 1);
        state = state.copyWith(position: pos);
      }
      double progress = dur.inMilliseconds == 0 ? 0 : pos.inMilliseconds / dur.inMilliseconds;
      _milestonesHit ??= <String, Set<int>>{};
      final tid = cur.id;
      final msSet = _milestonesHit![tid] ?? <int>{};
      bool mark(int pct){
        if (msSet.contains(pct)) return false; msSet.add(pct); _milestonesHit![tid] = msSet; return true;
      }
      if (pos >= dur) {
        if (mark(100)) _logInteraction(completed: true, milestone: 100);
        if (state.repeatMode == RepeatMode.one) {
          // restart track
          _audio.seek(Duration.zero);
          _audio.play();
          state = state.copyWith(position: Duration.zero, playing: true);
        } else {
          next();
        }
        _schedulePersist();
        return;
      }
      if (pos.inSeconds % 10 == 0) {
        _logInteraction();
        _schedulePersist();
      }
      if (progress >= 0.25 && mark(25)) _logInteraction(milestone: 25);
      if (progress >= 0.50 && mark(50)) _logInteraction(milestone: 50);
      if (progress >= 0.75 && mark(75)) _logInteraction(milestone: 75);
    });
  }

  Map<String, Set<int>>? _milestonesHit; // track.id -> {25,50,75,100}

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'queue': state.queue
            .map((t) => {
                  'id': t.id,
                  'title': t.title,
                  'artistName': t.artistName,
                  'durationMs': t.durationMs,
                  'albumId': t.albumId,
                  'previewUrl': t.previewUrl,
                  'coverUrl': t.coverUrl,
                })
            .toList(),
        'currentIndex': state.currentIndex,
        'positionMs': state.position.inMilliseconds,
        'shuffle': state.shuffle,
        'repeat': state.repeatMode.name,
        'playing': state.playing,
        'originalQueue': state.originalQueue
            .map((t) => {
                  'id': t.id,
                  'title': t.title,
                  'artistName': t.artistName,
                  'durationMs': t.durationMs,
                  'albumId': t.albumId,
                  'previewUrl': t.previewUrl,
                  'coverUrl': t.coverUrl,
                })
            .toList(),
        'savedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_persistKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final queueJson = (map['queue'] as List?) ?? [];
      final originalJson = (map['originalQueue'] as List?) ?? [];
      final savedAtStr = map['savedAt'] as String?;
      if (savedAtStr != null) {
        final savedAt = DateTime.tryParse(savedAtStr);
        if (savedAt != null) {
          final age = DateTime.now().difference(savedAt);
            if (age > persistTTL) {
            return; // quá cũ không khôi phục
          }
        }
      }
      final queue = queueJson
          .map((e) => Track(
                id: e['id'],
                title: e['title'],
                artistName: e['artistName'],
                durationMs: e['durationMs'] ?? 0,
                albumId: e['albumId'],
                previewUrl: e['previewUrl'],
                coverUrl: e['coverUrl'],
              ))
          .toList();
      final original = originalJson
          .map((e) => Track(
                id: e['id'],
                title: e['title'],
                artistName: e['artistName'],
                durationMs: e['durationMs'] ?? 0,
                albumId: e['albumId'],
                previewUrl: e['previewUrl'],
                coverUrl: e['coverUrl'],
              ))
          .toList();
      int currentIndex = map['currentIndex'] ?? -1;
      if (currentIndex < -1 || currentIndex >= queue.length) currentIndex = -1;
      final positionMs = map['positionMs'] ?? 0;
      final shuffle = map['shuffle'] ?? false;
      final repeatName = map['repeat'] as String?;
      final repeatMode = RepeatMode.values.firstWhere(
        (r) => r.name == repeatName,
        orElse: () => RepeatMode.off,
      );
      final playing = map['playing'] ?? false;
      Track? current;
      if (currentIndex >= 0 && currentIndex < queue.length) {
        current = queue[currentIndex];
      }
      state = state.copyWith(
        queue: queue,
        originalQueue: original.isNotEmpty ? original : queue,
        currentIndex: currentIndex,
        current: current,
        position: Duration(milliseconds: positionMs),
        shuffle: shuffle,
        repeatMode: repeatMode,
        playing: playing,
      );
      if (!playing) {
        _tick?.cancel();
      } else {
        _startTick();
      }

      // Metadata refresh: fetch latest track metadata for any IDs in queue to ensure titles/durations fresh
      _refreshMetadata();
    } catch (_) {}
  }

  Future<void> _refreshMetadata() async {
    try {
      if (state.queue.isEmpty) return;
      // Collect distinct track IDs (assuming numeric strings) for lookup
      // Simple strategy: fetch all (could optimize with batch endpoint later)
      final repo = ref.read(trackRepositoryProvider);
      final all = await repo.fetchAll();
      // Index by id for quick match
      final map = {for (final t in all) t.id: t};
      bool changed = false;
      List<Track> newQueue = [];
      for (final old in state.queue) {
        final updated = map[old.id];
        if (updated != null) {
          // Compare a few key fields
            if (updated.title != old.title ||
                updated.artistName != old.artistName ||
                updated.durationMs != old.durationMs) {
            changed = true;
          }
          newQueue.add(updated);
        } else {
          newQueue.add(old); // keep old if missing
        }
      }
      List<Track> newOriginal = state.originalQueue;
      if (state.originalQueue.isNotEmpty) {
        List<Track> temp = [];
        for (final old in state.originalQueue) {
          final updated = map[old.id];
          if (updated != null) {
            temp.add(updated);
          } else {
            temp.add(old);
          }
        }
        newOriginal = temp;
      }
      if (changed) {
        Track? newCurrent;
        int curIndex = state.currentIndex;
        if (curIndex >= 0 && curIndex < newQueue.length) {
          newCurrent = newQueue[curIndex];
        }
        state = state.copyWith(queue: newQueue, originalQueue: newOriginal, current: newCurrent);
        _schedulePersist();
      }
    } catch (_) {
      // silent; metadata refresh is best-effort
    }
  }
}

final playerControllerProvider = StateNotifierProvider<PlayerController, PlayerStateModel>((ref) => PlayerController(ref));
