import 'package:dio/dio.dart';

class DeezerService {
  final Dio _dio;
  DeezerService(String baseUrl) : _dio = Dio(BaseOptions(baseUrl: baseUrl));

  Future<List<dynamic>> search(String q, {int limit = 10}) async {
    final res = await _dio.get('/deezer/search', queryParameters: {'q': q, 'limit': limit});
    return res.data['data'] as List<dynamic>;
  }
}
