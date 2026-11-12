import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/company_invite_form.dart';
import 'package:taref_gps/features/workspaces/company_member_editor.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Company extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey', role: 'owner')],
    activeCompanyId: 1,
  );
}

class _Members extends CompanyMemberService {
  int calls = 0;
  Map<String, dynamic>? changes;
  String? failure;
  @override
  Future<void> change(
    String token,
    int company,
    int membership,
    Map<String, dynamic>? changes,
  ) async {
    calls++;
    this.changes = changes;
    if (failure != null) throw Exception(failure);
  }
}

Widget editor(
  CompanyMemberService service, {
  bool allowed = false,
  bool active = true,
  String role = 'employee',
  List<String> roles = const ['viewer'],
  ValueChanged<bool?>? onResult,
}) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Company.new),
    companyMemberServiceProvider.overrideWithValue(service),
    companyInviteRolesProvider.overrideWith((ref, company) async => roles),
    entitlementProvider.overrideWith(
      (ref) async => {
        'company.employee_management': FeatureDecision(
          allowed: allowed,
          name: 'Employee management',
        ),
      },
    ),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CompanyMemberEditor(
                  company: 1,
                  member: {
                    'id': 7,
                    'role': role,
                    'status': active ? 'active' : 'inactive',
                    'user': {
                      'id': 3,
                      'name': 'Field surveyor',
                      'email': 'surveyor@example.test',
                    },
                  },
                ),
              ),
            );
            onResult?.call(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

Future<void> open(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'deactivation does not require paid management or rewrite grandfathered role',
    (tester) async {
      final service = _Members();
      bool? result;
      await open(
        tester,
        editor(service, roles: [], onResult: (value) => result = value),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update access'));
      await tester.pumpAndSettle();
      expect(service.changes, {'status': 'inactive'});
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('role changes send only the selected role', (tester) async {
    final service = _Members();
    await open(tester, editor(service, allowed: true));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update access'));
    await tester.pumpAndSettle();
    expect(service.changes, {'role': 'viewer'});
    expect(service.calls, 1);
  });
  testWidgets('seat-limit rejection keeps reactivation form intact', (
    tester,
  ) async {
    final service = _Members()..failure = 'Company seat limit reached.';
    await open(
      tester,
      editor(service, allowed: true, active: false, roles: ['employee']),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update access'));
    await tester.pumpAndSettle();
    expect(service.changes, {'status': 'active'});
    expect(find.text('Company seat limit reached.'), findsOneWidget);
    expect(find.text('Field surveyor'), findsOneWidget);
  });
  testWidgets(
    'removal requires confirmation and cancellation does not mutate',
    (tester) async {
      final service = _Members();
      await open(tester, editor(service));
      await tester.ensureVisible(find.text('Remove member'));
      await tester.tap(find.text('Remove member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await tester.tap(find.text('Remove member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove member').last);
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(service.changes, isNull);
    },
  );
  testWidgets('owner access cannot be changed through member editor', (
    tester,
  ) async {
    final service = _Members();
    await open(tester, editor(service, role: 'owner', allowed: true));
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Remove member'), findsNothing);
    expect(service.calls, 0);
  });
  testWidgets('member editor fits narrow enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, editor(_Members()));
    await tester.scrollUntilVisible(find.text('Remove member'), 100);
    expect(tester.takeException(), isNull);
  });
}
