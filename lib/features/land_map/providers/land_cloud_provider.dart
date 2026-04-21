import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../auth/services/auth_service.dart';
import '../models/land_api_models.dart';
import '../services/land_cloud_service.dart';

final landCloudServiceProvider = Provider<LandCloudService>(
  (ref) => LandCloudService(),
);

class RemoteLandsNotifier extends AsyncNotifier<PaginatedLands?> {
  @override
  Future<PaginatedLands?> build() async => null;

  Future<PaginatedLands?> fetch({
    String? search,
    int perPage = 15,
    int page = 1,
  }) async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }
    if (!session.isVerified) {
      throw const AuthException('Verify your email before cloud access.');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(landCloudServiceProvider).listLands(
            token,
            search: search,
            perPage: perPage,
            page: page,
          ),
    );
    return switch (state) {
      AsyncData<PaginatedLands?>(:final value) => value,
      _ => null,
    };
  }
}

final remoteLandsProvider =
    AsyncNotifierProvider<RemoteLandsNotifier, PaginatedLands?>(
      RemoteLandsNotifier.new,
    );

class RemoteLandSummaryNotifier extends AsyncNotifier<LandSummary?> {
  @override
  Future<LandSummary?> build() async => null;

  Future<LandSummary?> fetch() async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }
    if (!session.isVerified) {
      throw const AuthException('Verify your email before cloud access.');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(landCloudServiceProvider).summary(token),
    );
    return switch (state) {
      AsyncData<LandSummary?>(:final value) => value,
      _ => null,
    };
  }
}

final remoteLandSummaryProvider =
    AsyncNotifierProvider<RemoteLandSummaryNotifier, LandSummary?>(
      RemoteLandSummaryNotifier.new,
    );

class RemoteSettingsNotifier extends AsyncNotifier<RemoteSettingsOptions?> {
  @override
  Future<RemoteSettingsOptions?> build() async => null;

  Future<RemoteSettingsOptions?> fetch() async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }
    if (!session.isVerified) {
      throw const AuthException('Verify your email before cloud access.');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(landCloudServiceProvider).getSettings(token),
    );
    return switch (state) {
      AsyncData<RemoteSettingsOptions?>(:final value) => value,
      _ => null,
    };
  }
}

final remoteSettingsProvider =
    AsyncNotifierProvider<RemoteSettingsNotifier, RemoteSettingsOptions?>(
      RemoteSettingsNotifier.new,
    );

final remoteLandDetailProvider =
    FutureProvider.autoDispose.family<LandDetail, String>((ref, landId) async {
      final session = ref.read(authSessionProvider);
      final token = session.token.trim();
      if (token.isEmpty) {
        throw const AuthException('Sign in is required.');
      }
      if (!session.isVerified) {
        throw const AuthException('Verify your email before cloud access.');
      }
      return ref.read(landCloudServiceProvider).getLand(token, landId);
    });
