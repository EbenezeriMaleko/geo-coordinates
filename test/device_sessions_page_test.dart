import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/auth/ui/device_sessions_page.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Devices extends DeviceSessionService {
  int? revoked;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> list(String token, int page) async => {
    'available': true,
    'enforced': true,
    'login_limit': 2,
    'last_page': 2,
    'sessions': page == 2
        ? [
            {'id': 3, 'name': 'Older laptop', 'current': false},
          ]
        : [
            {'id': 1, 'name': 'Current phone', 'current': true},
            if (revoked == null)
              {'id': 2, 'name': 'Other phone', 'current': false},
          ],
  };
  @override
  Future<void> revoke(String token, int id) async {
    if (fail) throw Exception('Unable to sign out this device.');
    revoked = id;
  }
}

Widget devices(DeviceSessionService service) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    deviceSessionServiceProvider.overrideWithValue(service),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const DeviceSessionsPage(),
  ),
);

void main() {
  testWidgets(
    'current device has no revoke action and other devices require confirmation',
    (tester) async {
      final service = _Devices();
      await tester.pumpWidget(devices(service));
      await tester.pumpAndSettle();
      expect(find.text('Current device'), findsOneWidget);
      expect(find.text('Sign out device'), findsOneWidget);
      await tester.tap(find.text('Sign out device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.revoked, isNull);
      await tester.tap(find.text('Sign out device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out device').last);
      await tester.pumpAndSettle();
      expect(service.revoked, 2);
      expect(find.text('Other phone'), findsNothing);
      expect(find.text('Current phone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed revocation keeps the other session visible', (
    tester,
  ) async {
    await tester.pumpWidget(devices(_Devices()..fail = true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out device').last);
    await tester.pumpAndSettle();
    expect(find.text('Unable to sign out this device.'), findsOneWidget);
    expect(find.text('Other phone'), findsOneWidget);
  });
  testWidgets('device pagination fits narrow enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(devices(_Devices()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next devices page'));
    await tester.pumpAndSettle();
    expect(find.text('Older laptop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
