class RegisterRequest {
  final String firstName;
  final String lastName;
  final String email;
  final String password;

  const RegisterRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'password': password,
  };
}

class RegisteredUser {
  final String userId;
  final String firstName;
  final String lastName;
  final String email;

  const RegisteredUser({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  factory RegisteredUser.fromJson(Map<String, dynamic> json) => RegisteredUser(
    userId: json['user_id'] as String,
    firstName: json['first_name'] as String,
    lastName: json['last_name'] as String,
    email: json['email'] as String,
  );
}

class RegisterResponse {
  final bool success;
  final String message;
  final RegisteredUser? user;

  const RegisterResponse({
    required this.success,
    required this.message,
    this.user,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      RegisterResponse(
        success: json['success'] as bool,
        message: json['message'] as String,
        user: json['user'] != null
            ? RegisteredUser.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );
}

class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class LoginResponse {
  final bool success;
  final String message;
  final int httpCode;
  final bool requires2fa;
  final String? redirect;

  const LoginResponse({
    required this.success,
    required this.message,
    required this.httpCode,
    required this.requires2fa,
    this.redirect,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    success: json['success'] as bool,
    message: json['message'] as String,
    httpCode: json['http_code'] as int? ?? 200,
    requires2fa: json['requires_2fa'] as bool? ?? false,
    redirect: json['redirect'] as String?,
  );
}
