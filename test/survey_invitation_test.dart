import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taref_gps/features/land_map/services/survey_invitation.dart';
import 'package:taref_gps/features/land_map/services/survey_queue.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('survey_invite_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('survey_invite_test');
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('waits for three records and a week of eligibility', () async {
    final policy = SurveyInvitation(box);
    final first = DateTime.utc(2026, 9, 1);
    expect(await policy.shouldShow(savedRecordCount: 2, now: first), false);
    expect(await policy.shouldShow(savedRecordCount: 3, now: first), false);
    expect(
      await policy.shouldShow(
        savedRecordCount: 3,
        now: first.add(const Duration(days: 6)),
      ),
      false,
    );
    expect(
      await policy.shouldShow(
        savedRecordCount: 3,
        now: first.add(const Duration(days: 7)),
      ),
      true,
    );
  });

  test('dismissal cools down and a completed survey stops invites', () async {
    final policy = SurveyInvitation(box);
    final first = DateTime.utc(2026, 9, 1);
    await policy.shouldShow(savedRecordCount: 3, now: first);
    final eligible = first.add(const Duration(days: 7));
    await policy.dismiss(now: eligible);
    expect(
      await policy.shouldShow(
        savedRecordCount: 3,
        now: eligible.add(const Duration(days: 89)),
      ),
      false,
    );
    expect(
      await policy.shouldShow(
        savedRecordCount: 3,
        now: eligible.add(const Duration(days: 90)),
      ),
      true,
    );
    await SurveyQueue(
      box,
    ).enqueue(role: 'Surveyor', difficulty: 'Navigation', satisfaction: 3);
    expect(
      await policy.shouldShow(
        savedRecordCount: 3,
        now: eligible.add(const Duration(days: 100)),
      ),
      false,
    );
  });

  test('debug preview is one-time and bypasses normal eligibility', () async {
    final policy = SurveyInvitation(box);
    expect(await policy.shouldShow(savedRecordCount: 0), false);

    await policy.requestDebugPreview();
    expect(await policy.consumeDebugPreview(), true);
    expect(await policy.consumeDebugPreview(), false);
    expect(await policy.shouldShow(savedRecordCount: 0), false);
  });
}
