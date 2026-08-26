import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart';

import '../models/display_coordinate.dart';
import '../models/geodetic_datum.dart';
import '../models/reference_ellipsoid.dart';
import 'utm_converter.dart';

class CoordinateConverter {
  static final Map<String, Projection> _projectionCache = {};

  /// Derives secondary coordinates from immutable canonical WGS84 Lat/Lon.
  /// EPSG translation parameters describe selected datum -> WGS84, and
  /// proj4dart applies their inverse when WGS84 is the source.
  static DisplayCoordinate deriveDisplayCoordinate(
    LatLng canonicalWgs84,
    ReferenceEllipsoid ellipsoid,
    GeodeticDatum? datum,
  ) {
    if (datum != null && datum.parentEllipsoid != ellipsoid) {
      throw ArgumentError(
        '${datum.displayName} does not use ${ellipsoid.displayName}.',
      );
    }
    if (!canonicalWgs84.latitude.isFinite ||
        !canonicalWgs84.longitude.isFinite ||
        canonicalWgs84.latitude < -90 ||
        canonicalWgs84.latitude > 90 ||
        canonicalWgs84.longitude < -180 ||
        canonicalWgs84.longitude > 180) {
      throw ArgumentError.value(canonicalWgs84, 'canonicalWgs84');
    }

    final selectedGeodetic =
        ellipsoid == ReferenceEllipsoid.wgs84 && datum == null
        ? canonicalWgs84
        : _toSelectedGeodetic(canonicalWgs84, ellipsoid, datum);
    return DisplayCoordinate(
      canonicalWgs84: canonicalWgs84,
      geodeticOnSelectedDatum: selectedGeodetic,
      utm: UtmConverter.fromLatLng(
        selectedGeodetic.latitude,
        selectedGeodetic.longitude,
        ellipsoid,
        semiMajorAxis: datum?.semiMajorAxis,
        inverseFlattening: datum?.inverseFlattening,
      ),
    );
  }

  static LatLng _toSelectedGeodetic(
    LatLng canonical,
    ReferenceEllipsoid ellipsoid,
    GeodeticDatum? datum,
  ) {
    final source = _projectionCache.putIfAbsent(
      'wgs84',
      () => Projection.parse('+proj=longlat +datum=WGS84 +no_defs'),
    );
    final destination = _projectionCache.putIfAbsent(
      '${ellipsoid.name}:${datum?.id ?? 'shape'}',
      () => Projection.parse(_geographicDefinition(ellipsoid, datum)),
    );
    final result = source.transform(
      destination,
      Point(x: canonical.longitude, y: canonical.latitude),
    );
    return LatLng(result.y, result.x);
  }

  static String _geographicDefinition(
    ReferenceEllipsoid ellipsoid,
    GeodeticDatum? datum,
  ) {
    final shape = datum == null
        ? _shapeParameters[ellipsoid]
        : '+a=${datum.semiMajorAxis} +rf=${datum.inverseFlattening}';
    return '+proj=longlat $shape '
        '+towgs84=${datum?.towgs84 ?? '0,0,0'} +no_defs';
  }

  static const Map<ReferenceEllipsoid, String> _shapeParameters = {
    ReferenceEllipsoid.clarke1880: '+a=6378249.145 +rf=293.465',
    ReferenceEllipsoid.clarke1866: '+a=6378206.4 +b=6356583.8',
    ReferenceEllipsoid.grs1980: '+a=6378137 +rf=298.257222101',
    ReferenceEllipsoid.grs1967: '+a=6378160 +rf=298.247167427',
    ReferenceEllipsoid.wgs84: '+a=6378137 +rf=298.257223563',
    ReferenceEllipsoid.wgs72: '+a=6378135 +rf=298.26',
    ReferenceEllipsoid.wgs66: '+a=6378145 +rf=298.25',
    ReferenceEllipsoid.wgs60: '+a=6378165 +rf=298.3',
  };

  static void clearCache() => _projectionCache.clear();
}
