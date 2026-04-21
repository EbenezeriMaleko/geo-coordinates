import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'https://ardhi.co.tz/api/v1';
  static const Duration timeout = Duration(seconds: 30);

  static Uri uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
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

    print('[API][$requestTag] REQUEST POST $requestUri');

    try {
      final response = await http
          .post(
            requestUri,
            headers: jsonHeaders(bearerToken: bearerToken),
          )
          .timeout(timeout);

      print('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      print('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      print('[API][$requestTag] ERROR $error');
      rethrow;
    }
  }

  static Future<http.Response> getJson(
    String path, {
    String? bearerToken,
    String? tag,
  }) async {
    final requestTag = tag?.trim().isNotEmpty == true ? tag!.trim() : path;
    final requestUri = uri(path);

    print('[API][$requestTag] REQUEST GET $requestUri');

    try {
      final response = await http
          .get(
            requestUri,
            headers: jsonHeaders(bearerToken: bearerToken),
          )
          .timeout(timeout);

      print('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      print('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      print('[API][$requestTag] ERROR $error');
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

    print('[API][$requestTag] REQUEST PUT $requestUri');
    print('[API][$requestTag] REQUEST BODY ${_truncate(encodedBody)}');

    try {
      final response = await http
          .put(
            requestUri,
            headers: jsonHeaders(bearerToken: bearerToken),
            body: encodedBody,
          )
          .timeout(timeout);

      print('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      print('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      print('[API][$requestTag] ERROR $error');
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

    print('[API][$requestTag] REQUEST POST $requestUri');
    print('[API][$requestTag] REQUEST BODY ${_truncate(encodedBody)}');

    try {
      final response = await http
          .post(
            requestUri,
            headers: jsonHeaders(bearerToken: bearerToken),
            body: encodedBody,
          )
          .timeout(timeout);

      print('[API][$requestTag] RESPONSE STATUS ${response.statusCode}');
      print('[API][$requestTag] RESPONSE BODY ${_truncate(response.body)}');
      return response;
    } catch (error) {
      print('[API][$requestTag] ERROR $error');
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
