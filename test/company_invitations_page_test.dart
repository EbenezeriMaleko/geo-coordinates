import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/company_invitations_page.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Workspace extends WorkspaceNotifier {
  static int refreshes = 0;
  @override
  WorkspaceState build() => const WorkspaceState.personal();
  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

class _Invitations extends CompanyInvitationService {
  int calls = 0;
  bool? accepted;
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> pending(String token) async =>
      accepted != null
      ? []
      : [
          {
            'id': 1,
            'company': {'name': 'Northern survey company'},
            'role': 'reviewer',
            'inviter': {'name': 'Company owner'},
            'expires_at': '2026-11-12T09:00:00Z',
          },
        ];
  @override
  Future<void> respond(String token, int id, bool accept) async {
    calls++;
    if (fail) throw Exception('No company seats available.');
    accepted = accept;
  }
}

Widget page(CompanyInvitationService service) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Workspace.new),
    companyInvitationServiceProvider.overrideWithValue(service),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const CompanyInvitationsPage(),
  ),
);

void main() {
  setUp(() => _Workspace.refreshes = 0);
  testWidgets(
    'accept confirms, refreshes company choices and keeps current workspace',
    (tester) async {
      final service = _Invitations();
      await tester.pumpWidget(page(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept invitation').last);
      await tester.pumpAndSettle();
      expect(service.accepted, isTrue);
      expect(_Workspace.refreshes, 1);
      expect(find.text('No pending invitations.'), findsOneWidget);
      final context = tester.element(find.byType(CompanyInvitationsPage));
      expect(
        ProviderScope.containerOf(
          context,
        ).read(workspaceProvider).activeCompanyId,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel leaves invitation pending on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Invitations();
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    expect(find.text('Reviewer'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('Northern survey company'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decline removes invitation without refreshing company choices', (
    tester,
  ) async {
    final service = _Invitations();
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline invitation').last);
    await tester.pumpAndSettle();
    expect(service.accepted, isFalse);
    expect(_Workspace.refreshes, 0);
    expect(find.text('No pending invitations.'), findsOneWidget);
  });

  testWidgets(
    'failed acceptance keeps invitation and shows server explanation',
    (tester) async {
      final service = _Invitations()..fail = true;
      await tester.pumpWidget(page(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept invitation').last);
      await tester.pumpAndSettle();
      expect(service.accepted, isNull);
      expect(find.text('No company seats available.'), findsOneWidget);
      expect(find.text('Accept invitation'), findsOneWidget);
      expect(_Workspace.refreshes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
