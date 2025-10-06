enum AppEnvironment { dev, prod }

class AppConfig {
  final String apiBaseUrl;
  final AppEnvironment environment;
  const AppConfig({required this.apiBaseUrl, required this.environment});

  // Use 127.0.0.1 instead of localhost to avoid some browser host resolution / CORS edge cases.
  static const AppConfig dev = AppConfig(apiBaseUrl: 'http://127.0.0.1:8000', environment: AppEnvironment.dev);
}
