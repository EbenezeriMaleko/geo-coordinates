import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/organization_page.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';

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
    companies: [
      CompanyWorkspace(id: 1, name: 'Survey Company', role: 'employee'),
    ],
    activeCompanyId: 1,
  );
}

void main() {
  testWidgets('project form can cancel and reopen during route animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(_Company.new),
          authSessionProvider.overrideWith(_Session.new),
          workspacePermissionsProvider.overrideWith(
            (ref) async => {'organization.manage': true},
          ),
          organizationPageProvider.overrideWith(
            (ref, query) async => {
              'can_write': true,
              'items': {'data': [], 'last_page': 1},
            },
          ),
        ],
        child: const MaterialApp(home: OrganizationPage()),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Test project');
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Create project'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'employees can read roster without membership management controls',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceProvider.overrideWith(_Company.new),
            workspacePermissionsProvider.overrideWith((ref) async => {}),
            organizationPageProvider.overrideWith(
              (ref, query) async => {
                'can_manage': false,
                'can_write': false,
                'members': {
                  'data': [
                    {
                      'id': 3,
                      'name': 'Field surveyor',
                      'email': 'surveyor@example.test',
                      'active': true,
                    },
                  ],
                  'last_page': 1,
                },
              },
            ),
          ],
          child: const MaterialApp(
            home: OrganizationPage(teamId: 2, teamName: 'Survey team'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Field surveyor'), findsOneWidget);
      expect(find.byTooltip('Remove from team'), findsNothing);
      expect(find.text('Add member'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('company projects fit narrow screens with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(_Company.new),
          workspacePermissionsProvider.overrideWith((ref) async => {}),
          organizationPageProvider.overrideWith(
            (ref, query) async => {
              'items': {
                'data': [
                  {
                    'id': 2,
                    'name': 'Northern district boundary survey',
                    'description': 'Scheduled survey work',
                    'archived_at': null,
                  },
                ],
                'last_page': 1,
              },
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
          home: const OrganizationPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Northern district boundary survey'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Page 1 of 1'), findsOneWidget);
  });
}
