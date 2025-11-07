import 'package:dio/dio.dart';

class AuthResult {
  final String token;
  final int userId;
  AuthResult(this.token, this.userId);
}

class AuthRepository {
  final Dio _dio;
  final String baseUrl;
  AuthRepository(this._dio, this.baseUrl);

  Future<AuthResult> login(String email, String password) async {
    final res = await _dio.post('$baseUrl/auth/login', data: {'email': email, 'password': password});
    if (res.statusCode == 200) {
      return AuthResult(res.data['access_token'], res.data['user_id']);
    }
    throw Exception('Login failed');
  }

  Future<AuthResult> register(String email, String password) async {
    final res = await _dio.post('$baseUrl/auth/register', data: {'email': email, 'password': password});
    if (res.statusCode == 200) {
      return AuthResult(res.data['access_token'], res.data['user_id']);
    }
    throw Exception('Register failed');
  }

  Future<Map<String, dynamic>?> me(String token) async {
    try {
      final res = await _dio.get('$baseUrl/auth/me', options: Options(headers: {'Authorization': 'Bearer $token'}));
      if (res.statusCode == 200 && res.data is Map) return res.data as Map<String, dynamic>;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateMe(String token, Map<String, dynamic> payload) async {
    try {
      final res = await _dio.patch('$baseUrl/auth/me', data: payload, options: Options(headers: {'Authorization': 'Bearer $token'}));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changePassword(String token, String oldPassword, String newPassword) async {
    try {
      final res = await _dio.post('$baseUrl/auth/me/password', data: {'old_password': oldPassword, 'new_password': newPassword}, options: Options(headers: {'Authorization': 'Bearer $token'}));
      return res.statusCode == 200 && res.data != null;
    } catch (_) {
      return false;
    }
  }
}
