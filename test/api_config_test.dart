import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/core/network/api_config.dart';

void main() {
  test('normalizes staging and production HTTPS endpoints', () {
    for (final host in ['dev.ardhi.co.tz', 'ardhi.co.tz']) {
      expect(
        ApiConfig.validate('https://$host/api/v1/', allowHttp: false),
        'https://$host/api/v1',
      );
    }
  });

  test('allows explicit HTTP endpoints for debug local testing only', () {
    expect(
      ApiConfig.validate('http://192.168.1.8:8000/api/v1', allowHttp: true),
      'http://192.168.1.8:8000/api/v1',
    );
    expect(
      () =>
          ApiConfig.validate('http://dev.ardhi.co.tz/api/v1', allowHttp: false),
      throwsArgumentError,
    );
  });

  test('rejects malformed, credential-bearing, and ambiguous URLs', () {
    for (final url in [
      '',
      '/api/v1',
      'https://example.test',
      'ftp://example.test/api/v1',
      'https://user:secret@example.test/api/v1',
      'https://example.test/api/v1?key=secret',
      'https://example.test/api/v1#fragment',
    ]) {
      expect(
        () => ApiConfig.validate(url, allowHttp: false),
        throwsArgumentError,
      );
    }
  });
}
