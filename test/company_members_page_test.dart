import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/company_members_page.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Manager extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey company', role: 'owner')],
    activeCompanyId: 1,
  );
}

class _Viewer extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [
      CompanyWorkspace(id: 1, name: 'Survey company', role: 'viewer'),
    ],
    activeCompanyId: 1,
  );
}

class _Directory extends CompanyDirectoryService {
  int calls = 0;
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> list(
    String token,
    int company,
    bool pending,
  ) async {
    calls++;
    if (fail) throw Exception('Unavailable');
    return pending
        ? [
            {
              'id': 101,
              'role': 'reviewer',
              'status': 'pending',
              'user': {
                'name': 'Invited surveyor',
                'email': 'pending@example.test',
              },
              'expires_at': '2026-11-12T09:00:00Z',
            },
          ]
        : List.generate(
            100,
            (i) => {
              'id': i + 1,
              'role': 'field_operator',
              'status': 'active',
              'user': {
                'name': 'Member ${i + 1}',
                'email': 'member${i + 1}@example.test',
              },
            },
          );
  }
}

Widget directory(CompanyDirectoryService service, {bool viewer = false}) =>
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(_Session.new),
        workspaceProvider.overrideWith(viewer ? _Viewer.new : _Manager.new),
        companyDirectoryServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const CompanyMembersPage(),
      ),
    );

void main() {
  testWidgets(
    '100 members can page and search without mixing pending invitations',
    (tester) async {
      final service = _Directory();
      await tester.pumpWidget(directory(service));
      await tester.pumpAndSettle();
      expect(find.text('Member 1'), findsOneWidget);
      expect(find.text('Page 1 of 5 (100)'), findsOneWidget);
      await tester.tap(find.byTooltip('Next directory page'));
      await tester.pumpAndSettle();
      expect(find.text('Member 21'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'member99@');
      await tester.pumpAndSettle();
      expect(find.text('Member 99'), findsOneWidget);
      await tester.tap(find.text('Pending invitations'));
      await tester.pumpAndSettle();
      expect(find.text('Invited surveyor'), findsOneWidget);
      expect(find.text('Pending acceptance'), findsOneWidget);
      expect(find.text('Member 99'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('directory fits narrow screens with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(directory(_Directory()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('viewer cannot request manager-only directory', (tester) async {
    final service = _Directory();
    await tester.pumpWidget(directory(service, viewer: true));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('Member 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed directory does not pretend members are empty', (
    tester,
  ) async {
    await tester.pumpWidget(directory(_Directory()..fail = true));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load directory. Retry'), findsOneWidget);
    expect(find.text('No members found.'), findsNothing);
  });
}
