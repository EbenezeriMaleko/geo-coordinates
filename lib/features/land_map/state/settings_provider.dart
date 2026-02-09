import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/coordinate_format.dart';

final coordinateFormatProvider =
    NotifierProvider<CoordinateFormatNotifier, CoordinateFormat>(
      CoordinateFormatNotifier.new,
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
