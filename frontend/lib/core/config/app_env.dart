enum AppEnvironment { dev, prod }

class AppConfig {
  final String apiBaseUrl;
  final AppEnvironment environment;
  const AppConfig({required this.apiBaseUrl, required this.environment});

  // Allow overriding backend URL at build/run time with --dart-define=BACKEND_URL.
  // Default remains 127.0.0.1 for tools that run on host machine; emulators should
  // pass backend as http://10.0.2.2:8000 via dart-define.
  static const String _defaultDev = 'http://127.0.0.1:8000';
  static const String _backendUrlFromDefine = String.fromEnvironment('BACKEND_URL', defaultValue: _defaultDev);
  static const AppConfig dev = AppConfig(apiBaseUrl: _backendUrlFromDefine, environment: AppEnvironment.dev);
}
