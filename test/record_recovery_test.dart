import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_context.dart';
import 'package:taref_gps/features/land_map/services/record_recovery_service.dart';
import 'package:taref_gps/features/land_map/ui/record_recovery_page.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Workspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState.personal();
}

class _Recovery extends RecordRecoveryService {
  bool restored = false;
  bool pendingEdits = false;
  bool cacheFailure = false;
  String? failure;
  String? revision;
  int? restoredVersion;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> list(String token, RecoveryQuery query) async =>
      {
        'data': query.record == null
            ? [
                if (!restored)
                  {
                    'id': query.page,
                    'name': 'Deleted plot ${query.page}',
                    'can_restore': true,
                    'deleted_at': '2026-10-30T00:00:00Z',
                    'restore_until': '2026-11-20T00:00:00Z',
                  },
              ]
            : [
                {
                  'id': 8,
                  'record_name': 'Old plot',
                  'point_count': 1,
                  'created_at': '2026-10-30T00:00:00Z',
                  'actor': {'name': 'Surveyor'},
                },
              ],
        'meta': {'last_page': 2},
        'policy': {'enabled': true},
        'can_restore': true,
        'current_revision': 'a' * 64,
      };
  @override
  Future<Map<String, dynamic>> version(
    String token,
    String record,
    int version,
  ) async => {
    'id': version,
    'created_at': '2026-10-30T00:00:00Z',
    'snapshot': {
      'attributes': {'name': 'Old plot', 'type': 'point'},
      'points': [
        {'point_order': 1, 'x': 39.2, 'y': -6.7},
      ],
    },
  };
  @override
  bool pending(String record) => pendingEdits;
  @override
  Future<void> restore(
    String token,
    String record, {
    int? version,
    String? revision,
  }) async {
    calls++;
    this.revision = revision;
    restoredVersion = version;
    if (failure != null) throw Exception(failure);
    restored = true;
  }

  @override
  Future<void> refreshCache(String token, int? company, String record) async {
    if (cacheFailure) throw Exception('Offline');
  }
}

Widget recovery(
  RecordRecoveryService service, {
  bool version = false,
  bool write = true,
  bool history = false,
}) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Workspace.new),
    workspacePermissionsProvider.overrideWith((ref) async => {}),
    entitlementProvider.overrideWith(
      (ref) async => {
        for (final key in [
          'land.view_and_edit',
          'land.create_and_save',
          'land.sync',
        ])
          key: FeatureDecision(allowed: write, name: key),
      },
    ),
    recordRecoveryServiceProvider.overrideWithValue(service),
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
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => version
                  ? RecordVersionPage(
                      company: null,
                      record: '1',
                      version: 8,
                      revision: 'a' * 64,
                      canRestore: true,
                    )
                  : RecordRecoveryPage(
                      company: null,
                      record: history ? '1' : null,
                    ),
            ),
          ),
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

Future<void> chooseRestore(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test('cache refresh after restore preserves newer pending edits', () async {
    final directory = await Directory.systemTemp.createTemp('recovery_cache_');
    Hive.init(directory.path);
    final box = await Hive.openBox('landbox');
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    await box.putAll({
      'auth_token': 'synthetic',
      'draft': {
        'id': 'draft',
        'cloudId': '1',
        'syncStatus': 'pending',
        'name': 'Newer local edit',
      },
    });
    await WorkspaceContext.selectCompany(null);
    await http.runWithClient(
      () => RecordRecoveryService().refreshCache('synthetic', null, '1'),
      () => MockClient(
        (request) async => http.Response(
          '{"data":{"id":1,"name":"Restored cloud version","type":"point","points":[]}}',
          200,
        ),
      ),
    );
    expect((box.get('draft') as Map)['name'], 'Newer local edit');
    expect((box.get('draft') as Map)['syncStatus'], 'pending');
    expect(box.containsKey('cloud_1'), isFalse);
  });
  test('pending edit guard is scoped to current workspace', () async {
    final directory = await Directory.systemTemp.createTemp(
      'recovery_pending_',
    );
    Hive.init(directory.path);
    final box = await Hive.openBox('landbox');
    addTearDown(() async {
      await WorkspaceContext.selectCompany(null);
      await Hive.close();
      await directory.delete(recursive: true);
    });
    await box.put('draft', {
      'id': 'draft',
      'cloudId': '1',
      'companyId': 2,
      'syncStatus': 'pending',
    });
    await WorkspaceContext.selectCompany(1);
    expect(RecordRecoveryService().pending('1'), isFalse);
    await WorkspaceContext.selectCompany(2);
    expect(RecordRecoveryService().pending('1'), isTrue);
  });
  testWidgets(
    'recycle restoration requires confirmation and removes restored row',
    (tester) async {
      final service = _Recovery();
      await open(tester, recovery(service));
      await chooseRestore(tester, 'Restore record');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await chooseRestore(tester, 'Restore record');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(service.restored, isTrue);
      expect(find.text('No deleted records found.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'quota failure retains deleted record and displays server explanation',
    (tester) async {
      final service = _Recovery()
        ..failure = 'This workspace has reached its record allowance.';
      await open(tester, recovery(service));
      await chooseRestore(tester, 'Restore record');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(
        find.text('This workspace has reached its record allowance.'),
        findsOneWidget,
      );
      expect(find.text('Deleted plot 1'), findsOneWidget);
      expect(service.restored, isFalse);
    },
  );
  testWidgets('pending local edits block restoration without mutation', (
    tester,
  ) async {
    final service = _Recovery()..pendingEdits = true;
    await open(tester, recovery(service));
    await chooseRestore(tester, 'Restore record');
    expect(find.text('Restore record?'), findsNothing);
    expect(service.calls, 0);
    expect(
      find.text(
        'Sync or resolve pending local edits for this record before restoring it.',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'read-only access hides restore actions but retains readable rows',
    (tester) async {
      await open(tester, recovery(_Recovery(), write: false));
      expect(find.text('Deleted plot 1'), findsOneWidget);
      expect(find.text('Restore record'), findsNothing);
    },
  );
  testWidgets(
    'history previews saved coordinates and restores with loaded revision',
    (tester) async {
      final service = _Recovery();
      await open(tester, recovery(service, history: true));
      await tester.tap(find.text('Old plot'));
      await tester.pumpAndSettle();
      expect(find.text('39.2'), findsOneWidget);
      expect(find.text('-6.7'), findsOneWidget);
      await chooseRestore(tester, 'Restore version');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(service.restoredVersion, 8);
      expect(service.revision, 'a' * 64);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stale revision failure keeps preview and does not claim restoration',
    (tester) async {
      final service = _Recovery()
        ..failure = 'The record changed. Refresh history before restoring.';
      await open(tester, recovery(service, version: true));
      await chooseRestore(tester, 'Restore version');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(
        find.text('The record changed. Refresh history before restoring.'),
        findsOneWidget,
      );
      expect(service.restored, isFalse);
    },
  );
  testWidgets(
    'cache refresh failure reports cloud success rather than failed restore',
    (tester) async {
      final service = _Recovery()..cacheFailure = true;
      await open(tester, recovery(service));
      await chooseRestore(tester, 'Restore record');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(service.restored, isTrue);
      expect(
        find.textContaining('Record restored. Refresh the Library'),
        findsOneWidget,
      );
    },
  );
  testWidgets('recycle paging fits narrow enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, recovery(_Recovery()));
    await tester.tap(find.byTooltip('Next recovery page'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted plot 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'history restore sends expected revision and surfaces structured validation',
    () async {
      Map? sent;
      await http.runWithClient(
        () => RecordRecoveryService().restore(
          'synthetic',
          '1',
          version: 8,
          revision: 'b' * 64,
        ),
        () => MockClient((request) async {
          sent = jsonDecode(request.body) as Map;
          return http.Response('{"success":true}', 200);
        }),
      );
      expect(sent, {'expected_revision': 'b' * 64});
      await expectLater(
        http.runWithClient(
          () => RecordRecoveryService().restore('synthetic', '1'),
          () => MockClient(
            (request) async => http.Response(
              '{"errors":{"record":["Restore period ended."]}}',
              422,
            ),
          ),
        ),
        throwsA(
          predicate(
            (error) => error.toString().contains('Restore period ended.'),
          ),
        ),
      );
    },
  );
}
