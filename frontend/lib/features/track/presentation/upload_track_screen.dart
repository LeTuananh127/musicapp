import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/repositories/track_repository.dart';
import '../../../data/models/track.dart';
// auth provider not required here; repo uses dio provider with configured auth interceptor

class UploadTrackScreen extends ConsumerStatefulWidget {
  const UploadTrackScreen({super.key});

  @override
  ConsumerState<UploadTrackScreen> createState() => _UploadTrackScreenState();
}

class _UploadTrackScreenState extends ConsumerState<UploadTrackScreen> {
  final _titleCtrl = TextEditingController();
  final _artistIdCtrl = TextEditingController();
  final _audioUrlCtrl = TextEditingController();
  final _coverUrlCtrl = TextEditingController();
  File? _audioFile;
  File? _coverFile;
  bool _uploading = false;
  double _progress = 0.0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistIdCtrl.dispose();
    _audioUrlCtrl.dispose();
    _coverUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'wav', 'm4a']);
    if (res != null && res.files.isNotEmpty) {
      setState(() => _audioFile = File(res.files.single.path!));
    }
  }

  Future<void> _pickCover() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.isNotEmpty) {
      setState(() => _coverFile = File(res.files.single.path!));
    }
  }

  Future<void> _upload() async {
    final title = _titleCtrl.text.trim();
  final artistText = _artistIdCtrl.text.trim();
  final int? artistId = artistText.isEmpty ? null : (int.tryParse(artistText));
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tiêu đề')));
      return;
    }
  // If audio URL provided and no file selected, use URL flow
    final audioUrl = _audioUrlCtrl.text.trim();
    final coverUrl = _coverUrlCtrl.text.trim();
    setState(() {
      _uploading = true;
      _progress = 0.0;
    });
    final repo = ref.read(trackRepositoryProvider) as TrackRepository;
    try {
      Track? created;
      if (_audioFile != null) {
        created = await repo.uploadTrack(
          title: title,
          artistId: artistId,
          audioPath: _audioFile!.path,
          coverPath: _coverFile?.path,
          durationMs: 0,
          onSendProgress: (sent, total) {
            setState(() {
              _progress = total > 0 ? sent / total : 0;
            });
          },
        );
      } else if (audioUrl.isNotEmpty) {
  created = await repo.createTrackWithUrls(title: title, artistId: artistId, durationMs: 0, audioUrl: audioUrl, coverUrl: coverUrl.isNotEmpty ? coverUrl : null);
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn file audio hoặc nhập link audio')));
        setState(() => _uploading = false);
        return;
      }
      if (created != null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tải lên thành công')));
        // navigate back to playlists or home
        if (context.mounted) Navigator.of(context).maybePop();
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tải lên thất bại')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tải lên bài hát')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Tiêu đề')),
            const SizedBox(height: 12),
            TextFormField(controller: _artistIdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Artist id (số) - để trống để tạo artist mới')),
            const SizedBox(height: 12),
            TextFormField(controller: _audioUrlCtrl, decoration: const InputDecoration(labelText: 'Link audio (nếu có)')),
            const SizedBox(height: 12),
            TextFormField(controller: _coverUrlCtrl, decoration: const InputDecoration(labelText: 'Link ảnh bìa (nếu có)')),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: Text(_audioFile?.path.split(Platform.pathSeparator).last ?? 'Chọn file audio'),
              onTap: _pickAudio,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.image),
              title: Text(_coverFile?.path.split(Platform.pathSeparator).last ?? 'Chọn ảnh bìa (tùy chọn)'),
              onTap: _pickCover,
            ),
            const SizedBox(height: 16),
            if (_uploading) LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: _uploading ? null : _upload, icon: const Icon(Icons.upload_file), label: const Text('Tải lên')),
          ],
        ),
      ),
    );
  }
}
