import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/land_map/models/land_api_models.dart';
import 'package:taref_gps/features/land_map/providers/land_cloud_provider.dart';
import 'package:taref_gps/features/land_map/services/land_cloud_service.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/library_organization_filter.dart';
import 'package:taref_gps/features/workspaces/record_organization_section.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';
import 'package:taref_gps/core/localization/app_localizations.dart';
import 'package:taref_gps/features/land_map/ui/saved_locations_page.dart';
import 'package:taref_gps/features/workspaces/field_job_link_picker.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Workspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey', role: 'admin')],
    activeCompanyId: 1,
  );
  void personal() =>
      state = const WorkspaceState(companies: [], activeCompanyId: null);
}

class _Cloud extends LandCloudService {
  @override
  Future<LandSummary> summary(String bearerToken) async =>
      LandSummary.fromJson({});
  final calls = <({int? project, int? team, int page, String? search})>[];
  @override
  Future<PaginatedLands> listLands(
    String bearerToken, {
    String? search,
    int perPage = 15,
    int page = 1,
    int? projectId,
    int? teamId,
  }) async {
    calls.add((project: projectId, team: teamId, page: page, search: search));
    return PaginatedLands(
      items: [
        LandListItem.fromJson({
          'id': page,
          'name': 'Plot $page',
          'type': 'polygon',
        }),
      ],
      total: 2,
      perPage: 1,
      currentPage: page,
      lastPage: 2,
    );
  }
}

void main() {
  for (final authorized in [true, false]) {
    testWidgets(
      'assignment controls respect organization permission: $authorized',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workspaceProvider.overrideWith(_Workspace.new),
              workspacePermissionsProvider.overrideWith(
                (ref) async => {'organization.manage': authorized},
              ),
              entitlementProvider.overrideWith(
                (ref) async => {
                  for (final key in [
                    'company.projects',
                    'company.teams',
                    'land.view_and_edit',
                  ])
                    key: FeatureDecision(allowed: true, name: key),
                },
              ),
              remoteLandDetailProvider.overrideWith(
                (ref, id) async => LandDetail.fromJson({
                  'id': id,
                  'name': 'Plot',
                  'record_access': {'can_manage': true},
                }),
              ),
              recordAssignmentProvider.overrideWith((ref, query) async => {}),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RecordOrganizationSection(
                    company: 1,
                    record: '9',
                    canManage: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Assign project'),
          authorized ? findsOneWidget : findsNothing,
        );
        expect(
          find.byTooltip('Assign team'),
          authorized ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Library reloads cloud results when a project filter is selected and cleared',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'library_organization_',
      );
      Hive.init(directory.path);
      await tester.runAsync(() async {
        final box = await Hive.openBox('landbox');
        await box.put('workspace_active_company_id', 1);
      });
      addTearDown(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });
      final cloud = _Cloud();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceProvider.overrideWith(_Workspace.new),
            authSessionProvider.overrideWith(_Session.new),
            landCloudServiceProvider.overrideWithValue(cloud),
            jobLinkOptionsProvider.overrideWith(
              (ref, query) async => {
                'data': [
                  {'id': 5, 'name': 'Northern survey'},
                ],
                'last_page': 1,
              },
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizations.delegate],
            home: SavedLocationsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Northern survey'));
      await tester.pumpAndSettle();
      expect(cloud.calls.last.project, 5);
      expect(
        find.text(
          'Cloud records only. Clear filters to see pending local records.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final chip = tester.widget<InputChip>(find.byType(InputChip).first);
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(cloud.calls.last.project, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test(
    'project/team filters persist through pagination and reset for personal workspace',
    () async {
      final cloud = _Cloud();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(_Session.new),
          workspaceProvider.overrideWith(_Workspace.new),
          landCloudServiceProvider.overrideWithValue(cloud),
        ],
      );
      addTearDown(container.dispose);
      final filter = container.read(libraryOrganizationFilterProvider.notifier);
      filter.select(team: false, id: 5, name: 'North');
      filter.select(team: true, id: 7, name: 'Surveyors');
      await container.read(remoteLandsProvider.future);
      await container
          .read(remoteLandsProvider.notifier)
          .fetch(search: 'Plot', perPage: 1);
      await container
          .read(remoteLandsProvider.notifier)
          .fetchNextPage(search: 'Plot', perPage: 1);
      expect(cloud.calls, [
        (project: 5, team: 7, page: 1, search: 'Plot'),
        (project: 5, team: 7, page: 2, search: 'Plot'),
      ]);
      expect(
        container.read(remoteLandsProvider).asData?.value?.items.length,
        2,
      );
      (container.read(workspaceProvider.notifier) as _Workspace).personal();
      expect(container.read(libraryOrganizationFilterProvider).active, isFalse);
      await container.read(remoteLandsProvider.future);
      await container.read(remoteLandsProvider.notifier).fetch();
      expect(cloud.calls.last.project, isNull);
      expect(cloud.calls.last.team, isNull);
    },
  );

  testWidgets(
    'read-only record retains archived assignment names without editing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceProvider.overrideWith(_Workspace.new),
            workspacePermissionsProvider.overrideWith(
              (ref) async => {'organization.manage': true},
            ),
            entitlementProvider.overrideWith(
              (ref) async => {
                for (final key in [
                  'company.projects',
                  'company.teams',
                  'land.view_and_edit',
                ])
                  key: FeatureDecision(allowed: true, name: key),
              },
            ),
            recordAssignmentProvider.overrideWith(
              (ref, query) async => {
                'company_project_id': 5,
                'project_name': 'Northern district survey project',
                'project_archived': true,
                'company_team_id': 7,
                'team_name': 'Survey team',
                'team_archived': false,
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
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: RecordOrganizationSection(
                  company: 1,
                  record: '9',
                  canManage: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Northern district survey project'), findsOneWidget);
      expect(find.text('Archived project'), findsOneWidget);
      expect(find.byTooltip('Assign project'), findsNothing);
      expect(find.byTooltip('Unassign team'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
