import 'package:dio/dio.dart';

class HttpClientFactory {
  static Dio create(String baseUrl, {String? authToken}) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)));
    if (authToken != null) {
      dio.options.headers['Authorization'] = 'Bearer $authToken';
    }
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: false));
    return dio;
  }
}
