import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_identity_bar.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({
      'id': 1,
      'name': 'Test User',
      'is_verified': true,
    }),
    token: 'synthetic',
  );
}

class _SignedOut extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession.empty;
}

class _Workspace extends WorkspaceNotifier {
  static const companies = [
    CompanyWorkspace(
      id: 2,
      name: 'Northern Region Surveying and Engineering Company',
      role: 'owner',
    ),
  ];
  @override
  WorkspaceState build() =>
      const WorkspaceState(companies: companies, activeCompanyId: 2);
  @override
  Future<void> selectCompany(int? id) async {
    state = WorkspaceState(companies: companies, activeCompanyId: id);
  }
}

class _LoadingWorkspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: _Workspace.companies,
    activeCompanyId: 2,
    isLoading: true,
  );
}

void main() {
  testWidgets('workspace refresh disables switching and company shortcuts', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_Session.new),
          workspaceProvider.overrideWith(_LoadingWorkspace.new),
        ],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: WorkspaceIdentityBar()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('workspace controls are hidden when signed out', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(_SignedOut.new)],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: WorkspaceIdentityBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Switch workspace'), findsNothing);
    expect(find.byTooltip('Company tools'), findsNothing);
  });

  testWidgets('company tool menu names destinations clearly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_Session.new),
          workspaceProvider.overrideWith(_Workspace.new),
        ],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: WorkspaceIdentityBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Company tools'));
    await tester.pumpAndSettle();
    expect(find.text('Projects & Teams'), findsOneWidget);
    expect(find.text('Field jobs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('company identity fits enlarged text and switches to personal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_Session.new),
          workspaceProvider.overrideWith(_Workspace.new),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(bottomNavigationBar: WorkspaceIdentityBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Company · Owner'), findsOneWidget);
    expect(find.byTooltip('Company tools'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Switch workspace'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CheckedPopupMenuItem<int>).first);
    await tester.pumpAndSettle();
    expect(find.text('My workspace'), findsOneWidget);
    expect(find.byTooltip('Company tools'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
