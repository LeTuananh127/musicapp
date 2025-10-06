import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'player_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool loading = false;

  Future<void> loadSongs(BuildContext context) async {
    setState(() => loading = true);
    final res = await http.get(Uri.parse('http://127.0.0.1:8000/songs'));
    if (res.statusCode == 200) {
      final List<dynamic> arr = json.decode(res.body);
      final songs = arr.map((e) => Song.fromJson(e)).toList();
      // set playlist và phát từ bài đầu
      Provider.of<PlayerModel>(context, listen: false)
          .setPlaylist(songs, startIndex: 0);
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerModel>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          AppBar(title: Text('Spotify-like'), backgroundColor: Colors.black),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () => loadSongs(context),
            child: Text('Load playlist từ backend'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: player.playlist.length,
              itemBuilder: (context, index) {
                final s = player.playlist[index];
                return ListTile(
                  leading: Image.network(s.cover,
                      width: 50, height: 50, fit: BoxFit.cover),
                  title: Text(s.title, style: TextStyle(color: Colors.white)),
                  subtitle:
                      Text(s.artist, style: TextStyle(color: Colors.grey)),
                  onTap: () async {
                    await player.playAt(index);
                  },
                );
              },
            ),
          ),
          // mini player
          if (player.currentSong != null) MiniPlayer(),
        ],
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerModel>(context);
    final song = player.currentSong!;
    return Container(
      color: Colors.grey[900],
      height: 70,
      child: Row(
        children: [
          SizedBox(width: 8),
          Image.network(song.cover, width: 50, height: 50, fit: BoxFit.cover),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title, style: TextStyle(color: Colors.white)),
                Text(song.artist,
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.skip_previous, color: Colors.white),
            onPressed: () => player.previous(),
          ),
          IconButton(
            icon: Icon(player.playing ? Icons.pause_circle : Icons.play_circle,
                size: 36, color: Colors.white),
            onPressed: () => player.playing ? player.pause() : player.play(),
          ),
          IconButton(
            icon: Icon(Icons.skip_next, color: Colors.white),
            onPressed: () => player.next(),
          ),
          SizedBox(width: 8),
        ],
      ),
    );
  }
}
