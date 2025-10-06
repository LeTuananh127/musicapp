import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/auth_providers.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController(text: 'alice@example.com');
  final _passCtrl = TextEditingController(text: 'dev');
  bool _isLogin = true;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Đăng nhập' : 'Đăng ký')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Mật khẩu'), obscureText: true),
            const SizedBox(height: 20),
            if (auth.loading) const CircularProgressIndicator() else ElevatedButton(
              onPressed: () async {
                final ok = _isLogin
                    ? await ref.read(authControllerProvider.notifier).login(_emailCtrl.text.trim(), _passCtrl.text)
                    : await ref.read(authControllerProvider.notifier).register(_emailCtrl.text.trim(), _passCtrl.text);
                if (ok && mounted) {
                  context.go('/home');
                }
              },
              child: Text(_isLogin ? 'Đăng nhập' : 'Đăng ký'),
            ),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(_isLogin ? 'Tạo tài khoản mới' : 'Đã có tài khoản? Đăng nhập'),
            ),
            if (auth.error != null) Text(auth.error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
