import 'package:dio/dio.dart';

class HttpClientFactory {
  static Dio create(String baseUrl, {String? authToken}) {
    // Treat any status below 500 as a valid response so Dio does not throw
    // a DioException for 4xx responses. The app will handle 4xx responses
    // (like 401/403) at the application layer instead of letting the
    // low-level HTTP client throw an exception which may be uncaught
    // in background async callbacks.
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
    );
    final dio = Dio(options);
    if (authToken != null) {
      dio.options.headers['Authorization'] = 'Bearer $authToken';
    }
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: false));
    return dio;
  }
}
