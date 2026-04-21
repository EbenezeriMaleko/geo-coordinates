import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_models.dart';
import '../services/auth_service.dart';
import '../services/auth_session_store.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authSessionStoreProvider = Provider<AuthSessionStore>(
  (ref) => AuthSessionStore(),
);

class AuthSessionNotifier extends Notifier<AuthSession> {
  @override
  AuthSession build() {
    return ref.read(authSessionStoreProvider).read();
  }

  Future<void> setFromAuthResponse(AuthResponse response) async {
    final next = AuthSession(
      user: response.user,
      token: response.token?.trim() ?? '',
    );
    await ref.read(authSessionStoreProvider).save(next);
    state = next;
  }

  Future<void> setUser(AuthUser user) async {
    final next = state.copyWith(user: user);
    await ref.read(authSessionStoreProvider).save(next);
    state = next;
  }

  Future<void> refreshCurrentUser() async {
    final token = state.token.trim();
    if (token.isEmpty) return;
    final result = await ref.read(authServiceProvider).me(token);
    if (result.user == null) return;
    await setUser(result.user!);
  }

  Future<void> logout() async {
    final token = state.token.trim();
    if (token.isNotEmpty) {
      try {
        await ref.read(authServiceProvider).logout(token);
      } catch (_) {
        // Local logout should still succeed if the remote call fails.
      }
    }
    await ref.read(authSessionStoreProvider).clear();
    state = AuthSession.empty;
  }
}

final authSessionProvider =
    NotifierProvider<AuthSessionNotifier, AuthSession>(
      AuthSessionNotifier.new,
    );

class LoginNotifier extends AsyncNotifier<AuthResponse?> {
  @override
  Future<AuthResponse?> build() async => null;

  Future<AuthResponse?> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref
          .read(authServiceProvider)
          .login(LoginRequest(email: email, password: password));
      await ref.read(authSessionProvider.notifier).setFromAuthResponse(result);
      return result;
    });
    return switch (state) {
      AsyncData<AuthResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final loginProvider = AsyncNotifierProvider<LoginNotifier, AuthResponse?>(
  LoginNotifier.new,
);

class RegisterNotifier extends AsyncNotifier<AuthResponse?> {
  @override
  Future<AuthResponse?> build() async => null;

  Future<AuthResponse?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref
          .read(authServiceProvider)
          .register(
            RegisterRequest(
              firstName: firstName,
              lastName: lastName,
              email: email,
              password: password,
              phone: phone,
            ),
          );
      await ref.read(authSessionProvider.notifier).setFromAuthResponse(result);
      return result;
    });
    return switch (state) {
      AsyncData<AuthResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final registerProvider = AsyncNotifierProvider<RegisterNotifier, AuthResponse?>(
  RegisterNotifier.new,
);

class ForgotPasswordNotifier extends AsyncNotifier<MessageResponse?> {
  @override
  Future<MessageResponse?> build() async => null;

  Future<MessageResponse?> submit(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authServiceProvider)
          .forgotPassword(ForgotPasswordRequest(email: email)),
    );
    return switch (state) {
      AsyncData<MessageResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final forgotPasswordProvider =
    AsyncNotifierProvider<ForgotPasswordNotifier, MessageResponse?>(
      ForgotPasswordNotifier.new,
    );

class ResetPasswordNotifier extends AsyncNotifier<MessageResponse?> {
  @override
  Future<MessageResponse?> build() async => null;

  Future<MessageResponse?> submit({
    required String token,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authServiceProvider)
          .resetPassword(
            ResetPasswordRequest(
              token: token,
              email: email,
              password: password,
              passwordConfirmation: passwordConfirmation,
            ),
          ),
    );
    return switch (state) {
      AsyncData<MessageResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final resetPasswordProvider =
    AsyncNotifierProvider<ResetPasswordNotifier, MessageResponse?>(
      ResetPasswordNotifier.new,
    );

class CurrentUserNotifier extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    return ref.watch(authSessionProvider).user;
  }

  Future<AuthUser?> refresh() async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn) {
      state = const AsyncData(null);
      return null;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(authServiceProvider).me(session.token);
      final user = result.user;
      if (user != null) {
        await ref.read(authSessionProvider.notifier).setUser(user);
      }
      return user;
    });
    return switch (state) {
      AsyncData<AuthUser?>(:final value) => value,
      _ => null,
    };
  }
}

final currentUserProvider =
    AsyncNotifierProvider<CurrentUserNotifier, AuthUser?>(
      CurrentUserNotifier.new,
    );

class UpdateProfileNotifier extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async => null;

  Future<AuthUser?> submit({
    required String name,
    required String email,
    String? phone,
  }) async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref
          .read(authServiceProvider)
          .updateProfile(
            token,
            UpdateProfileRequest(name: name, email: email, phone: phone),
          );
      final user = result.user;
      if (user != null) {
        await ref.read(authSessionProvider.notifier).setUser(user);
      }
      return user;
    });
    return switch (state) {
      AsyncData<AuthUser?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final updateProfileProvider =
    AsyncNotifierProvider<UpdateProfileNotifier, AuthUser?>(
      UpdateProfileNotifier.new,
    );

class ChangePasswordNotifier extends AsyncNotifier<MessageResponse?> {
  @override
  Future<MessageResponse?> build() async => null;

  Future<MessageResponse?> submit({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final token = ref.read(authSessionProvider).token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authServiceProvider)
          .changePassword(
            token,
            ChangePasswordRequest(
              currentPassword: currentPassword,
              password: password,
              passwordConfirmation: passwordConfirmation,
            ),
          ),
    );
    return switch (state) {
      AsyncData<MessageResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final changePasswordProvider =
    AsyncNotifierProvider<ChangePasswordNotifier, MessageResponse?>(
      ChangePasswordNotifier.new,
    );

class ResendVerificationNotifier extends AsyncNotifier<MessageResponse?> {
  @override
  Future<MessageResponse?> build() async => null;

  Future<MessageResponse?> send() async {
    final token = ref.read(authSessionProvider).token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).resendVerificationEmail(token),
    );
    return switch (state) {
      AsyncData<MessageResponse?>(:final value) => value,
      _ => null,
    };
  }

  void reset() => state = const AsyncData(null);
}

final resendVerificationProvider =
    AsyncNotifierProvider<ResendVerificationNotifier, MessageResponse?>(
      ResendVerificationNotifier.new,
    );
