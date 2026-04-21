import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../auth/services/auth_service.dart';
import '../models/land_api_models.dart';

class LandCloudService {
  Future<PaginatedLands> listLands(
    String bearerToken, {
    String? search,
    int perPage = 15,
    int page = 1,
  }) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/lands',
        bearerToken: bearerToken,
        tag: 'lands_list',
        queryParameters: {
          if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
          'per_page': perPage,
          'page': page,
        },
      ),
      fallbackError: 'Failed to load lands.',
    );
    return PaginatedLands.fromJson(body);
  }

  Future<LandListItem> createLand(
    String bearerToken,
    CreateLandRequest request,
  ) async {
    final body = await _requestJson(
      () => ApiClient.postJson(
        '/lands',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'lands_create',
      ),
      fallbackError: 'Failed to create land.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LandListItem.fromJson(data);
  }

  Future<LandSummary> summary(String bearerToken) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/lands/summary',
        bearerToken: bearerToken,
        tag: 'lands_summary',
      ),
      fallbackError: 'Failed to load land summary.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LandSummary.fromJson(data);
  }

  Future<LandDetail> getLand(String bearerToken, String landId) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/lands/$landId',
        bearerToken: bearerToken,
        tag: 'land_get',
      ),
      fallbackError: 'Failed to load land details.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LandDetail.fromJson(data);
  }

  Future<LandListItem> updateLand(
    String bearerToken,
    String landId,
    UpdateLandRequest request,
  ) async {
    final body = await _requestJson(
      () => ApiClient.putJson(
        '/lands/$landId',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'land_update',
      ),
      fallbackError: 'Failed to update land.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LandListItem.fromJson(data);
  }

  Future<LandMessageResponse> deleteLand(
    String bearerToken,
    String landId,
  ) async {
    final body = await _requestJson(
      () => ApiClient.deleteJson(
        '/lands/$landId',
        bearerToken: bearerToken,
        tag: 'land_delete',
      ),
      fallbackError: 'Failed to delete land.',
    );
    return LandMessageResponse.fromJson(body);
  }

  Future<SyncLandResult> markLandSynced(
    String bearerToken,
    String landId,
  ) async {
    final body = await _requestJson(
      () => ApiClient.postJsonNoBody(
        '/lands/$landId/sync',
        bearerToken: bearerToken,
        tag: 'land_mark_synced',
      ),
      fallbackError: 'Failed to mark land as synced.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SyncLandResult.fromJson(data);
  }

  Future<PaginatedMarkers> listMarkers(
    String bearerToken,
    String landId, {
    int perPage = 50,
  }) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/lands/$landId/markers',
        bearerToken: bearerToken,
        tag: 'land_markers_list',
        queryParameters: {'per_page': perPage},
      ),
      fallbackError: 'Failed to load markers.',
    );
    return PaginatedMarkers.fromJson(body);
  }

  Future<LandMarker> createMarker(
    String bearerToken,
    String landId,
    LandMarkerRequest request,
  ) async {
    final body = await _requestJson(
      () => ApiClient.postJson(
        '/lands/$landId/markers',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'land_marker_create',
      ),
      fallbackError: 'Failed to create marker.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LandMarker.fromJson(data);
  }

  Future<LandMarker> updateMarker(
    String bearerToken,
    String landId,
    String markerId,
    UpdateLandMarkerRequest request,
  ) async {
    final body = await _requestJson(
      () => ApiClient.putJson(
        '/lands/$landId/markers/$markerId',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'land_marker_update',
      ),
      fallbackError: 'Failed to update marker.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LandMarker.fromJson(data);
  }

  Future<LandMessageResponse> deleteMarker(
    String bearerToken,
    String landId,
    String markerId,
  ) async {
    final body = await _requestJson(
      () => ApiClient.deleteJson(
        '/lands/$landId/markers/$markerId',
        bearerToken: bearerToken,
        tag: 'land_marker_delete',
      ),
      fallbackError: 'Failed to delete marker.',
    );
    return LandMessageResponse.fromJson(body);
  }

  Future<RemoteSettingsOptions> getSettings(String bearerToken) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/settings',
        bearerToken: bearerToken,
        tag: 'land_settings_get',
      ),
      fallbackError: 'Failed to load settings.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RemoteSettingsOptions.fromJson(data);
  }

  Future<Map<String, dynamic>> _requestJson(
    Future<dynamic> Function() request, {
    required String fallbackError,
  }) async {
    try {
      final response = await request();
      final body = _decodeBody(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      }

      throw AuthException(_extractErrorMessage(body, fallbackError));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException(fallbackError);
    }
  }

  Map<String, dynamic> _decodeBody(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  String _extractErrorMessage(Map<String, dynamic> body, String fallback) {
    final topLevel = body['message']?.toString();
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final firstValue = errors.values.first;
      if (firstValue is List && firstValue.isNotEmpty) {
        return firstValue.first.toString();
      }
    }
    return (topLevel == null || topLevel.trim().isEmpty) ? fallback : topLevel;
  }
}
