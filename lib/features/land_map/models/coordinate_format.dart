enum CoordinateFormat {
  decimalDegrees('Decimal Degrees', 'DD'),
  degreesMinutesSeconds('Degrees Minutes Seconds', 'DMS'),
  degreesDecimalMinutes('Degrees Decimal Minutes', 'DDM');

  final String displayName;
  final String shortName;
  const CoordinateFormat(this.displayName, this.shortName);
}

class CoordinateFormatter {
  static String format(
    double latitude,
    double longitude,
    CoordinateFormat format,
  ) {
    switch (format) {
      case CoordinateFormat.decimalDegrees:
        return _formatDecimalDegrees(latitude, longitude);
      case CoordinateFormat.degreesMinutesSeconds:
        return _formatDMS(latitude, longitude);
      case CoordinateFormat.degreesDecimalMinutes:
        return _formatDDM(latitude, longitude);
    }
  }

  static String _formatDecimalDegrees(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  static String _formatDMS(double latitude, double longitude) {
    final latStr = _toDMS(latitude, latitude >= 0 ? 'N' : 'S');
    final lonStr = _toDMS(longitude, longitude >= 0 ? 'E' : 'W');
    return '$latStr, $lonStr';
  }

  static String _toDMS(double decimal, String direction) {
    final absolute = decimal.abs();
    final degrees = absolute.floor();
    final minutesDecimal = (absolute - degrees) * 60;
    final minutes = minutesDecimal.floor();
    final seconds = (minutesDecimal - minutes) * 60;
    return '$degrees°$minutes\'${seconds.toStringAsFixed(2)}"$direction';
  }

  static String _formatDDM(double latitude, double longitude) {
    final latStr = _toDDM(latitude, latitude >= 0 ? 'N' : 'S');
    final lonStr = _toDDM(longitude, longitude >= 0 ? 'E' : 'W');
    return '$latStr, $lonStr';
  }

  static String _toDDM(double decimal, String direction) {
    final absolute = decimal.abs();
    final degrees = absolute.floor();
    final minutes = (absolute - degrees) * 60;
    return '$degrees°${minutes.toStringAsFixed(4)}\'$direction';
  }
}
