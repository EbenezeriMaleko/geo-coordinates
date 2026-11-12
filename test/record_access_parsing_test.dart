import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/land_map/models/land_api_models.dart';

void main() {
  test('list and detail preserve explicit read-only record access', () {
    final json = <String, dynamic>{
      'id': 4,
      'record_access': {'can_manage': false},
    };
    expect(LandListItem.fromJson(json).canManage, isFalse);
    expect(LandDetail.fromJson(json).canManage, isFalse);
    expect(
      LandDetail.fromJson({
        'id': 4,
        'record_access': {'can_manage': true},
      }).canManage,
      isTrue,
    );
  });
  test('legacy responses remain compatible without access metadata', () {
    expect(LandListItem.fromJson({'id': 4}).canManage, isTrue);
    expect(LandDetail.fromJson({'id': 4}).canManage, isTrue);
  });
}
