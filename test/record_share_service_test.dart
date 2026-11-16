import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/core/network/api_client.dart';
import 'package:taref_gps/features/land_map/services/record_share_service.dart';

void main() {
  tearDown(() => ApiClient.setActiveCompanyId(null));

  test(
    'shows the server validation reason instead of a generic error',
    () async {
      final service = RecordShareService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'message': 'Validation failed.',
              'errors': {
                'sharing': [
                  'Sharing is disabled or the allowance has been reached.',
                ],
              },
            }),
            422,
          ),
        ),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.request(
          token: 'token',
          record: 5,
          company: null,
          isCurrent: () => true,
          method: 'POST',
          body: {'expires_days': 30},
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Sharing is disabled or the allowance has been reached.'),
          ),
        ),
      );
    },
  );

  test(
    'sharing requests pin the company and send explicit privacy settings',
    () async {
      ApiClient.setActiveCompanyId(99);
      final service = RecordShareService(
        client: MockClient((request) async {
          expect(request.headers['X-Company-Id'], '12');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body)['include_claimant_details'], false);
          return http.Response(
            jsonEncode({
              'data': {
                'company': true,
                'can_manage': true,
                'policy': {},
                'links': [],
              },
            }),
            201,
          );
        }),
      );
      addTearDown(service.dispose);
      final result = await service.request(
        token: 'token',
        record: 5,
        company: 12,
        isCurrent: () => true,
        method: 'POST',
        body: {'expires_days': 30, 'include_claimant_details': false},
      );
      expect(result['links'], isEmpty);
    },
  );

  test('response is rejected when the workspace changes', () async {
    var current = true;
    final service = RecordShareService(
      client: MockClient((request) async {
        current = false;
        return http.Response(
          jsonEncode({
            'data': {'links': []},
          }),
          200,
        );
      }),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.request(
        token: 'token',
        record: 5,
        company: 12,
        isCurrent: () => current,
      ),
      throwsException,
    );
  });

  test('only links from the configured server origin can be shared', () {
    final token = 'a' * 64;
    expect(
      RecordShareService.safeUrl('${ApiClient.originUrl()}/s/$token'),
      isTrue,
    );
    expect(
      RecordShareService.safeUrl('https://attacker.example/s/$token'),
      isFalse,
    );
    expect(RecordShareService.safeUrl('javascript:alert(1)'), isFalse);
    expect(
      RecordShareService.safeUrl('${ApiClient.originUrl()}/s/$token?extra=1'),
      isFalse,
    );
  });
}
