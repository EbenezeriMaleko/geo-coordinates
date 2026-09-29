import '../state/settings_provider.dart';

enum AreaDisplayUnit {
  automatic('Automatic'),
  squareMeters('Square metres (m²)'),
  hectares('Hectares (ha)'),
  squareKilometers('Square kilometres (km²)'),
  squareFeet('Square feet (ft²)'),
  acres('Acres (ac)');

  const AreaDisplayUnit(this.label);

  final String label;
}

class MeasurementFormatter {
  static const double metersToFeet = 3.280839895013123;
  static const double metersPerMile = 1609.344;
  static const double squareMetersToSquareFeet = 10.763910416709722;
  static const double squareMetersPerAcre = 4046.8564224;
  static const double squareMetersPerHectare = 10000;
  static const double squareMetersPerSquareKilometer = 1000000;

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

  static String areaIn(
    double squareMeters,
    AreaDisplayUnit displayUnit,
    DistanceUnit defaultUnit,
  ) {
    switch (displayUnit) {
      case AreaDisplayUnit.automatic:
        return area(squareMeters, defaultUnit);
      case AreaDisplayUnit.squareMeters:
        return '${squareMeters.toStringAsFixed(1)} m²';
      case AreaDisplayUnit.hectares:
        return '${_areaDecimal(squareMeters / squareMetersPerHectare)} ha';
      case AreaDisplayUnit.squareKilometers:
        return '${_areaDecimal(squareMeters / squareMetersPerSquareKilometer)} km²';
      case AreaDisplayUnit.squareFeet:
        return '${(squareMeters * squareMetersToSquareFeet).toStringAsFixed(1)} ft²';
      case AreaDisplayUnit.acres:
        return '${_areaDecimal(squareMeters / squareMetersPerAcre)} ac';
    }
  }

  static String _areaDecimal(double value) =>
      value.abs() < 1 ? value.toStringAsFixed(4) : value.toStringAsFixed(2);
}
