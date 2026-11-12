import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/company_invite_form.dart';
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
    companies: [CompanyWorkspace(id: 1, name: 'Survey company', role: 'owner')],
    activeCompanyId: 1,
  );
}

class _Invite extends CompanyInviteService {
  List<String> allowed = ['reviewer'];
  String? failure;
  bool? delivered = false;
  int calls = 0;
  String? invitedRole;
  @override
  Future<List<String>> roles(String token, int company) async => allowed;
  @override
  Future<List<Map<String, dynamic>>> search(
    String token,
    int company,
    String query,
  ) async => [
    {'id': 7, 'name': 'Surveyor Jane', 'email': 'jane@example.test'},
  ];
  @override
  Future<bool?> invite(String token, int company, int user, String role) async {
    calls++;
    invitedRole = role;
    if (failure != null) throw Exception(failure);
    return delivered;
  }
}

Widget form(CompanyInviteService service, {ValueChanged<String?>? onResult}) =>
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(_Session.new),
        workspaceProvider.overrideWith(_Company.new),
        companyInviteServiceProvider.overrideWithValue(service),
        entitlementProvider.overrideWith(
          (ref) async => {
            'company.employee_management': const FeatureDecision(
              allowed: true,
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
        home: onResult == null
            ? const CompanyInviteForm(company: 1)
            : Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      onResult(
                        await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const CompanyInviteForm(company: 1),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
      ),
    );

Future<void> selectAccount(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'ja');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Surveyor Jane'));
  await tester.pumpAndSettle();
}

void main() {
  test('invitation role parsing excludes owner and unknown roles', () {
    expect(
      parseCompanyInvitationRoles(['owner', 'reviewer', 'unknown', 'reviewer']),
      ['reviewer'],
    );
    expect(parseCompanyInvitationRoles(null), isEmpty);
    expect(parseCompanyInvitationRoles([]), isEmpty);
  });
  testWidgets(
    'email failure still reports created invitation and uses configured role',
    (tester) async {
      final service = _Invite();
      String? result;
      await tester.pumpWidget(
        form(service, onResult: (value) => result = value),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await selectAccount(tester);
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(service.invitedRole, 'reviewer');
      expect(result, contains('Invitation created. Email delivery failed'));
      expect(result, contains('accept it in the app'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('server rejection retains selected account and shows error', (
    tester,
  ) async {
    final service = _Invite()
      ..failure = 'This user already has a pending invitation.';
    await tester.pumpWidget(form(service));
    await tester.pumpAndSettle();
    await selectAccount(tester);
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();
    expect(
      find.text('This user already has a pending invitation.'),
      findsOneWidget,
    );
    expect(find.text('Surveyor Jane'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('typing a different search clears the selected account', (
    tester,
  ) async {
    await tester.pumpWidget(form(_Invite()));
    await tester.pumpAndSettle();
    await selectAccount(tester);
    await tester.enterText(find.byType(TextField), 'x');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear selected account'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send invitation'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets(
    'empty configured roles disable sending and fit narrow enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(form(_Invite()..allowed = []));
      await tester.pumpAndSettle();
      expect(
        find.text('No invitation roles are enabled in the company plan.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send invitation'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
