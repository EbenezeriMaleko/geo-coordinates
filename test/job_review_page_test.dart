import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/job_review_page.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

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
    companies: [
      CompanyWorkspace(id: 2, name: 'Survey company', role: 'reviewer'),
    ],
    activeCompanyId: 2,
  );
}

Widget page(Map<String, dynamic> review) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Workspace.new),
    entitlementProvider.overrideWith(
      (ref) async => {
        'company.review_workflow': const FeatureDecision(
          allowed: true,
          name: 'Review',
        ),
      },
    ),
    jobReviewProvider.overrideWith((ref, id) async => review),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: JobReviewPage(
      job: const {
        'id': 5,
        'title': 'Northern boundary survey',
        'status': 'completed',
      },
      company: 2,
      manager: false,
      writable: true,
      canSubmit: false,
      onChanged: () {},
    ),
  ),
);

void main() {
  testWidgets(
    'server-authorized reviewer sees decisions without manager flag',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        page({
          'state': 'submitted',
          'submitted_by': 3,
          'permissions': {'can_decide': true},
        }),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Approve'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Request changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('self approval and absent server permission hide decisions', (
    tester,
  ) async {
    await tester.pumpWidget(
      page({
        'state': 'submitted',
        'submitted_by': 1,
        'permissions': {'can_decide': false},
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Request changes'), findsNothing);
    expect(
      find.text('Another company manager must review this submission.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'server-unavailable review shows retry instead of action controls',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_Session.new),
            workspaceProvider.overrideWith(_Workspace.new),
            entitlementProvider.overrideWith((ref) async => {}),
            jobReviewProvider.overrideWith(
              (ref, id) async => throw Exception('Reviews unavailable'),
            ),
          ],
          child: MaterialApp(
            home: JobReviewPage(
              job: const {'id': 5},
              company: 2,
              manager: true,
              writable: true,
              canSubmit: true,
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    },
  );
}
