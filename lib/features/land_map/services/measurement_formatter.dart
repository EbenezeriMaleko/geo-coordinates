import '../state/settings_provider.dart';

class MeasurementFormatter {
  static const double metersToFeet = 3.280839895013123;
  static const double metersPerMile = 1609.344;
  static const double squareMetersToSquareFeet = 10.763910416709722;
  static const double squareMetersPerAcre = 4046.8564224;

  const MeasurementFormatter._();

  static String distance(double meters, DistanceUnit unit) {
    if (unit == DistanceUnit.feet) {
      if (meters.abs() >= metersPerMile) {
        return '${(meters / metersPerMile).toStringAsFixed(2)} mi';
      }
      return '${(meters * metersToFeet).toStringAsFixed(1)} ft';
    }
    if (meters.abs() >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(1)} m';
  }

  static String area(double squareMeters, DistanceUnit unit) {
    if (unit == DistanceUnit.feet) {
      if (squareMeters.abs() >= squareMetersPerAcre) {
        return '${(squareMeters / squareMetersPerAcre).toStringAsFixed(2)} ac';
      }
      return '${(squareMeters * squareMetersToSquareFeet).toStringAsFixed(1)} ft²';
    }
    if (squareMeters.abs() >= 10000) {
      return '${(squareMeters / 10000).toStringAsFixed(2)} ha';
    }
    return '${squareMeters.toStringAsFixed(1)} m²';
  }
}
