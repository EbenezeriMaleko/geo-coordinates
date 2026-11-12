import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/land_map/services/land_cloud_service.dart';

void main() {
  test('record quota validation is distinguished from other failures', () {
    expect(const LandCloudException('Full', statusCode: 422, validationFields: {'records'}).waitingForSpace, isTrue);
    expect(const LandCloudException('Invalid name', statusCode: 422, validationFields: {'name'}).waitingForSpace, isFalse);
    expect(const LandCloudException('Unauthorized', statusCode: 403, validationFields: {'records'}).waitingForSpace, isFalse);
    expect(const LandCloudException('Unavailable', statusCode: 503).waitingForSpace, isFalse);
  });
}
