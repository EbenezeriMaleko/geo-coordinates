import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/coordinate_format.dart';

enum DistanceUnit { meters, feet }

final coordinateFormatProvider =
    NotifierProvider<CoordinateFormatNotifier, CoordinateFormat>(
      CoordinateFormatNotifier.new,
    );

final distanceUnitProvider = NotifierProvider<DistanceUnitNotifier, DistanceUnit>(
  DistanceUnitNotifier.new,
);

class CoordinateFormatNotifier extends Notifier<CoordinateFormat> {
  @override
  CoordinateFormat build() {
    return CoordinateFormat.decimalDegrees;
  }

  void setFormat(CoordinateFormat format) {
    state = format;
  }
}

class DistanceUnitNotifier extends Notifier<DistanceUnit> {
  @override
  DistanceUnit build() {
    return DistanceUnit.feet;
  }

  void setUnit(DistanceUnit unit) {
    state = unit;
  }
}
