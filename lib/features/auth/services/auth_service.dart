import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const String _baseUrl = 'https://databenki.co.tz';
  static const Duration _timeout = Duration(seconds: 30);

  Future<LoginResponse> login(LoginRequest request) async {
    final uri = Uri.parse('$_baseUrl/api/auth/login');

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(_timeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return LoginResponse.fromJson(body);
      }

      final errorMsg =
          body['message'] as String? ?? 'Login failed. Please try again.';
      throw AuthException(errorMsg);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }

  Future<RegisterResponse> register(RegisterRequest request) async {
    final uri = Uri.parse('$_baseUrl/api/auth/register');

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(_timeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return RegisterResponse.fromJson(body);
      }

      final errorMsg =
          body['message'] as String? ??
          'Registration failed. Please try again.';
      throw AuthException(errorMsg);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }
}
