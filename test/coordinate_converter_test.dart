import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taref_gps/features/land_map/models/geodetic_datum.dart';
import 'package:taref_gps/features/land_map/models/reference_ellipsoid.dart';
import 'package:taref_gps/features/land_map/services/coordinate_converter.dart';

void main() {
  tearDown(CoordinateConverter.clearCache);

  test('registry exposes EPSG-sourced worldwide datum operations', () {
    expect(
      GeodeticDatumRegistry.forEllipsoid(ReferenceEllipsoid.clarke1880),
      containsAll([
        GeodeticDatumRegistry.arc1960,
        GeodeticDatumRegistry.arc1960Kenya,
        GeodeticDatumRegistry.arc1960Tanzania,
        GeodeticDatumRegistry.arc1950,
      ]),
    );
    expect(
      GeodeticDatumRegistry.forEllipsoid(ReferenceEllipsoid.wgs84),
      isEmpty,
    );
    expect(GeodeticDatumRegistry.forEllipsoid(ReferenceEllipsoid.clarke1866), [
      GeodeticDatumRegistry.nad27Conus,
    ]);
    expect(
      GeodeticDatumRegistry.forEllipsoid(ReferenceEllipsoid.grs1980),
      containsAll([
        GeodeticDatumRegistry.nad83,
        GeodeticDatumRegistry.etrs89,
        GeodeticDatumRegistry.gda94,
      ]),
    );
    expect(GeodeticDatumRegistry.forEllipsoid(ReferenceEllipsoid.wgs72), [
      GeodeticDatumRegistry.wgs72,
    ]);
    expect(GeodeticDatumRegistry.arc1960.epsgSource, contains('/1122'));
  });

  test('operations valid at the current location are ordered first', () {
    final tanzania = GeodeticDatumRegistry.orderedForLocation(
      ReferenceEllipsoid.clarke1880,
      const LatLng(-6.8, 39.2833),
    );
    expect(tanzania.first, GeodeticDatumRegistry.arc1960Tanzania);

    final europe = GeodeticDatumRegistry.orderedForLocation(
      ReferenceEllipsoid.grs1980,
      const LatLng(52.52, 13.405),
    );
    expect(europe.first, GeodeticDatumRegistry.etrs89);
  });

  test('datum-specific ellipsoid variants are preserved', () {
    expect(
      GeodeticDatumRegistry.arc1950.inverseFlattening,
      isNot(GeodeticDatumRegistry.arc1960.inverseFlattening),
    );
  });

  test('datum must belong to the selected ellipsoid', () {
    expect(
      () => CoordinateConverter.deriveDisplayCoordinate(
        const LatLng(-6.8, 39.2833),
        ReferenceEllipsoid.grs1980,
        GeodeticDatumRegistry.arc1960,
      ),
      throwsArgumentError,
    );
  });

  test('canonical WGS84 remains identical through repeated selections', () {
    const canonical = LatLng(-6.655303, 39.185703);
    final selections = <(ReferenceEllipsoid, GeodeticDatum?)>[
      (ReferenceEllipsoid.clarke1880, GeodeticDatumRegistry.arc1960),
      (ReferenceEllipsoid.grs1980, GeodeticDatumRegistry.nad83),
      (ReferenceEllipsoid.clarke1880, GeodeticDatumRegistry.arc1960),
      (ReferenceEllipsoid.wgs84, null),
    ];

    for (final selection in selections) {
      final result = CoordinateConverter.deriveDisplayCoordinate(
        canonical,
        selection.$1,
        selection.$2,
      );
      expect(identical(result.canonicalWgs84, canonical), isTrue);
      expect(result.canonicalWgs84.latitude, canonical.latitude);
      expect(result.canonicalWgs84.longitude, canonical.longitude);
    }
  });

  test('switching away and back has no compounding drift', () {
    const canonical = LatLng(-6.655303, 39.185703);
    final first = CoordinateConverter.deriveDisplayCoordinate(
      canonical,
      ReferenceEllipsoid.clarke1880,
      GeodeticDatumRegistry.arc1960,
    );

    CoordinateConverter.deriveDisplayCoordinate(
      canonical,
      ReferenceEllipsoid.grs1980,
      GeodeticDatumRegistry.nad83,
    );
    final second = CoordinateConverter.deriveDisplayCoordinate(
      canonical,
      ReferenceEllipsoid.clarke1880,
      GeodeticDatumRegistry.arc1960,
    );

    expect(
      second.geodeticOnSelectedDatum.latitude,
      first.geodeticOnSelectedDatum.latitude,
    );
    expect(
      second.geodeticOnSelectedDatum.longitude,
      first.geodeticOnSelectedDatum.longitude,
    );
    expect(second.utm!.easting, first.utm!.easting);
    expect(second.utm!.northing, first.utm!.northing);
  });

  test('Arc 1960 changes derived values but not displayed WGS84 Lat/Lon', () {
    const canonical = LatLng(-6.655303, 39.185703);
    final wgs84 = CoordinateConverter.deriveDisplayCoordinate(
      canonical,
      ReferenceEllipsoid.wgs84,
      null,
    );
    final arc1960 = CoordinateConverter.deriveDisplayCoordinate(
      canonical,
      ReferenceEllipsoid.clarke1880,
      GeodeticDatumRegistry.arc1960,
    );

    expect(arc1960.canonicalWgs84, canonical);
    expect(arc1960.geodeticOnSelectedDatum, isNot(canonical));
    expect(arc1960.utm!.easting, isNot(closeTo(wgs84.utm!.easting, 0.001)));
    expect(arc1960.utm!.northing, isNot(closeTo(wgs84.utm!.northing, 0.001)));
  });
}
