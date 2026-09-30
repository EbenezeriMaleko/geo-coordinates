import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import 'survey_queue.dart';

/// Sends queued, anonymous survey answers without logging free-text comments.
class SurveySyncService {
  SurveySyncService(this._box, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final Box _box;
  final http.Client _client;
  final bool _ownsClient;
  static bool _syncing = false;

  Future<int> syncPending({int limit = 10}) async {
    if (_syncing) return 0;
    _syncing = true;
    var sent = 0;
    try {
      final entries = SurveyQueue(_box).pending.take(limit).toList();
      for (final entry in entries) {
        final id = entry['id']?.toString() ?? '';
        if (id.isEmpty) break;
        try {
          final response = await _client
              .post(
                ApiClient.uri('/surveys'),
                headers: ApiClient.jsonHeaders(),
                body: jsonEncode(entry),
              )
              .timeout(const Duration(seconds: 10));
          final body = jsonDecode(response.body);
          final confirmedId = body is Map && body['data'] is Map
              ? (body['data'] as Map)['id']?.toString()
              : null;
          if ((response.statusCode != 200 && response.statusCode != 201) ||
              body is! Map ||
              body['success'] != true ||
              confirmedId != id) {
            break;
          }

          // Re-read the current queue so a new response saved while syncing
          // cannot be lost by replacing it with an older snapshot.
          final remaining = SurveyQueue(_box).pending.toList()
            ..removeWhere((item) => item['id']?.toString() == id);
          await _box.put(SurveyQueue.pendingKey, remaining);
          sent++;
        } catch (_) {
          // Offline or server unavailable: retain this and later entries.
          break;
        }
      }
      return sent;
    } finally {
      if (_ownsClient) _client.close();
      _syncing = false;
    }
  }
}
