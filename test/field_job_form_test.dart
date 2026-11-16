import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/workspaces/field_job_form.dart';
import 'package:taref_gps/features/workspaces/field_job_link_picker.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'original-session',
  );
  void replace() => state = AuthSession(
    user: AuthUser.fromJson({'id': 2, 'is_verified': true}),
    token: 'different-session',
  );
}

class _Workspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey', role: 'owner')],
    activeCompanyId: 1,
  );
  void personal() => state = const WorkspaceState.personal();
}

class _Writer extends FieldJobService {
  int calls = 0;
  int? jobId;
  String? usedToken;
  Map<String, dynamic>? savedPayload;
  Completer<void>? pending;
  @override
  Future<void> save(
    String token, {
    int? job,
    required Map<String, dynamic> payload,
  }) async {
    calls++;
    jobId = job;
    usedToken = token;
    savedPayload = payload;
    await pending?.future;
  }
}

void main() {
  testWidgets('creating a job can assign a team', (tester) async {
    final writer = _Writer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_Session.new),
          workspaceProvider.overrideWith(_Workspace.new),
          fieldJobServiceProvider.overrideWithValue(writer),
          jobLinkOptionsProvider.overrideWith(
            (ref, query) async => {
              'data': [
                {'id': 9, 'name': 'Survey team'},
              ],
              'last_page': 1,
            },
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        FieldJobForm(workspaceId: 1, onSaved: () {}),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Survey');
    await tester.scrollUntilVisible(
      find.text('Assign a team'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Assign a team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Survey team'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create job'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Create job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create job'));
    await tester.pumpAndSettle();
    expect(writer.savedPayload?['company_team_id'], 9);
    expect(writer.savedPayload?['assignee_membership_id'], isNull);
    expect(writer.savedPayload?['status'], 'assigned');
  });

  testWidgets('edit form preserves job content and fits narrow enlarged text', (
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
          home: FieldJobForm(
            workspaceId: 1,
            onSaved: () {},
            job: const {
              'id': 1,
              'title': 'Boundary survey',
              'description': 'Visit the northern boundary',
              'status': 'assigned',
              'assignee_membership_id': 4,
              'assignee_name': 'Field surveyor',
              'company_project_id': 7,
              'project_name': 'Northern boundary project',
              'land_id': 8,
              'record_name': 'Boundary plot',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit field job'), findsOneWidget);
    expect(find.text('Boundary survey'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Northern boundary project'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Northern boundary project'), findsOneWidget);
    await tester.tap(find.byTooltip('Unlink project'));
    await tester.pumpAndSettle();
    expect(find.text('Northern boundary project'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final accountChange in [true, false]) {
    testWidgets(
      'stale field job form refuses save after ${accountChange ? 'account' : 'workspace'} change',
      (tester) async {
        final writer = _Writer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authSessionProvider.overrideWith(_Session.new),
              workspaceProvider.overrideWith(_Workspace.new),
              fieldJobServiceProvider.overrideWithValue(writer),
            ],
            child: MaterialApp(
              home: FieldJobForm(workspaceId: 1, onSaved: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FieldJobForm)),
        );
        await tester.enterText(
          find.byType(TextFormField).first,
          'Draft for original workspace',
        );
        if (accountChange) {
          (container.read(authSessionProvider.notifier) as _Session).replace();
        } else {
          (container.read(workspaceProvider.notifier) as _Workspace).personal();
        }
        await tester.pumpAndSettle();
        expect(
          find.text('Workspace or account changed. Reopen the field job form.'),
          findsOneWidget,
        );
        expect(find.text('Create job'), findsNothing);
        expect(writer.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final accountChange in [true, false]) {
    testWidgets(
      'late job save cannot navigate or refresh after ${accountChange ? 'account' : 'workspace'} change',
      (tester) async {
        final writer = _Writer()..pending = Completer<void>();
        var saved = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authSessionProvider.overrideWith(_Session.new),
              workspaceProvider.overrideWith(_Workspace.new),
              fieldJobServiceProvider.overrideWithValue(writer),
            ],
            child: MaterialApp(
              home: FieldJobForm(workspaceId: 1, onSaved: () => saved++),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FieldJobForm)),
        );
        await tester.enterText(
          find.byType(TextFormField).first,
          'Draft for original workspace',
        );
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Create job'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Create job'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create job'));
        await tester.pump();
        expect(writer.calls, 1);
        expect(writer.usedToken, 'original-session');
        if (accountChange) {
          (container.read(authSessionProvider.notifier) as _Session).replace();
        } else {
          (container.read(workspaceProvider.notifier) as _Workspace).personal();
        }
        await tester.pump();
        writer.pending!.complete();
        await tester.pumpAndSettle();
        expect(saved, 0);
        expect(find.byType(FieldJobForm), findsOneWidget);
        expect(
          tester.widget<PopScope>(find.byType(PopScope).first).canPop,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editing a string job ID still sends an update and preserves links',
    (tester) async {
      final writer = _Writer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_Session.new),
            workspaceProvider.overrideWith(_Workspace.new),
            fieldJobServiceProvider.overrideWithValue(writer),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FieldJobForm(
                        workspaceId: 1,
                        onSaved: () {},
                        job: const {
                          'id': '17',
                          'title': 'Existing job',
                          'status': 'assigned',
                          'assignee_membership_id': 4,
                          'company_project_id': 8,
                          'land_id': 9,
                        },
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(writer.jobId, 17);
      expect(writer.savedPayload?.containsKey('company_project_id'), isFalse);
      expect(writer.savedPayload?.containsKey('land_id'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing a team job preserves its existing assignment', (
    tester,
  ) async {
    final writer = _Writer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_Session.new),
          workspaceProvider.overrideWith(_Workspace.new),
          fieldJobServiceProvider.overrideWithValue(writer),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FieldJobForm(
                      workspaceId: 1,
                      onSaved: () {},
                      job: const {
                        'id': 17,
                        'title': 'Team job',
                        'status': 'assigned',
                        'company_team_id': 9,
                        'team_name': 'Survey team',
                      },
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Survey team'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Survey team'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(writer.calls, 1);
    expect(writer.savedPayload?.containsKey('company_team_id'), isFalse);
    expect(writer.savedPayload?.containsKey('assignee_membership_id'), isFalse);
    expect(writer.savedPayload?['status'], 'assigned');
  });
}
