import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'survey_invitation.dart';

/// Local-only queue until the TaREF backend exposes a survey submission API.
/// Do not display these entries as "sent" or delete them on app restart.
class SurveyQueue {
  SurveyQueue(this._box);

  final Box _box;
  static const pendingKey = 'pending_user_surveys_v1';

  List<Map<String, dynamic>> get pending {
    final raw = _box.get(pendingKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> enqueue({
    required String role,
    required String difficulty,
    required int satisfaction,
    String? comment,
  }) async {
    if (role.trim().isEmpty ||
        difficulty.trim().isEmpty ||
        satisfaction < 1 ||
        satisfaction > 5) {
      throw ArgumentError('Complete the required survey questions.');
    }
    final items = pending.toList();
    items.add({
      'id': const Uuid().v4(),
      'schema_version': 1,
      'role': role.trim(),
      'difficulty': difficulty.trim(),
      'satisfaction': satisfaction,
      'comment': (comment ?? '').trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _box.put(pendingKey, items);
    await _box.put(SurveyInvitation.completedKey, true);
  }
}
