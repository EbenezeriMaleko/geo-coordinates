import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taref_gps/core/network/api_client.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_context.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
  void signOut() => state = AuthSession.empty;
}

class _Service extends WorkspaceService {
  final requests = <Completer<List<CompanyWorkspace>>>[];
  @override
  Future<List<CompanyWorkspace>> companies(String token) {
    final request = Completer<List<CompanyWorkspace>>();
    requests.add(request);
    return request.future;
  }
}

const companies = [CompanyWorkspace(id: 1, name: 'Survey', role: 'reviewer')];

void main() {
  late Directory directory;
  late ProviderContainer container;
  late _Service service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('workspace_refresh_');
    Hive.init(directory.path);
    await Hive.openBox('landbox');
    service = _Service();
    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_Session.new),
        workspaceServiceProvider.overrideWithValue(service),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    ApiClient.setActiveCompanyId(null);
    await directory.delete(recursive: true);
  });

  test('older refresh cannot overwrite the newest company list', () async {
    final notifier = container.read(workspaceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    final latest = notifier.refresh();
    service.requests[1].complete(companies);
    await latest;
    service.requests[0].complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(workspaceProvider).companies.single.name, 'Survey');
    expect(container.read(workspaceProvider).isLoading, isFalse);
  });

  test('late refresh cannot clear a newly selected company', () async {
    final notifier = container.read(workspaceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    service.requests[0].complete(companies);
    await Future<void>.delayed(Duration.zero);
    final pending = notifier.refresh();
    await notifier.selectCompany(1);
    service.requests[1].complete([]);
    await pending;
    expect(container.read(workspaceProvider).activeCompanyId, 1);
    expect(WorkspaceContext.activeCompanyId, 1);
    expect(ApiClient.jsonHeaders()['X-Company-Id'], '1');
  });

  test('late refresh cannot restore company access after logout', () async {
    container.read(workspaceProvider);
    await Future<void>.delayed(Duration.zero);
    (container.read(authSessionProvider.notifier) as _Session).signOut();
    expect(container.read(workspaceProvider).activeCompanyId, isNull);
    service.requests.single.complete(companies);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(workspaceProvider).companies, isEmpty);
    expect(ApiClient.jsonHeaders().containsKey('X-Company-Id'), isFalse);
  });

  test('concurrent workspace selections keep the newest API header', () async {
    final older = WorkspaceContext.selectCompany(1);
    final newer = WorkspaceContext.selectCompany(null);
    await Future.wait([older, newer]);
    expect(WorkspaceContext.activeCompanyId, isNull);
    expect(ApiClient.jsonHeaders().containsKey('X-Company-Id'), isFalse);
  });

  test('advanced company roles have explicit labels', () {
    expect(companyRoleLabel('field_operator'), 'Field operator');
    expect(companyRoleLabel('reviewer'), 'Reviewer');
    expect(companyRoleLabel('viewer'), 'Viewer');
    expect(companyRoleLabel('employee'), 'Employee');
    expect(companyRoleLabel('unknown'), 'Member');
  });
}
