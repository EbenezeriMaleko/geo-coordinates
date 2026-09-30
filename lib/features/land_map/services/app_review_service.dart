import 'dart:io';

import 'package:hive/hive.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

/// Store reviews are controlled by Apple/Google; requesting one does not
/// guarantee that the platform will show it or tell us what the user chose.
class AppReviewService {
  AppReviewService(this._box, {InAppReview? review})
    : _review = review ?? InAppReview.instance;

  final Box _box;
  final InAppReview _review;

  static const _firstSaveKey = 'review_first_successful_save';
  static const _saveCountKey = 'review_successful_save_count';
  static const _lastRequestKey = 'review_last_request';
  static const _minimumSaves = 3;
  static const _minimumAge = Duration(days: 7);
  static const _minimumInterval = Duration(days: 120);

  Future<bool> openStoreListing() async {
    if (Platform.isAndroid) {
      return launchUrl(
        Uri.parse(
          'https://play.google.com/store/apps/details?id=com.databenki.taref_gps',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
    if (Platform.isIOS) {
      return launchUrl(
        Uri.parse(
          'https://apps.apple.com/us/app/taref-gps-coordinates/id6787417155?action=write-review',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
    return false;
  }

  /// Call only after a save succeeded and the save UI has finished.
  Future<void> recordSuccessfulSave() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final now = DateTime.now().toUtc();
      final first = DateTime.tryParse(
        _box.get(_firstSaveKey)?.toString() ?? '',
      );
      if (first == null) await _box.put(_firstSaveKey, now.toIso8601String());
      final count = (_box.get(_saveCountKey) as int? ?? 0) + 1;
      await _box.put(_saveCountKey, count);
      if (count < _minimumSaves || now.difference(first ?? now) < _minimumAge) {
        return;
      }

      final last = DateTime.tryParse(
        _box.get(_lastRequestKey)?.toString() ?? '',
      );
      if (last != null && now.difference(last) < _minimumInterval) return;

      // Persist before requesting: even a platform-suppressed prompt should
      // not cause us to repeatedly interrupt the user's next actions.
      await _box.put(_lastRequestKey, now.toIso8601String());
      if (await _review.isAvailable()) await _review.requestReview();
    } catch (_) {
      // Review prompting is optional and must never fail a successful save.
    }
  }
}
