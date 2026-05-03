import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../auth/services/auth_service.dart';
import '../models/location_media_models.dart';
import 'package:http_parser/http_parser.dart';

class LocationMediaService {
  Future<PaginatedLocationRecords> listLocations(
    String bearerToken, {
    int perPage = 20,
  }) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/locations',
        bearerToken: bearerToken,
        tag: 'locations_list',
        queryParameters: {'per_page': perPage},
      ),
      fallbackError: 'Failed to load locations.',
    );
    return PaginatedLocationRecords.fromJson(body);
  }

  Future<LocationRecord> createLocation(
    String bearerToken,
    CreateLocationRequest request,
  ) async {
    final body = await _requestJson(
      () => ApiClient.postJson(
        '/locations',
        body: request.toJson(),
        bearerToken: bearerToken,
        tag: 'location_create',
      ),
      fallbackError: 'Failed to create location.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LocationRecord.fromJson(data);
  }

  Future<LocationRecord> getLocation(
    String bearerToken,
    String locationId,
  ) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/locations/$locationId',
        bearerToken: bearerToken,
        tag: 'location_get',
      ),
      fallbackError: 'Failed to load location details.',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LocationRecord.fromJson(data);
  }

  Future<LocationMediaItem> uploadLocationMedia(
    String bearerToken,
    String locationId,
    String filePath,
    String mediaType,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        ApiClient.uri('/locations/$locationId/media'),
      );
      request.headers.addAll(
        ApiClient.multipartHeaders(bearerToken: bearerToken),
      );

      final mimeType = _detectMimeType(filePath, mediaType);
      final contentType = MediaType.parse(mimeType);

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: File(filePath).path.split(Platform.pathSeparator).last,
          contentType: contentType,
        ),
      );

      final streamed = await request.send().timeout(ApiClient.timeout);
      final response = await http.Response.fromStream(streamed);
      final body = _decodeBody(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data =
            (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
        return LocationMediaItem.fromJson(data);
      }

      throw AuthException(
        _extractErrorMessage(body, 'Failed to upload media.'),
      );
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
    }
  }

  Future<PaginatedLocationMedia> listMedia(
    String bearerToken, {
    String? type,
    int perPage = 10,
  }) async {
    final body = await _requestJson(
      () => ApiClient.getJson(
        '/locations/media',
        bearerToken: bearerToken,
        tag: 'location_media_list',
        queryParameters: {
          if ((type ?? '').trim().isNotEmpty) 'type': type!.trim(),
          'per_page': perPage,
        },
      ),
      fallbackError: 'Failed to load media.',
    );
    return PaginatedLocationMedia.fromJson(body);
  }

  Future<void> deleteMedia(String bearerToken, String mediaId) async {
    await _requestJson(
      () => ApiClient.deleteJson(
        '/locations/media/$mediaId',
        bearerToken: bearerToken,
        tag: 'location_media_delete',
      ),
      fallbackError: 'Failed to delete media.',
    );
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
      throw const AuthException(
        'Unable to connect. Check your internet connection.',
      );
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

  String _detectMimeType(String filePath, String mediaType) {
    final extension = filePath.split('.').last.toLowerCase();

    if (mediaType == 'video') {
      switch (extension) {
        case 'mp4':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        case 'mkv':
          return 'video/x-matroska';
        case 'webm':
          return 'video/webm';
        default:
          return 'video/mp4'; // Fallback for videos
      }
    } else {
      // Image mime type detection
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg'; // Fallback for images
      }
    }
  }
}
