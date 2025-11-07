import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _oldPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _loadingProfile = false;
  bool _changingPassword = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(authRepositoryProvider);
    if (auth.token != null) {
      final me = await repo.me(auth.token!);
      if (me != null) {
        _displayNameCtrl.text = (me['display_name'] as String?) ?? '';
      }
    }
    setState(() => _loadingProfile = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authControllerProvider);
    if (auth.token == null) return;
    final repo = ref.read(authRepositoryProvider);
    final ok = await repo.updateMe(auth.token!, {'display_name': _displayNameCtrl.text.trim()});
    if (ok) {
      // update local state so UI reflects change immediately
      ref.read(authControllerProvider.notifier).setDisplayName(_displayNameCtrl.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật thông tin')));
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi khi cập nhật')));
      }
    }
  }

  Future<void> _changePassword() async {
    if (_newPassCtrl.text.trim() != _confirmPassCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu mới không khớp')));
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (auth.token == null) return;
    setState(() => _changingPassword = true);
    final repo = ref.read(authRepositoryProvider);
    final ok = await repo.changePassword(auth.token!, _oldPassCtrl.text.trim(), _newPassCtrl.text.trim());
    setState(() => _changingPassword = false);
    if (ok) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu đã được thay đổi')));
      _oldPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
    } else {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể thay đổi mật khẩu')));
    }
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _oldPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ của tôi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Prefer to pop the GoRouter history. If there's nothing to pop
            // (e.g., route was replaced), fall back to a safe route.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Thông tin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _displayNameCtrl,
                          decoration: const InputDecoration(labelText: 'Tên hiển thị'),
                          validator: (v) {
                            if (v == null) return null;
                            if (v.trim().isEmpty) return 'Vui lòng nhập tên hiển thị';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saveProfile,
                          icon: const Icon(Icons.save),
                          label: const Text('Lưu thay đổi'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () {
                            // Push preferred artists so users can pop back to profile
                            if (context.mounted) context.push('/preferred-artists');
                          },
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Nghệ sĩ yêu thích'),
                        ),
                        const SizedBox(height: 24),
                        const Text('Đổi mật khẩu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _oldPassCtrl,
                          decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'),
                          obscureText: true,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _newPassCtrl,
                          decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
                          obscureText: true,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmPassCtrl,
                          decoration: const InputDecoration(labelText: 'Xác nhận mật khẩu mới'),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        _changingPassword
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton.icon(
                                onPressed: _changePassword,
                                icon: const Icon(Icons.lock),
                                label: const Text('Đổi mật khẩu'),
                              ),
                        const SizedBox(height: 40),
                        Text('Email: ${auth.userId == null ? "(không đăng nhập)" : "${auth.userId}"}'),
                      ],
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
