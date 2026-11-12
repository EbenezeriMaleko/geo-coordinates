import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/land_map/models/land_api_models.dart';

void main() {
  test('company parcel fields serialize with the server field names', () {
    const request = CreateLandRequest(
      type: 'point',
      name: 'Plot 12',
      coordinates: [],
      claimantName: '  Jane Doe  ',
      claimantPhone: ' +255700000000 ',
      plotNumber: ' 12 ',
      landUse: ' Residential ',
    );
    final json = request.toJson();
    expect(json['claimant_name'], 'Jane Doe');
    expect(json['claimant_phone'], '+255700000000');
    expect(json['plot_number'], '12');
    expect(json['land_use'], 'Residential');
    expect(json.containsKey('claimant_id'), isFalse);
  });

  test('personal requests omit optional company fields', () {
    const request = UpdateLandRequest(name: 'Personal record');
    final json = request.toJson();
    expect(json.containsKey('claimant_name'), isFalse);
    expect(json.containsKey('claimant_phone'), isFalse);
    expect(json.containsKey('plot_number'), isFalse);
    expect(json.containsKey('land_use'), isFalse);
  });

  test('updates can clear company fields', () {
    const request = UpdateLandRequest(claimantName: '', plotNumber: '');
    expect(request.toJson()['claimant_name'], '');
    expect(request.toJson()['plot_number'], '');
  });

  test('record details parse masked IDs without exposing the original', () {
    final record = LandListItem.fromJson({
      'id': 1,
      'claimant_name': 'Jane Doe',
      'claimant_id_masked': '****1234',
      'plot_number': '12',
    });
    expect(record.claimantName, 'Jane Doe');
    expect(record.claimantIdMasked, '****1234');
    expect(record.plotNumber, '12');
  });
}
