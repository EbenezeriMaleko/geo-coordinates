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

  test('area display units convert only the view from square metres', () {
    const sqm = 10000.0;
    expect(
      MeasurementFormatter.areaIn(
        sqm,
        AreaDisplayUnit.automatic,
        DistanceUnit.meters,
      ),
      '1.00 ha',
    );
    expect(
      MeasurementFormatter.areaIn(
        sqm,
        AreaDisplayUnit.squareMeters,
        DistanceUnit.feet,
      ),
      '10000.0 m²',
    );
    expect(
      MeasurementFormatter.areaIn(
        sqm,
        AreaDisplayUnit.hectares,
        DistanceUnit.feet,
      ),
      '1.00 ha',
    );
    expect(
      MeasurementFormatter.areaIn(
        sqm,
        AreaDisplayUnit.squareKilometers,
        DistanceUnit.meters,
      ),
      '0.0100 km²',
    );
    expect(
      MeasurementFormatter.areaIn(
        MeasurementFormatter.squareMetersPerAcre,
        AreaDisplayUnit.acres,
        DistanceUnit.meters,
      ),
      '1.00 ac',
    );
    expect(
      MeasurementFormatter.areaIn(
        100,
        AreaDisplayUnit.squareFeet,
        DistanceUnit.meters,
      ),
      '1076.4 ft²',
    );
  });
}
