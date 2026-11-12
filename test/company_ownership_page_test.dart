import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/company_ownership_page.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Owner extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey company', role: 'owner')],
    activeCompanyId: 1,
  );
}

class _Admin extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey company', role: 'admin')],
    activeCompanyId: 1,
  );
}

class _Ownership extends CompanyOwnershipService {
  int reads = 0;
  int calls = 0;
  int? target;
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> candidates(
    String token,
    int company,
  ) async {
    reads++;
    return [
      {
        'id': 1,
        'status': 'active',
        'role': 'owner',
        'user': {'name': 'Current owner'},
      },
      {
        'id': '2',
        'status': 'active',
        'role': 'reviewer',
        'user': {'name': 'Surveyor Jane', 'email': 'jane@example.test'},
      },
      {
        'id': 3,
        'status': 'inactive',
        'role': 'employee',
        'user': {'name': 'Inactive member'},
      },
    ];
  }

  @override
  Future<void> transfer(String token, int company, int membership) async {
    calls++;
    target = membership;
    if (fail) throw Exception('The new owner must have an active account.');
  }
}

Widget ownership(
  CompanyOwnershipService service, {
  bool admin = false,
  ValueChanged<bool?>? onResult,
}) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(admin ? _Admin.new : _Owner.new),
    companyOwnershipServiceProvider.overrideWithValue(service),
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
            onResult?.call(
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const CompanyOwnershipPage(company: 1),
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
Future<void> open(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only eligible members show and transfer requires confirmation', (
    tester,
  ) async {
    final service = _Ownership();
    bool? result;
    await open(tester, ownership(service, onResult: (value) => result = value));
    expect(find.text('Current owner'), findsNothing);
    expect(find.text('Inactive member'), findsNothing);
    await tester.tap(find.text('Surveyor Jane'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer ownership'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer ownership'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Transfer ownership').last,
    );
    await tester.pumpAndSettle();
    expect(service.target, 2);
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ordinary company admin cannot open ownership transfer', (
    tester,
  ) async {
    final service = _Ownership();
    await open(tester, ownership(service, admin: true, onResult: (_) {}));
    expect(service.reads, 0);
    expect(find.text('Surveyor Jane'), findsNothing);
  });
  testWidgets(
    'failed transfer retains selected member and shows server reason',
    (tester) async {
      final service = _Ownership()..fail = true;
      await open(tester, ownership(service, onResult: (_) {}));
      await tester.tap(find.text('Surveyor Jane'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer ownership'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Transfer ownership').last,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The new owner must have an active account.'),
        findsOneWidget,
      );
      expect(
        tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ownership selector fits narrow enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, ownership(_Ownership(), onResult: (_) {}));
    expect(tester.takeException(), isNull);
  });
  test('platform admin override still requires an active company context', () {
    expect(
      canTransferCompanyOwnership(const WorkspaceState.personal(), 'admin'),
      isFalse,
    );
    expect(
      canTransferCompanyOwnership(
        const WorkspaceState(companies: [], activeCompanyId: 1),
        'admin',
      ),
      isTrue,
    );
  });
}
