import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/land_map/services/measurement_formatter.dart';
import 'package:taref_gps/features/land_map/state/settings_provider.dart';

void main() {
  test('formats metric distance and area', () {
    expect(MeasurementFormatter.distance(500, DistanceUnit.meters), '500.0 m');
    expect(MeasurementFormatter.distance(1500, DistanceUnit.meters), '1.50 km');
    expect(MeasurementFormatter.area(1000, DistanceUnit.meters), '1000.0 m²');
    expect(MeasurementFormatter.area(20000, DistanceUnit.meters), '2.00 ha');
  });

  test('formats imperial distance and area', () {
    expect(MeasurementFormatter.distance(100, DistanceUnit.feet), '328.1 ft');
    expect(
      MeasurementFormatter.distance(1609.344, DistanceUnit.feet),
      '1.00 mi',
    );
    expect(MeasurementFormatter.area(100, DistanceUnit.feet), '1076.4 ft²');
    expect(
      MeasurementFormatter.area(4046.8564224, DistanceUnit.feet),
      '1.00 ac',
    );
  });
}
