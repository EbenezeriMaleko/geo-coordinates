import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';
import 'package:taref_gps/features/subscriptions/subscription_provider.dart';

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
  void company(int? id) =>
      state = WorkspaceState(companies: const [], activeCompanyId: id);
}

void main() {
  test(
    'billing follows personal to company and back with explicit query scope',
    () async {
      final scopes = <String?>[];
      final client = MockClient((request) async {
        final id = request.url.queryParameters['company_id'];
        scopes.add(id);
        return http.Response(
          jsonEncode({
            'data': {
              'company': id == null ? null : {'id': int.parse(id)},
              'usage': {
                'plan_name': id == null ? 'Personal Expert' : 'Company Team',
              },
            },
          }),
          200,
        );
      });
      await http.runWithClient(() async {
        final container = ProviderContainer(
          overrides: [
            authSessionProvider.overrideWith(_Session.new),
            workspaceProvider.overrideWith(_Workspace.new),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          subscriptionOverviewProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        expect(
          (await container.read(
            subscriptionOverviewProvider.future,
          ))['usage']['plan_name'],
          'Personal Expert',
        );
        (container.read(workspaceProvider.notifier) as _Workspace).company(12);
        expect(
          (await container.read(
            subscriptionOverviewProvider.future,
          ))['usage']['plan_name'],
          'Company Team',
        );
        (container.read(workspaceProvider.notifier) as _Workspace).company(
          null,
        );
        expect(
          (await container.read(
            subscriptionOverviewProvider.future,
          ))['usage']['plan_name'],
          'Personal Expert',
        );
        expect(scopes, [null, '12', null]);
      }, () => client);
    },
  );

  test('rejects personal billing returned for a company workspace', () async {
    await http.runWithClient(
      () async {
        final container = ProviderContainer(
          overrides: [
            authSessionProvider.overrideWith(_Session.new),
            workspaceProvider.overrideWith(_Workspace.new),
          ],
        );
        addTearDown(container.dispose);
        (container.read(workspaceProvider.notifier) as _Workspace).company(12);
        await expectLater(
          container.read(subscriptionOverviewProvider.future),
          throwsException,
        );
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {'company': null},
          }),
          200,
        ),
      ),
    );
  });
}
