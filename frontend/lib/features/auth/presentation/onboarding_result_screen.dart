import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingResultScreen extends StatelessWidget {
  final List<Map<String, dynamic>> playlists;
  const OnboardingResultScreen({super.key, required this.playlists});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gợi ý cho bạn')),
      body: playlists.isEmpty
          ? const Center(child: Text('Không có gợi ý'))
          : ListView.separated(
              itemCount: playlists.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final p = playlists[i];
                return ListTile(
                  title: Text(p['name']),
                  subtitle: Text('Score: ${p['score'].toStringAsFixed(2)}'),
                  onTap: () {
                    // navigate to playlist detail
                    context.go('/playlists/${p['id']}');
                  },
                );
              },
            ),
    );
  }
}
