import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'http://10.160.38.178:8000/api/v1';
  static const Duration timeout = Duration(seconds: 30);

  static Uri uri(String path, {Map<String, dynamic>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  static Map<String, String> jsonHeaders({String? bearerToken}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final token = bearerToken?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Map<String, String> multipartHeaders({String? bearerToken}) {
    final headers = <String, String>{'Accept': 'application/json'};
    final token = bearerToken?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String originUrl() => Uri.parse(baseUrl).origin;

  static Future<http.Response> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    String? tag,
  }) {
    return _postJsonWithLogging(
      path,
      body: body,
      bearerToken: bearerToken,
      tag: tag,
    );
  }

  static Future<http.Response> postJsonNoBody(
    String path, {
    String? bearerToken,
    String? tag,
  }) async {
    final requestTag = tag?.trim().isNotEmpty == true ? tag!.trim() : path;
    final requestUri = uri(path);

    debugPrint('[API][$requestTag] REQUEST POST $requestUri');

    try {
      final response = await http
          .post(requestUri, headers: jsonHeaders(bearerToken: bearerToken))
          .timeout(timeout);

      debugPrint('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      debugPrint('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      debugPrint('[API][$requestTag] ERROR $error');
      rethrow;
    }
  }

  static Future<http.Response> getJson(
    String path, {
    String? bearerToken,
    String? tag,
    Map<String, dynamic>? queryParameters,
  }) async {
    final requestTag = tag?.trim().isNotEmpty == true ? tag!.trim() : path;
    final requestUri = uri(path, queryParameters: queryParameters);

    debugPrint('[API][$requestTag] REQUEST GET $requestUri');

    try {
      final response = await http
          .get(requestUri, headers: jsonHeaders(bearerToken: bearerToken))
          .timeout(timeout);

      debugPrint('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      debugPrint('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      debugPrint('[API][$requestTag] ERROR $error');
      rethrow;
    }
  }

  static Future<http.Response> putJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    String? tag,
  }) async {
    final requestTag = tag?.trim().isNotEmpty == true ? tag!.trim() : path;
    final requestUri = uri(path);
    final encodedBody = jsonEncode(body);

    debugPrint('[API][$requestTag] REQUEST PUT $requestUri');
    debugPrint('[API][$requestTag] REQUEST BODY ${_truncate(encodedBody)}');

    try {
      final response = await http
          .put(
            requestUri,
            headers: jsonHeaders(bearerToken: bearerToken),
            body: encodedBody,
          )
          .timeout(timeout);

      debugPrint('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      debugPrint('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      debugPrint('[API][$requestTag] ERROR $error');
      rethrow;
    }
  }

  static Future<http.Response> deleteJson(
    String path, {
    String? bearerToken,
    String? tag,
    Map<String, dynamic>? queryParameters,
  }) async {
    final requestTag = tag?.trim().isNotEmpty == true ? tag!.trim() : path;
    final requestUri = uri(path, queryParameters: queryParameters);

    debugPrint('[API][$requestTag] REQUEST DELETE $requestUri');

    try {
      final response = await http
          .delete(requestUri, headers: jsonHeaders(bearerToken: bearerToken))
          .timeout(timeout);

      debugPrint('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      debugPrint('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      debugPrint('[API][$requestTag] ERROR $error');
      rethrow;
    }
  }

  static Future<http.Response> _postJsonWithLogging(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    String? tag,
  }) async {
    final requestTag = tag?.trim().isNotEmpty == true ? tag!.trim() : path;
    final requestUri = uri(path);
    final encodedBody = jsonEncode(body);

    debugPrint('[API][$requestTag] REQUEST POST $requestUri');
    debugPrint('[API][$requestTag] REQUEST BODY ${_truncate(encodedBody)}');

    try {
      final response = await http
          .post(
            requestUri,
            headers: jsonHeaders(bearerToken: bearerToken),
            body: encodedBody,
          )
          .timeout(timeout);

      debugPrint('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      debugPrint('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      debugPrint('[API][$requestTag] ERROR $error');
      rethrow;
    }
  }

  static String _truncate(String value, {int maxLength = 2500}) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...<truncated>';
  }
}
