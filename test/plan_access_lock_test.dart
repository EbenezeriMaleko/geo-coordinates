import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/ui/login_page.dart';
import 'package:taref_gps/features/subscriptions/plans_access_page.dart';
import 'package:taref_gps/features/widget/plan_access_lock.dart';

class _Observer extends NavigatorObserver {
  Route<dynamic>? last;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      last = route;
}

class _SignedIn extends AuthSessionNotifier {
  @override
  AuthSession build() => const AuthSession(user: null, token: 'synthetic');
}

class _Guest extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession.empty;
}

void main() {
  for (final signedIn in [true, false]) {
    testWidgets(
      signedIn
          ? 'signed-in locked action opens Plans & Access'
          : 'guest locked action opens Sign In and returns to the feature',
      (tester) async {
        var calls = 0;
        final observer = _Observer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authSessionProvider.overrideWith(
                signedIn ? _SignedIn.new : _Guest.new,
              ),
            ],
            child: MaterialApp(
              navigatorObservers: [observer],
              home: Scaffold(
                body: PlanAccessLock(
                  locked: true,
                  child: FilledButton(
                    onPressed: () => calls++,
                    child: const Text('Export'),
                  ),
                ),
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(PlanAccessLock));
        await tester.tap(find.byType(PlanAccessLock));
        expect(calls, 0);
        final destination = (observer.last as MaterialPageRoute).builder(
          context,
        );
        if (signedIn) {
          expect(destination, isA<PlansAccessPage>());
        } else {
          expect(destination, isA<LoginPage>());
          expect((destination as LoginPage).returnToPreviousPage, isTrue);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('allowed action remains enabled and unchanged', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PlanAccessLock(
              locked: false,
              child: FilledButton(
                onPressed: () => calls++,
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    expect(calls, 1);
  });

  testWidgets('unknown access is not displayed as a plan restriction', (
    tester,
  ) async {
    final waiting = Completer<Map<String, FeatureDecision>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [entitlementProvider.overrideWith((ref) => waiting.future)],
        child: const MaterialApp(
          home: Scaffold(
            body: FeatureAccessLock(
              features: ['map.google_maps'],
              child: Text('Google Maps'),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<PlanAccessLock>(find.byType(PlanAccessLock)).locked,
      isFalse,
    );
    waiting.complete({});
    await tester.pumpAndSettle();
    expect(
      tester.widget<PlanAccessLock>(find.byType(PlanAccessLock)).locked,
      isFalse,
    );
  });

  testWidgets(
    'combined navigation stays usable when one feature is available',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            entitlementProvider.overrideWith(
              (ref) async => {
                'company.projects': const FeatureDecision(
                  allowed: true,
                  name: 'Projects',
                ),
                'company.teams': const FeatureDecision(
                  allowed: false,
                  name: 'Teams',
                ),
              },
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FeatureAccessLock(
                features: ['company.projects', 'company.teams'],
                allDenied: true,
                child: Text('Projects & Teams'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PlanAccessLock>(find.byType(PlanAccessLock)).locked,
        isFalse,
      );
    },
  );
}
