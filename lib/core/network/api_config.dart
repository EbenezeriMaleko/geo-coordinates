import 'package:flutter/foundation.dart';

class ApiConfig {
  static const configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dev.ardhi.co.tz/api/v1',
  );

  static String validate(String value, {required bool allowHttp}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' || (allowHttp && uri.scheme == 'http'))) {
      throw ArgumentError(
        'API_BASE_URL must be an absolute HTTPS API URL. '
        'HTTP is permitted only in debug builds for local testing.',
      );
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/api/v1')) {
      throw ArgumentError('API_BASE_URL must end with /api/v1.');
    }
    return uri.replace(path: path).toString();
  }

  static final baseUrl = validate(configuredUrl, allowHttp: kDebugMode);
}
