import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/services/auth_device_identity.dart';
import 'package:taref_gps/features/auth/services/auth_service.dart';
import 'package:taref_gps/features/auth/services/auth_session_store.dart';
import 'package:taref_gps/core/network/api_client.dart';

void main() {
  late Directory directory;
  late Box box;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('auth_device_identity_');
    Hive.init(directory.path);
    box = await Hive.openBox('landbox');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'installation ID survives logout and preserves pending records',
    () async {
      await box.put('draft', {'id': 'draft', 'syncStatus': 'pending'});
      final first = await AuthDeviceIdentity().metadata();
      await AuthSessionStore().clear();
      final second = await AuthDeviceIdentity().metadata();
      expect(second['device_id'], first['device_id']);
      expect(first['device_id']?.length, 36);
      expect((box.get('draft') as Map)['syncStatus'], 'pending');
    },
  );
  test(
    'login sends installation metadata using a mocked HTTP request',
    () async {
      Map? payload;
      final originalPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalPrint);
      await http.runWithClient(
        () => AuthService().login(
          const LoginRequest(email: 'test@example.test', password: 'synthetic'),
        ),
        () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'token': 'synthetic'},
            }),
            200,
          );
        }),
      );
      expect(payload?['device_id'], box.get(AuthDeviceIdentity.key));
      expect(payload?['device_name'], startsWith('TaREF GPS - '));
      expect(payload?['email'], 'test@example.test');
      expect(logs.join(), contains('<redacted>'));
      expect(logs.join(), isNot(contains('synthetic')));
    },
  );
  test('password-update HTTP bodies are redacted', () async {
    final originalPrint = debugPrint;
    final logs = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalPrint);
    await http.runWithClient(
      () => ApiClient.putJson(
        '/auth/password',
        body: {'password': 'synthetic-secret'},
      ),
      () => MockClient(
        (request) async => http.Response('{"token":"synthetic-secret"}', 200),
      ),
    );
    expect(logs.join(), contains('<redacted>'));
    expect(logs.join(), isNot(contains('synthetic-secret')));
  });
  test(
    'only the known allowance rejection is classified as a device limit',
    () {
      expect(
        isDeviceLimitResponse(422, {
          'errors': {
            'device_id': ['Device allowance reached. Sign out another device.'],
          },
        }),
        isTrue,
      );
      expect(
        isDeviceLimitResponse(422, {
          'errors': {
            'device_id': ['The device id must be a valid UUID.'],
          },
        }),
        isFalse,
      );
      expect(
        isDeviceLimitResponse(401, {'message': 'Invalid credentials'}),
        isFalse,
      );
    },
  );
}
