import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Keeps the survey invitation infrequent and independent of store reviews.
class SurveyInvitation {
  SurveyInvitation(this._box);

  final Box _box;

  static const _firstEligibleKey = 'survey_invitation_first_eligible_v1';
  static const _lastDismissedKey = 'survey_invitation_last_dismissed_v1';
  static const completedKey = 'survey_invitation_completed_v1';
  static const _debugPreviewKey = 'survey_invitation_debug_preview_once';
  static const minimumRecords = 3;
  static const minimumEligibleAge = Duration(days: 7);
  static const dismissalInterval = Duration(days: 90);

  Future<void> requestDebugPreview() async {
    if (kDebugMode) await _box.put(_debugPreviewKey, true);
  }

  Future<bool> consumeDebugPreview() async {
    if (!kDebugMode || _box.get(_debugPreviewKey) != true) return false;
    await _box.delete(_debugPreviewKey);
    return true;
  }

  Future<bool> shouldShow({
    required int savedRecordCount,
    DateTime? now,
  }) async {
    if (savedRecordCount < minimumRecords || _box.get(completedKey) == true) {
      return false;
    }
    // A queued answer means the user has already completed the survey, even
    // if delivery to the backend has not happened yet.
    final queued = _box.get('pending_user_surveys_v1');
    if (queued is List && queued.isNotEmpty) return false;

    final current = (now ?? DateTime.now()).toUtc();
    final first = DateTime.tryParse(
      _box.get(_firstEligibleKey)?.toString() ?? '',
    );
    if (first == null) {
      await _box.put(_firstEligibleKey, current.toIso8601String());
      return false;
    }
    if (current.difference(first) < minimumEligibleAge) return false;

    final dismissed = DateTime.tryParse(
      _box.get(_lastDismissedKey)?.toString() ?? '',
    );
    return dismissed == null ||
        current.difference(dismissed) >= dismissalInterval;
  }

  Future<void> dismiss({DateTime? now}) => _box.put(
    _lastDismissedKey,
    (now ?? DateTime.now()).toUtc().toIso8601String(),
  );
}
