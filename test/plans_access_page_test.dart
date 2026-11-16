import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/subscriptions/plans_access_page.dart';
import 'package:taref_gps/features/subscriptions/subscription_provider.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Workspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState.personal();
}

void main() {
  testWidgets('usage layout fits narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(_Workspace.new),
          entitlementProvider.overrideWith(
            (ref) async => {
              'map.standard_basemap': const FeatureDecision(
                allowed: true,
                name: 'Standard map',
              ),
            },
          ),
          subscriptionOverviewProvider.overrideWith(
            (ref) async => {
              'usage': {
                'plan_name': 'Professional field workspace',
                'records': {'used': 10, 'limit': 10},
                'storage': {'used': 1048576, 'limit': 10485760},
                'exports': {'used': 0, 'limit': -1},
                'reports': {
                  'used': 2,
                  'limit': 5,
                  'resets_at': '2026-12-01T00:00:00Z',
                },
                'shared_links': {'used': 1, 'limit': 3},
                'downgrade': {
                  'restricted_records': 4,
                  'grace_ends_at': '2026-12-10T00:00:00Z',
                },
              },
              'has_pending_request': true,
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
          home: const PlansAccessPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pending approval'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('4 older records are read-only'),
      100,
    );
    expect(find.text('4 older records are read-only'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Allowance reached'), 100);
    expect(find.text('Allowance reached'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('1 / 10 MB'), 100);
    expect(find.text('1 / 10 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Monthly parcel reports'), 100);
    expect(find.text('Monthly parcel reports'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Active shared links'), 100);
    expect(find.text('Active shared links'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
