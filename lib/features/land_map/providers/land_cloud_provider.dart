import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../auth/services/auth_service.dart';
import '../models/land_api_models.dart';
import '../services/land_cloud_service.dart';
import '../../workspaces/workspace_provider.dart';
import '../../workspaces/library_organization_filter.dart';

const int latestRemoteLandsLimit = 100;
const int latestRemoteLandsPageSize = 20;

final landCloudServiceProvider = Provider<LandCloudService>(
  (ref) => LandCloudService(),
);

class RemoteLandsNotifier extends AsyncNotifier<PaginatedLands?> {
  int _generation = 0;
  @override
  Future<PaginatedLands?> build() async {
    ref.watch(workspaceProvider.select((s) => s.activeCompanyId));
    ref.watch(authSessionProvider);
    ref.watch(libraryOrganizationFilterProvider);
    _generation++;
    return null;
  }

  Future<PaginatedLands?> fetch({
    String? search,
    int perPage = latestRemoteLandsPageSize,
    int page = 1,
    int limit = latestRemoteLandsLimit,
  }) async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }
    if (!session.isVerified) {
      throw const AuthException('Verify your email before cloud access.');
    }

    final generation = ++_generation;
    state = const AsyncLoading();
    final outcome = await AsyncValue.guard(() async {
      final service = ref.read(landCloudServiceProvider);
      final maxItems = limit <= 0 ? latestRemoteLandsLimit : limit;
      final pageSize = perPage <= 0 ? maxItems : min(perPage, maxItems);
      final result = await service.listLands(
        token,
        search: search,
        perPage: pageSize,
        page: page,
        projectId: ref.read(libraryOrganizationFilterProvider).project,
        teamId: ref.read(libraryOrganizationFilterProvider).team,
      );

      final items = <LandListItem>[];
      final seenIds = <String>{};
      for (final item in result.items) {
        if (items.length >= maxItems) break;
        final id = item.id.trim();
        if (id.isNotEmpty && !seenIds.add(id)) continue;
        items.add(item);
      }

      return PaginatedLands(
        items: items,
        total: result.total,
        perPage: result.perPage,
        currentPage: result.currentPage,
        lastPage: result.lastPage,
      );
    });
    if (!ref.mounted || generation != _generation) return null;
    state = outcome;
    return switch (state) {
      AsyncData<PaginatedLands?>(:final value) => value,
      _ => null,
    };
  }

  Future<PaginatedLands?> fetchNextPage({
    String? search,
    int perPage = latestRemoteLandsPageSize,
    int limit = latestRemoteLandsLimit,
  }) async {
    final current = switch (state) {
      AsyncData<PaginatedLands?>(:final value) => value,
      _ => null,
    };
    if (current == null) {
      return fetch(search: search, perPage: perPage, limit: limit);
    }

    final maxItems = limit <= 0 ? latestRemoteLandsLimit : limit;
    if (current.items.length >= maxItems ||
        current.currentPage >= current.lastPage) {
      return current;
    }

    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }
    if (!session.isVerified) {
      throw const AuthException('Verify your email before cloud access.');
    }

    final remaining = maxItems - current.items.length;
    final generation = _generation;
    final pageSize = min(
      perPage <= 0 ? latestRemoteLandsPageSize : perPage,
      remaining,
    ).toInt();
    final result = await ref
        .read(landCloudServiceProvider)
        .listLands(
          token,
          search: search,
          perPage: pageSize,
          page: current.currentPage + 1,
          projectId: ref.read(libraryOrganizationFilterProvider).project,
          teamId: ref.read(libraryOrganizationFilterProvider).team,
        );

    if (!ref.mounted || generation != _generation) return null;
    final seenIds = current.items.map((item) => item.id.trim()).toSet();
    final merged = <LandListItem>[...current.items];
    for (final item in result.items) {
      if (merged.length >= maxItems) break;
      final id = item.id.trim();
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      merged.add(item);
    }

    final next = PaginatedLands(
      items: merged,
      total: result.total,
      perPage: result.perPage,
      currentPage: result.currentPage,
      lastPage: result.lastPage,
    );
    state = AsyncData(next);
    return next;
  }
}

final remoteLandsProvider =
    AsyncNotifierProvider<RemoteLandsNotifier, PaginatedLands?>(
      RemoteLandsNotifier.new,
    );

class RemoteLandSummaryNotifier extends AsyncNotifier<LandSummary?> {
  int _generation = 0;
  @override
  Future<LandSummary?> build() async {
    ref.watch(workspaceProvider.select((s) => s.activeCompanyId));
    ref.watch(authSessionProvider);
    _generation++;
    return null;
  }

  Future<LandSummary?> fetch() async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) {
      throw const AuthException('Sign in is required.');
    }
    if (!session.isVerified) {
      throw const AuthException('Verify your email before cloud access.');
    }

    final generation = ++_generation;
    state = const AsyncLoading();
    final outcome = await AsyncValue.guard(
      () => ref.read(landCloudServiceProvider).summary(token),
    );
    if (!ref.mounted || generation != _generation) return null;
    state = outcome;
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

final remoteLandDetailProvider = FutureProvider.autoDispose
    .family<LandDetail, String>((ref, landId) async {
      ref.watch(workspaceProvider.select((s) => s.activeCompanyId));
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
