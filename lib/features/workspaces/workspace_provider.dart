import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_context.dart';

String companyRoleLabel(String? role) => switch (role) {
  'owner' => 'Owner',
  'admin' => 'Administrator',
  'employee' => 'Employee',
  'field_operator' => 'Field operator',
  'reviewer' => 'Reviewer',
  'viewer' => 'Viewer',
  _ => 'Member',
};

class WorkspaceService {
  Future<List<CompanyWorkspace>> companies(String token) async {
    final response = await ApiClient.getJson(
      '/companies',
      bearerToken: token,
      tag: 'workspaces_list',
    );
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to load workspaces.'
            : 'Unable to load workspaces.',
      );
    }
    if (body is! Map || body['data'] is! List) {
      throw Exception('Unexpected workspace response. Please retry.');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((item) => CompanyWorkspace.fromJson(item.cast<String, dynamic>()))
        .where((company) => company.id > 0 && company.name.isNotEmpty)
        .toList();
  }
}

final workspaceServiceProvider = Provider<WorkspaceService>(
  (ref) => WorkspaceService(),
);

bool canViewCompanyDirectory(WorkspaceState workspace, String? platformRole) =>
    workspace.activeCompanyId != null &&
    !workspace.isLoading &&
    (platformRole == 'admin' ||
        const ['owner', 'admin'].contains(workspace.activeCompany?.role));

bool canTransferCompanyOwnership(
  WorkspaceState workspace,
  String? platformRole,
) =>
    workspace.activeCompanyId != null &&
    !workspace.isLoading &&
    (platformRole == 'admin' || workspace.activeCompany?.role == 'owner');

class CompanyWorkspace {
  final int id;
  final String name;
  final String role;

  const CompanyWorkspace({
    required this.id,
    required this.name,
    required this.role,
  });

  factory CompanyWorkspace.fromJson(Map<String, dynamic> json) {
    final company =
        (json['company'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CompanyWorkspace(
      id: (company['id'] as num?)?.toInt() ?? 0,
      name: company['name']?.toString().trim() ?? '',
      role: json['role']?.toString() ?? 'employee',
    );
  }
}

class WorkspaceState {
  final List<CompanyWorkspace> companies;
  final int? activeCompanyId;
  final bool isLoading;
  final String? error;

  const WorkspaceState({
    required this.companies,
    required this.activeCompanyId,
    this.isLoading = false,
    this.error,
  });

  const WorkspaceState.personal()
    : companies = const [],
      activeCompanyId = null,
      isLoading = false,
      error = null;

  CompanyWorkspace? get activeCompany {
    for (final company in companies) {
      if (company.id == activeCompanyId) return company;
    }
    return null;
  }

  String get label => activeCompany?.name ?? 'Personal workspace';

  WorkspaceState copyWith({
    List<CompanyWorkspace>? companies,
    int? activeCompanyId,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return WorkspaceState(
      companies: companies ?? this.companies,
      activeCompanyId: activeCompanyId ?? this.activeCompanyId,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class WorkspaceNotifier extends Notifier<WorkspaceState> {
  int _generation = 0;

  bool _current(int generation, String token) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(authSessionProvider).token == token &&
      ref.read(authSessionProvider).isVerified;

  @override
  WorkspaceState build() {
    ref.watch(
      authSessionProvider.select((s) => (s.token, s.isVerified, s.user?.id)),
    );
    _generation++;
    WorkspaceContext.restore();
    final state = WorkspaceState(
      companies: const [],
      activeCompanyId: WorkspaceContext.activeCompanyId,
    );
    final session = ref.read(authSessionProvider);
    if (session.isLoggedIn && session.isVerified) {
      Future.microtask(() {
        if (ref.mounted) refresh();
      });
    } else {
      ApiClient.setActiveCompanyId(null);
      return const WorkspaceState.personal();
    }
    return state;
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) {
      state = const WorkspaceState.personal();
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final companies = await ref
          .read(workspaceServiceProvider)
          .companies(session.token);
      if (!_current(generation, session.token)) return;
      final activeId = WorkspaceContext.activeCompanyId;
      if (activeId != null &&
          !companies.any((company) => company.id == activeId)) {
        await WorkspaceContext.selectCompany(null);
      }
      if (!_current(generation, session.token)) return;
      state = WorkspaceState(
        companies: companies,
        activeCompanyId: WorkspaceContext.activeCompanyId,
      );
    } catch (error) {
      if (!_current(generation, session.token)) return;
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> selectCompany(int? companyId) async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;
    if (companyId != null &&
        !state.companies.any((company) => company.id == companyId)) {
      return;
    }
    final generation = ++_generation;
    await WorkspaceContext.selectCompany(companyId);
    if (!_current(generation, session.token)) return;
    state = WorkspaceState(
      companies: state.companies,
      activeCompanyId: companyId,
    );
  }
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(
  WorkspaceNotifier.new,
);
