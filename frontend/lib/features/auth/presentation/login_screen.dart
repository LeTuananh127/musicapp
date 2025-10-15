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
    final theme = Theme.of(context);

    return Scaffold(
      // No appbar - full screen auth look
      body: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo / Title
                    const SizedBox(height: 24),
                    Text('MusicApp', textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text(_isLogin ? 'Chào mừng trở lại' : 'Tạo tài khoản mới', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 28),

                    // Form
                    TextField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.person)),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      decoration: const InputDecoration(hintText: 'Mật khẩu', prefixIcon: Icon(Icons.lock)),
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),

                    // CTA
                    auth.loading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: () async {
                              final ok = _isLogin
                                  ? await ref.read(authControllerProvider.notifier).login(_emailCtrl.text.trim(), _passCtrl.text)
                                  : await ref.read(authControllerProvider.notifier).register(_emailCtrl.text.trim(), _passCtrl.text);
                              if (ok && mounted) {
                                context.go('/home');
                              }
                            },
                            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            child: Text(_isLogin ? 'Đăng nhập' : 'Đăng ký', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),

                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(_isLogin ? 'Tạo tài khoản mới' : 'Đã có tài khoản? Đăng nhập', style: const TextStyle(color: Colors.white70)),
                    ),

                    if (auth.error != null) ...[
                      const SizedBox(height: 8),
                      Text(auth.error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                    ]
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
