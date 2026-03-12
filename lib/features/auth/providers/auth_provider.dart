import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_models.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// ── Login ────────────────────────────────────────────────────────────────────

class LoginNotifier extends AsyncNotifier<LoginResponse?> {
  @override
  Future<LoginResponse?> build() async => null;

  Future<LoginResponse?> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authServiceProvider)
          .login(LoginRequest(email: email, password: password)),
    );
    return switch (state) {
      AsyncData<LoginResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final loginProvider = AsyncNotifierProvider<LoginNotifier, LoginResponse?>(
  LoginNotifier.new,
);

// ── Register ─────────────────────────────────────────────────────────────────

class RegisterNotifier extends AsyncNotifier<RegisterResponse?> {
  @override
  Future<RegisterResponse?> build() async => null;

  Future<RegisterResponse?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authServiceProvider)
          .register(
            RegisterRequest(
              firstName: firstName,
              lastName: lastName,
              email: email,
              password: password,
            ),
          ),
    );
    return switch (state) {
      AsyncData<RegisterResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final registerProvider =
    AsyncNotifierProvider<RegisterNotifier, RegisterResponse?>(
      RegisterNotifier.new,
    );
