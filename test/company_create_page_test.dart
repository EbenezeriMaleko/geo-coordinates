import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/company_create_page.dart';
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
  WorkspaceState build() => const WorkspaceState(
    companies: [
      CompanyWorkspace(id: 4, name: 'Current company', role: 'employee'),
    ],
    activeCompanyId: 4,
  );
  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

class _Create extends CompanyCreateService {
  int calls = 0;
  Map<String, dynamic>? input;
  Object? failure;
  @override
  Future<CompanyWorkspace> create(
    String token,
    Map<String, dynamic> input,
  ) async {
    calls++;
    this.input = input;
    if (failure != null) throw failure!;
    return const CompanyWorkspace(
      id: 9,
      name: 'New survey company',
      role: 'owner',
    );
  }
}

Widget creation(
  CompanyCreateService service, {
  ValueChanged<CompanyWorkspace?>? onResult,
}) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Workspace.new),
    companyCreateServiceProvider.overrideWithValue(service),
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
            final result = await Navigator.of(context).push<CompanyWorkspace>(
              MaterialPageRoute(builder: (_) => const CompanyCreatePage()),
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

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(
    find.widgetWithText(FilledButton, 'Create company'),
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Create company'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _Workspace.refreshes = 0);
  test(
    'server creation response yields owner workspace without changing context',
    () async {
      final company = await http.runWithClient(
        () => CompanyCreateService().create('synthetic', {'name': 'Survey'}),
        () => MockClient(
          (request) async =>
              http.Response('{"data":{"id":9,"name":"Survey"}}', 201),
        ),
      );
      expect(company.id, 9);
      expect(company.role, 'owner');
    },
  );
  test('ambiguous creation response requires checking workspaces', () async {
    await expectLater(
      http.runWithClient(
        () => CompanyCreateService().create('synthetic', {'name': 'Survey'}),
        () => MockClient((request) async => http.Response('{}', 201)),
      ),
      throwsA(isA<CompanyCreationUnconfirmed>()),
    );
    await expectLater(
      http.runWithClient(
        () => CompanyCreateService().create('synthetic', {'name': 'Survey'}),
        () => MockClient(
          (request) async => http.Response('Gateway failure', 502),
        ),
      ),
      throwsA(isA<CompanyCreationUnconfirmed>()),
    );
  });
  testWidgets(
    'creation refreshes companies without switching current workspace',
    (tester) async {
      final service = _Create();
      CompanyWorkspace? result;
      await open(
        tester,
        creation(service, onResult: (value) => result = value),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CompanyCreatePage)),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        ' New survey company ',
      );
      await submit(tester);
      expect(service.input, {'name': 'New survey company'});
      expect(result?.role, 'owner');
      expect(_Workspace.refreshes, 1);
      expect(container.read(workspaceProvider).activeCompanyId, 4);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty company name is rejected locally', (tester) async {
    final service = _Create();
    await open(tester, creation(service));
    await submit(tester);
    expect(service.calls, 0);
    expect(find.text('Enter the company name'), findsOneWidget);
  });
  testWidgets('server validation error preserves entered company fields', (
    tester,
  ) async {
    final service = _Create()
      ..failure = Exception('The email must be a valid email address.');
    await open(tester, creation(service));
    await tester.enterText(
      find.byType(TextFormField).first,
      'New survey company',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'invalid');
    await submit(tester);
    expect(
      find.text('The email must be a valid email address.'),
      findsOneWidget,
    );
    expect(find.text('New survey company'), findsOneWidget);
    expect(find.text('invalid'), findsOneWidget);
    expect(_Workspace.refreshes, 0);
  });
  testWidgets('uncertain creation prevents duplicate submission', (
    tester,
  ) async {
    final service = _Create()..failure = const CompanyCreationUnconfirmed();
    await open(tester, creation(service));
    await tester.enterText(
      find.byType(TextFormField).first,
      'New survey company',
    );
    await submit(tester);
    expect(service.calls, 1);
    expect(find.widgetWithText(FilledButton, 'Create company'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Check workspaces'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Check workspaces'), findsOneWidget);
    await tester.ensureVisible(find.text('Check workspaces'));
    await tester.tap(find.text('Check workspaces'));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(_Workspace.refreshes, 1);
  });
  testWidgets('company creation fits narrow enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, creation(_Create()));
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create company'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
