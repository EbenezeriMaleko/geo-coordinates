import 'dart:math' as math;

import '../models/reference_ellipsoid.dart';

class UtmCoordinate {
  final int zoneNumber;
  final String zoneLetter;
  final double easting;
  final double northing;

  const UtmCoordinate({
    required this.zoneNumber,
    required this.zoneLetter,
    required this.easting,
    required this.northing,
  });

  String get zone => '$zoneNumber$zoneLetter';

  String toDisplayString({int decimals = 2}) {
    return 'UTM $zone  E ${easting.toStringAsFixed(decimals)}  N ${northing.toStringAsFixed(decimals)}';
  }
}

class UtmConverter {
  static const double _k0 = 0.9996;

  static UtmCoordinate? fromLatLng(
    double latitude,
    double longitude,
    ReferenceEllipsoid ellipsoid,
  ) {
    if (latitude < -80 || latitude > 84) return null;

    final config = _ellipsoidConfig(ellipsoid);
    final latRad = _degToRad(latitude);
    final lonRad = _degToRad(longitude);
    final zoneNumber = _zoneNumber(latitude, longitude);
    final zoneLetter = _zoneLetter(latitude);
    final longOrigin = (zoneNumber - 1) * 6 - 180 + 3;
    final longOriginRad = _degToRad(longOrigin.toDouble());
    final eccPrimeSquared = config.eccSquared / (1 - config.eccSquared);

    final sinLat = _sin(latRad);
    final cosLat = _cos(latRad);
    final tanLat = _tan(latRad);

    final n = config.equatorialRadius /
        _sqrt(1 - config.eccSquared * sinLat * sinLat);
    final t = tanLat * tanLat;
    final c = eccPrimeSquared * cosLat * cosLat;
    final a = cosLat * (lonRad - longOriginRad);

    final m = config.equatorialRadius *
        ((1 -
                    config.eccSquared / 4 -
                    3 * _pow2(config.eccSquared) / 64 -
                    5 * _pow3(config.eccSquared) / 256) *
                latRad -
            (3 * config.eccSquared / 8 +
                    3 * _pow2(config.eccSquared) / 32 +
                    45 * _pow3(config.eccSquared) / 1024) *
                _sin(2 * latRad) +
            (15 * _pow2(config.eccSquared) / 256 +
                    45 * _pow3(config.eccSquared) / 1024) *
                _sin(4 * latRad) -
            (35 * _pow3(config.eccSquared) / 3072) * _sin(6 * latRad));

    var easting = _k0 *
            n *
            (a +
                (1 - t + c) * _pow3(a) / 6 +
                (5 - 18 * t + t * t + 72 * c - 58 * eccPrimeSquared) *
                    _pow5(a) /
                    120) +
        500000.0;

    var northing = _k0 *
        (m +
            n *
                tanLat *
                (_pow2(a) / 2 +
                    (5 - t + 9 * c + 4 * c * c) * _pow4(a) / 24 +
                    (61 - 58 * t + t * t + 600 * c - 330 * eccPrimeSquared) *
                        _pow6(a) /
                        720));

    if (latitude < 0) {
      northing += 10000000.0;
    }

    if (easting == -0.0) easting = 0.0;
    if (northing == -0.0) northing = 0.0;

    return UtmCoordinate(
      zoneNumber: zoneNumber,
      zoneLetter: zoneLetter,
      easting: easting,
      northing: northing,
    );
  }

  static _EllipsoidConfig _ellipsoidConfig(ReferenceEllipsoid ellipsoid) {
    switch (ellipsoid) {
      case ReferenceEllipsoid.clarke1866:
        return const _EllipsoidConfig(6378206.4, 0.006768658);
      case ReferenceEllipsoid.clarke1880:
        return const _EllipsoidConfig(6378249.145, 0.006803511);
      case ReferenceEllipsoid.grs1967:
        return const _EllipsoidConfig(6378160.0, 0.006694605);
      case ReferenceEllipsoid.grs1980:
        return const _EllipsoidConfig(6378137.0, 0.00669438);
      case ReferenceEllipsoid.wgs60:
        return const _EllipsoidConfig(6378165.0, 0.006693422);
      case ReferenceEllipsoid.wgs66:
        return const _EllipsoidConfig(6378145.0, 0.006694542);
      case ReferenceEllipsoid.wgs72:
        return const _EllipsoidConfig(6378135.0, 0.006694318);
      case ReferenceEllipsoid.wgs84:
        return const _EllipsoidConfig(6378137.0, 0.00669438);
    }
  }

  static int _zoneNumber(double latitude, double longitude) {
    var zoneNumber = ((longitude + 180) / 6).floor() + 1;

    if (latitude >= 56.0 &&
        latitude < 64.0 &&
        longitude >= 3.0 &&
        longitude < 12.0) {
      zoneNumber = 32;
    }

    if (latitude >= 72.0 && latitude < 84.0) {
      if (longitude >= 0.0 && longitude < 9.0) zoneNumber = 31;
      if (longitude >= 9.0 && longitude < 21.0) zoneNumber = 33;
      if (longitude >= 21.0 && longitude < 33.0) zoneNumber = 35;
      if (longitude >= 33.0 && longitude < 42.0) zoneNumber = 37;
    }

    return zoneNumber.clamp(1, 60);
  }

  static String _zoneLetter(double latitude) {
    if (latitude >= 84 || latitude < -80) return 'Z';
    const letters = 'CDEFGHJKLMNPQRSTUVWX';
    final index = ((latitude + 80) / 8).floor().clamp(0, letters.length - 1);
    return letters[index];
  }

  static double _degToRad(double degrees) => degrees * 0.017453292519943295;
  static double _sqrt(double value) => value >= 0 ? math.sqrt(value) : 0;
  static double _sin(double value) => math.sin(value);
  static double _cos(double value) => math.cos(value);
  static double _tan(double value) => math.tan(value);
  static double _pow2(double value) => value * value;
  static double _pow3(double value) => value * value * value;
  static double _pow4(double value) => value * value * value * value;
  static double _pow5(double value) => value * value * value * value * value;
  static double _pow6(double value) =>
      value * value * value * value * value * value;
}

class _EllipsoidConfig {
  final double equatorialRadius;
  final double eccSquared;

  const _EllipsoidConfig(this.equatorialRadius, this.eccSquared);
}
