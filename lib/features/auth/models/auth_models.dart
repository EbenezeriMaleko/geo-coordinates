class RegisterRequest {
  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final String? phone;

  const RegisterRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    this.phone,
  });

  Map<String, dynamic> toJson() {
    final mergedName = '$firstName $lastName'.trim();
    return {
      'name': mergedName,
      'email': email.trim(),
      'phone': phone?.trim(),
      'password': password,
      'password_confirmation': password,
    }..removeWhere(
      (key, value) => value == null || (value is String && value.isEmpty),
    );
  }
}

class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {
    'email': email.trim(),
    'password': password,
  };
}

class ForgotPasswordRequest {
  final String email;

  const ForgotPasswordRequest({required this.email});

  Map<String, dynamic> toJson() => {'email': email.trim()};
}

class ResetPasswordRequest {
  final String token;
  final String email;
  final String password;
  final String passwordConfirmation;

  const ResetPasswordRequest({
    required this.token,
    required this.email,
    required this.password,
    required this.passwordConfirmation,
  });

  Map<String, dynamic> toJson() => {
    'token': token.trim(),
    'email': email.trim(),
    'password': password,
    'password_confirmation': passwordConfirmation,
  };
}

class UpdateProfileRequest {
  final String name;
  final String email;
  final String? phone;

  const UpdateProfileRequest({
    required this.name,
    required this.email,
    this.phone,
  });

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'email': email.trim(),
    'phone': phone?.trim(),
  }..removeWhere(
    (key, value) => value == null || (value is String && value.isEmpty),
  );
}

class ChangePasswordRequest {
  final String currentPassword;
  final String password;
  final String passwordConfirmation;

  const ChangePasswordRequest({
    required this.currentPassword,
    required this.password,
    required this.passwordConfirmation,
  });

  Map<String, dynamic> toJson() => {
    'current_password': currentPassword,
    'password': password,
    'password_confirmation': passwordConfirmation,
  };
}

class AuthUser {
  final String id;
  final String name;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String role;
  final bool isActive;
  final String? emailVerifiedAt;
  final bool isVerified;
  final String? createdAt;

  const AuthUser({
    required this.id,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.emailVerifiedAt,
    required this.isVerified,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final fullName = (json['name'] as String? ?? '').trim();
    final nameParts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    return AuthUser(
      id: json['id']?.toString() ?? '',
      name: fullName,
      firstName: firstName,
      lastName: lastName,
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      role: json['role']?.toString() ?? 'user',
      isActive: json['is_active'] as bool? ?? true,
      emailVerifiedAt: json['email_verified_at']?.toString(),
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at']?.toString(),
    );
  }
}

class AuthPayload {
  final AuthUser? user;
  final String? token;
  final bool emailVerificationRequired;

  const AuthPayload({
    required this.user,
    required this.token,
    required this.emailVerificationRequired,
  });

  factory AuthPayload.fromJson(Map<String, dynamic> json) {
    final userJson = (json['user'] as Map?)?.cast<String, dynamic>();
    return AuthPayload(
      user: userJson != null ? AuthUser.fromJson(userJson) : null,
      token: json['token']?.toString(),
      emailVerificationRequired:
          json['email_verification_required'] as bool? ?? false,
    );
  }
}

class AuthResponse {
  final bool success;
  final String message;
  final AuthPayload data;

  const AuthResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  AuthUser? get user => data.user;
  String? get token => data.token;
  bool get emailVerificationRequired => data.emailVerificationRequired;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final data =
        (json['data'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return AuthResponse(
      success: json['success'] as bool? ?? false,
      message: json['message']?.toString() ?? '',
      data: AuthPayload.fromJson(data),
    );
  }
}

class MessageResponse {
  final bool success;
  final String message;

  const MessageResponse({required this.success, required this.message});

  factory MessageResponse.fromJson(Map<String, dynamic> json) {
    return MessageResponse(
      success: json['success'] as bool? ?? false,
      message: json['message']?.toString() ?? '',
    );
  }
}

class CurrentUserResponse {
  final bool success;
  final AuthUser? user;

  const CurrentUserResponse({required this.success, required this.user});

  factory CurrentUserResponse.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>();
    return CurrentUserResponse(
      success: json['success'] as bool? ?? false,
      user: data != null ? AuthUser.fromJson(data) : null,
    );
  }
}

class AuthSession {
  final AuthUser? user;
  final String token;

  const AuthSession({required this.user, required this.token});

  bool get isLoggedIn => token.trim().isNotEmpty;
  bool get isVerified => user?.isVerified ?? false;

  AuthSession copyWith({AuthUser? user, String? token}) {
    return AuthSession(
      user: user ?? this.user,
      token: token ?? this.token,
    );
  }

  static const empty = AuthSession(user: null, token: '');
}
