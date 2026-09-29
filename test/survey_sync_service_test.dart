import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/features/land_map/services/survey_queue.dart';
import 'package:taref_gps/features/land_map/services/survey_sync_service.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('survey_sync_test_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('survey_sync_test');
    await SurveyQueue(box).enqueue(
      role: 'Surveyor',
      difficulty: 'Offline use or syncing',
      satisfaction: 2,
      comment: 'Please improve offline editing',
    );
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('removes an answer only after server confirms its UUID', () async {
    final id = SurveyQueue(box).pending.single['id'];
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/surveys');
      expect(request.method, 'POST');
      return http.Response('{"success":true,"data":{"id":"$id"}}', 201);
    });

    expect(await SurveySyncService(box, client: client).syncPending(), 1);
    expect(SurveyQueue(box).pending, isEmpty);
  });

  test('keeps an answer when the server fails', () async {
    final client = MockClient((_) async => http.Response('Unavailable', 503));

    expect(await SurveySyncService(box, client: client).syncPending(), 0);
    expect(SurveyQueue(box).pending, hasLength(1));
  });

  test('keeps an answer if confirmation has a different UUID', () async {
    final client = MockClient(
      (_) async =>
          http.Response('{"success":true,"data":{"id":"wrong-id"}}', 200),
    );

    expect(await SurveySyncService(box, client: client).syncPending(), 0);
    expect(SurveyQueue(box).pending, hasLength(1));
  });
}
