import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../models/auth_models.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  Future<AuthResponse> login(LoginRequest request) async {
    return _performAuthRequest(
      () => ApiClient.postJson(
        '/auth/login',
        body: request.toJson(),
        tag: 'auth_login',
      ),
      fallbackError: 'Login failed. Please try again.',
    );
  }

  Future<AuthResponse> register(RegisterRequest request) async {
    return _performAuthRequest(
      () => ApiClient.postJson(
        '/auth/register',
        body: request.toJson(),
        tag: 'auth_register',
      ),
      fallbackError: 'Registration failed. Please try again.',
    );
  }

  Future<MessageResponse> forgotPassword(ForgotPasswordRequest request) async {
    return _performMessageRequest(
      () => ApiClient.postJson(
        '/auth/forgot-password',
        body: request.toJson(),
        tag: 'auth_forgot_password',
      ),
      fallbackError: 'Failed to request password reset.',
    );
  }

  Future<MessageResponse> resetPassword(ResetPasswordRequest request) async {
    return _performMessageRequest(
      () => ApiClient.postJson(
        '/auth/reset-password',
        body: request.toJson(),
        tag: 'auth_reset_password',
      ),
      fallbackError: 'Failed to reset password.',
    );
  }

  Future<MessageResponse> logout(String bearerToken) async {
    return _performMessageRequest(
      () => ApiClient.postJsonNoBody(
        '/auth/logout',
        bearerToken: bearerToken,
        tag: 'auth_logout',
      ),
      fallbackError: 'Failed to logout.',
    );
  }

  Future<CurrentUserResponse> me(String bearerToken) async {
    try {
      final response = await ApiClient.getJson(
        '/me',
        bearerToken: bearerToken,
        tag: 'auth_me',
      );
      final body = _decodeBody(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return CurrentUserResponse.fromJson(body);
      }

      throw AuthException(
        _extractErrorMessage(body, 'Failed to load account details.'),
      );
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }

  Future<CurrentUserResponse> updateProfile(
    String bearerToken,
    UpdateProfileRequest request,
  ) async {
    try {
      final response = await ApiClient.putJson(
        '/me',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'auth_update_profile',
      );
      final body = _decodeBody(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return CurrentUserResponse.fromJson(body);
      }

      throw AuthException(
        _extractErrorMessage(body, 'Failed to update profile.'),
      );
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }

  Future<MessageResponse> changePassword(
    String bearerToken,
    ChangePasswordRequest request,
  ) async {
    return _performMessageRequest(
      () => ApiClient.putJson(
        '/auth/password',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'auth_change_password',
      ),
      fallbackError: 'Failed to update password.',
    );
  }

  Future<MessageResponse> resendVerificationEmail(String bearerToken) async {
    return _performMessageRequest(
      () => ApiClient.postJsonNoBody(
        '/auth/email/verification-notification',
        bearerToken: bearerToken,
        tag: 'auth_resend_verification',
      ),
      fallbackError: 'Failed to send verification email.',
    );
  }

  Future<AuthResponse> _performAuthRequest(
    Future<dynamic> Function() request, {
    required String fallbackError,
  }) async {
    try {
      final response = await request();
      final body = _decodeBody(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthResponse.fromJson(body);
      }

      throw AuthException(_extractErrorMessage(body, fallbackError));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }

  Future<MessageResponse> _performMessageRequest(
    Future<dynamic> Function() request, {
    required String fallbackError,
  }) async {
    try {
      final response = await request();
      final body = _decodeBody(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return MessageResponse.fromJson(body);
      }

      throw AuthException(_extractErrorMessage(body, fallbackError));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }

  Map<String, dynamic> _decodeBody(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  String _extractErrorMessage(Map<String, dynamic> body, String fallback) {
    final topLevel = body['message']?.toString();
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final firstValue = errors.values.first;
      if (firstValue is List && firstValue.isNotEmpty) {
        return firstValue.first.toString();
      }
    }
    return (topLevel == null || topLevel.trim().isEmpty) ? fallback : topLevel;
  }
}
