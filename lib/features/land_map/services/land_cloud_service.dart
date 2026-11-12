import 'dart:convert';
import '../../workspaces/workspace_context.dart';

import '../../../core/network/api_client.dart';
import '../../auth/services/auth_service.dart';
import '../models/land_api_models.dart';

class LandCloudException extends AuthException {
  const LandCloudException(
    super.message, {
    required this.statusCode,
    this.reason,
    this.validationFields = const {},
  });
  final int statusCode;
  final String? reason;
  final Set<String> validationFields;
  bool get waitingForSpace =>
      statusCode == 422 && validationFields.contains('records');
}

class LandCloudService {
  Future<PaginatedLands> listLands(
    String bearerToken, {
    String? search,
    int perPage = 15,
    int page = 1,
    int? projectId,
    int? teamId,
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
          'project_id': ?projectId,
          'team_id': ?teamId,
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
    await _ensureManageable(bearerToken, landId);
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
    await _ensureManageable(bearerToken, landId);
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

  Future<void> _ensureManageable(String token, String landId) async {
    final company = WorkspaceContext.activeCompanyId;
    final detail = await getLand(token, landId);
    if (company != WorkspaceContext.activeCompanyId) {
      throw const AuthException('Workspace changed. Please try again.');
    }
    if (!detail.canManage) {
      throw const LandCloudException(
        'This cloud record is read-only after a plan change. Your local copy is retained.',
        statusCode: 403,
        reason: 'record_read_only',
      );
    }
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

      throw LandCloudException(
        _extractErrorMessage(body, fallbackError),
        statusCode: response.statusCode as int,
        reason: body['reason']?.toString(),
        validationFields: body['errors'] is Map
            ? (body['errors'] as Map).keys.map((key) => key.toString()).toSet()
            : const {},
      );
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
