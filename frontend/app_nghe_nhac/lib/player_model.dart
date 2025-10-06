import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class Song {
  final int id;
  final String title;
  final String artist;
  final String url;
  final String cover;
  Song(
      {required this.id,
      required this.title,
      required this.artist,
      required this.url,
      required this.cover});
  factory Song.fromJson(Map<String, dynamic> j) => Song(
      id: j['id'],
      title: j['title'],
      artist: j['artist'],
      url: j['url'],
      cover: j['cover']);
}

class PlayerModel extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<Song> playlist = [];
  int currentIndex = -1;

  PlayerModel() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  }

  Future<void> setPlaylist(List<Song> songs, {int startIndex = 0}) async {
    playlist = songs;
    currentIndex = startIndex;
    final initial =
        playlist.map((s) => AudioSource.uri(Uri.parse(s.url))).toList();
    await _player.setAudioSource(ConcatenatingAudioSource(children: initial));
    await playAt(startIndex);
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
    notifyListeners();
  }

  Future<void> play() async {
    await _player.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> next() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      notifyListeners();
    } else {
      // nếu muốn quay về đầu bài hiện tại:
      await _player.seek(Duration.zero);
    }
    notifyListeners();
  }

  bool get playing => _player.playing;
  Song? get currentSong => (currentIndex >= 0 && currentIndex < playlist.length)
      ? playlist[currentIndex]
      : null;

  // dispose
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
