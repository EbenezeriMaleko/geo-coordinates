import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taref_gps/features/land_map/services/survey_queue.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('survey_queue_test_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('survey_queue_test');
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test(
    'stores multiple responses without coordinates or account details',
    () async {
      final queue = SurveyQueue(box);
      await queue.enqueue(
        role: 'Surveyor',
        difficulty: 'Offline use or syncing',
        satisfaction: 2,
        comment: 'Hard to edit offline',
      );
      await queue.enqueue(
        role: 'Engineer',
        difficulty: 'Nothing is difficult',
        satisfaction: 5,
      );

      final reopened = SurveyQueue(box).pending;
      expect(reopened, hasLength(2));
      expect(reopened.first['comment'], 'Hard to edit offline');
      expect(reopened.first.keys, containsAll(['id', 'created_at']));
      expect(reopened.first.keys, isNot(contains('coordinates')));
      expect(reopened.first.keys, isNot(contains('email')));
    },
  );

  test('rejects incomplete answers', () async {
    await expectLater(
      SurveyQueue(
        box,
      ).enqueue(role: '', difficulty: 'Navigation', satisfaction: 3),
      throwsArgumentError,
    );
    expect(SurveyQueue(box).pending, isEmpty);
  });
}
