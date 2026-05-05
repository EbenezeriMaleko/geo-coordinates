import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart';
import '../models/reference_ellipsoid.dart';

class CoordinateConverter {
  /// Proj4 strings for each ellipsoid with WGS84 base for consistency
  static final Map<ReferenceEllipsoid, String> _projectionStrings = {
  // North America — NAD27 is correct here
  ReferenceEllipsoid.clarke1866:
      '+proj=longlat +ellps=clrk66 +datum=NAD27 +no_defs',

  // East Africa (Arc 1960) — Kenya + Tanzania mean solution ✅ EPSG verified
  ReferenceEllipsoid.clarke1880:
      '+proj=longlat +a=6378249.145 +rf=293.465 +towgs84=-160,-6,-302,0,0,0,0 +no_defs',

  // GRS 1967
  ReferenceEllipsoid.grs1967:
      '+proj=longlat +ellps=GRS67 +towgs84=-57,1,-41,0,0,0,0 +no_defs',

  // GRS 1980 — nearly identical to WGS84
  ReferenceEllipsoid.grs1980:
      '+proj=longlat +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +no_defs',

  // WGS 60
  ReferenceEllipsoid.wgs60:
      '+proj=longlat +ellps=WGS60 +towgs84=0,18,-181,0,0,0,0 +no_defs',

  // WGS 66
  ReferenceEllipsoid.wgs66:
      '+proj=longlat +ellps=WGS66 +towgs84=0,0,-4.5,0,0,0,0 +no_defs',

  // WGS 72 — 7-parameter, EPSG/PROJ verified ✅
  ReferenceEllipsoid.wgs72:
      '+proj=longlat +ellps=WGS72 +towgs84=0,0,4.5,0,0,0.554,0.219 +no_defs',

  // WGS 84 — modern GPS standard
  ReferenceEllipsoid.wgs84:
      '+proj=longlat +datum=WGS84 +no_defs',
};

  static final Map<String, Projection> _projectionCache = {};

  /// Get the proj4 projection string for a given ellipsoid
  static String getProjectionString(ReferenceEllipsoid ellipsoid) {
    return _projectionStrings[ellipsoid] ??
        '+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs';
  }

  /// Get or create a cached projection object
  static Projection _getProjection(ReferenceEllipsoid ellipsoid) {
    final key = ellipsoid.name;
    if (_projectionCache.containsKey(key)) {
      return _projectionCache[key]!;
    }

    final projection = Projection.parse(getProjectionString(ellipsoid));
    _projectionCache[key] = projection;
    return projection;
  }

  /// Convert coordinates from one ellipsoid to another
  /// Returns the converted LatLng
  static LatLng convertCoordinates(
    LatLng coordinates,
    ReferenceEllipsoid fromEllipsoid,
    ReferenceEllipsoid toEllipsoid,
  ) {
    // If converting to the same ellipsoid, return as-is
    if (fromEllipsoid == toEllipsoid) {
      return coordinates;
    }

    try {
      // Get projections for both ellipsoids
      final fromProj = _getProjection(fromEllipsoid);
      final toProj = _getProjection(toEllipsoid);

      // Create a point from the coordinates (in degrees, x=longitude, y=latitude)
      final point = Point(x: coordinates.longitude, y: coordinates.latitude);

      // Transform from source ellipsoid to target ellipsoid
      // using the transform method on the source projection
      final transformedPoint = fromProj.transform(toProj, point);

      // Debug print: show old -> new values
      try {
        final oldLat = coordinates.latitude.toStringAsFixed(6);
        final oldLon = coordinates.longitude.toStringAsFixed(6);
        final newLat = transformedPoint.y.toStringAsFixed(6);
        final newLon = transformedPoint.x.toStringAsFixed(6);
        debugPrint(
          'CoordinateConverter: ${fromEllipsoid.name} -> ${toEllipsoid.name}: '
          '$oldLat,$oldLon -> $newLat,$newLon',
        );
      } catch (_) {}

      return LatLng(transformedPoint.y, transformedPoint.x);
    } catch (e) {
      // If transformation fails, return original coordinates
      debugPrint('Error converting coordinates: $e');
      return coordinates;
    }
  }

  /// Convert a list of coordinates from one ellipsoid to another
  static List<LatLng> convertCoordinatesList(
    List<LatLng> coordinates,
    ReferenceEllipsoid fromEllipsoid,
    ReferenceEllipsoid toEllipsoid,
  ) {
    return coordinates
        .map((coord) => convertCoordinates(coord, fromEllipsoid, toEllipsoid))
        .toList();
  }

  /// Clear the projection cache (useful for testing or memory management)
  static void clearCache() {
    _projectionCache.clear();
  }
}
