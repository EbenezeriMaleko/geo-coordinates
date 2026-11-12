import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';

class RecordShareService {
  RecordShareService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  void dispose() => _client.close();

  Future<Map<String, dynamic>> request({
    required String token,
    required int record,
    required int? company,
    required bool Function() isCurrent,
    String method = 'GET',
    int? linkId,
    int page = 1,
    Map<String, dynamic>? body,
  }) async {
    if (record < 1 || !isCurrent()) {
      throw Exception('Workspace or account changed. Reopen sharing.');
    }
    final headers = ApiClient.jsonHeaders(bearerToken: token)
      ..remove('X-Company-Id');
    if (company != null) headers['X-Company-Id'] = '$company';
    final suffix = linkId == null ? '' : '/$linkId';
    final uri = ApiClient.uri(
      '/lands/$record/shares$suffix',
      queryParameters: method == 'GET' ? {'page': page} : null,
    );
    if (kReleaseMode && uri.scheme != 'https') {
      throw Exception('Secure HTTPS is required for record sharing.');
    }
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await _client.send(request).timeout(ApiClient.timeout);
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(ApiClient.timeout)) {
      if (!isCurrent()) {
        throw Exception('Workspace or account changed. Reopen sharing.');
      }
      if (bytes.length + chunk.length > 256 * 1024) {
        throw Exception('Sharing response is too large.');
      }
      bytes.addAll(chunk);
    }
    if (!isCurrent()) {
      throw Exception('Workspace or account changed. Reopen sharing.');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw Exception('Invalid sharing response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded is Map && decoded['message'] is String
            ? decoded['message']
            : 'Unable to update sharing.',
      );
    }
    if (decoded is! Map || decoded['data'] is! Map) {
      throw Exception('Invalid sharing response.');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    if (data['company'] != (company != null) ||
        data['can_manage'] is! bool ||
        data['policy'] is! Map ||
        data['links'] is! List) {
      throw Exception('Invalid sharing response for this workspace.');
    }
    return data;
  }

  static bool safeUrl(String value) {
    final url = Uri.tryParse(value);
    final origin = Uri.parse(ApiClient.originUrl());
    return url != null &&
        url.hasScheme &&
        url.hasAuthority &&
        (url.scheme == 'https' || url.scheme == 'http') &&
        url.origin == origin.origin &&
        url.userInfo.isEmpty &&
        RegExp(r'^/s/[a-f0-9]{64}$').hasMatch(url.path) &&
        !url.hasQuery &&
        !url.hasFragment;
  }
}
