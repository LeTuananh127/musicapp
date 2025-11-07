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
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLogin = true;
  String? _localError;

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

                    // Form (even spacing between fields)
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
                    const SizedBox(height: 12),

                    // Confirm password when registering (immediately below password)
                    if (!_isLogin) ...[
                      TextField(
                        controller: _confirmCtrl,
                        decoration: const InputDecoration(hintText: 'Xác nhận mật khẩu', prefixIcon: Icon(Icons.lock)),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 20),
                    // CTA
                    auth.loading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: () async {
                              final ok = await _performAction();
                              if (!mounted) return;
                              if (ok) {
                                if (!_isLogin) {
                                  context.go('/onboarding');
                                } else {
                                  context.go('/home');
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            child: Text(_isLogin ? 'Đăng nhập' : 'Đăng ký', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),

                    // Toggle link (visible on light backgrounds)
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _isLogin = !_isLogin;
                        _localError = null;
                        // Clear inputs when switching modes so the form is fresh
                        _emailCtrl.clear();
                        _passCtrl.clear();
                        _confirmCtrl.clear();
                      }),
                      child: Text(
                        _isLogin ? 'Tạo tài khoản mới' : 'Đã có tài khoản? Đăng nhập',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ),

                    // Error / confirmation message shown below the CTA
                    if (auth.error != null || _localError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _localError ?? auth.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return false;
    final regex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
    return regex.hasMatch(email);
  }

  Future<bool> _performAction() async {
    setState(() => _localError = null);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (!_isValidEmail(email)) {
      setState(() => _localError = 'Email không hợp lệ');
      return false;
    }
    if (pass.isEmpty) {
      setState(() => _localError = 'Mật khẩu không được để trống');
      return false;
    }
    if (!_isLogin) {
      if (_confirmCtrl.text != pass) {
        setState(() => _localError = 'Mật khẩu xác nhận không khớp');
        return false;
      }
      return await ref.read(authControllerProvider.notifier).register(email, pass);
    }
    return await ref.read(authControllerProvider.notifier).login(email, pass);
  }
}
