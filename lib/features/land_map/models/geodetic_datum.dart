import 'package:latlong2/latlong.dart';

import 'reference_ellipsoid.dart';

class GeographicBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const GeographicBounds(this.south, this.west, this.north, this.east);

  bool contains(LatLng point) {
    final inLatitude = point.latitude >= south && point.latitude <= north;
    final inLongitude = west <= east
        ? point.longitude >= west && point.longitude <= east
        : point.longitude >= west || point.longitude <= east;
    return inLatitude && inLongitude;
  }
}

class GeodeticDatum {
  final String id;
  final String displayName;
  final ReferenceEllipsoid parentEllipsoid;
  final int epsgCrsCode;
  final int epsgOperationCode;
  final double semiMajorAxis;
  final double inverseFlattening;
  final double dX;
  final double dY;
  final double dZ;
  final double rX;
  final double rY;
  final double rZ;
  final double scalePpm;
  final String areaOfUse;
  final GeographicBounds bounds;
  final double accuracyMeters;
  final String epsgSource;
  final bool isApproximate;

  const GeodeticDatum({
    required this.id,
    required this.displayName,
    required this.parentEllipsoid,
    required this.epsgCrsCode,
    required this.epsgOperationCode,
    required this.semiMajorAxis,
    required this.inverseFlattening,
    required this.dX,
    required this.dY,
    required this.dZ,
    this.rX = 0,
    this.rY = 0,
    this.rZ = 0,
    this.scalePpm = 0,
    required this.areaOfUse,
    required this.bounds,
    required this.accuracyMeters,
    required this.epsgSource,
    this.isApproximate = false,
  });

  bool isValidAt(LatLng point) => bounds.contains(point);

  String get towgs84 => '$dX,$dY,$dZ,$rX,$rY,$rZ,$scalePpm';
}

class GeodeticDatumRegistry {
  // All parameters and accuracy values below are copied from the cited EPSG
  // coordinate operations. Approximate entries explicitly represent EPSG's
  // stated assumption that the local datum and WGS 84 are coincident.
  static const arc1960 = GeodeticDatum(
    id: 'epsg_4210_1122',
    displayName: 'Arc 1960 — Kenya/Tanzania mean',
    parentEllipsoid: ReferenceEllipsoid.clarke1880,
    epsgCrsCode: 4210,
    epsgOperationCode: 1122,
    semiMajorAxis: 6378249.145,
    inverseFlattening: 293.465,
    dX: -160,
    dY: -6,
    dZ: -302,
    areaOfUse: 'Kenya and Tanzania',
    bounds: GeographicBounds(-11.75, 28.85, 4.63, 41.91),
    accuracyMeters: 35,
    epsgSource: 'https://epsg.io/1122',
  );

  static const arc1960Kenya = GeodeticDatum(
    id: 'epsg_4210_1284',
    displayName: 'Arc 1960 — Kenya',
    parentEllipsoid: ReferenceEllipsoid.clarke1880,
    epsgCrsCode: 4210,
    epsgOperationCode: 1284,
    semiMajorAxis: 6378249.145,
    inverseFlattening: 293.465,
    dX: -157,
    dY: -2,
    dZ: -299,
    areaOfUse: 'Kenya — onshore',
    bounds: GeographicBounds(-4.72, 33.90, 4.63, 41.91),
    accuracyMeters: 6,
    epsgSource: 'https://epsg.io/1284',
  );

  static const arc1960Tanzania = GeodeticDatum(
    id: 'epsg_4210_1285',
    displayName: 'Arc 1960 — Tanzania',
    parentEllipsoid: ReferenceEllipsoid.clarke1880,
    epsgCrsCode: 4210,
    epsgOperationCode: 1285,
    semiMajorAxis: 6378249.145,
    inverseFlattening: 293.465,
    dX: -175,
    dY: -23,
    dZ: -303,
    areaOfUse: 'Tanzania — onshore',
    bounds: GeographicBounds(-11.75, 29.34, -0.99, 40.48),
    accuracyMeters: 15,
    epsgSource: 'https://epsg.io/1285',
  );

  static const arc1950 = GeodeticDatum(
    id: 'epsg_4209_1113',
    displayName: 'Arc 1950 — Southern Africa mean',
    parentEllipsoid: ReferenceEllipsoid.clarke1880,
    epsgCrsCode: 4209,
    epsgOperationCode: 1113,
    semiMajorAxis: 6378249.145,
    inverseFlattening: 293.4663077,
    dX: -143,
    dY: -90,
    dZ: -294,
    areaOfUse: 'Botswana, Eswatini, Lesotho, Malawi, Zambia and Zimbabwe',
    bounds: GeographicBounds(-30.66, 19.99, -8.19, 35.93),
    accuracyMeters: 44,
    epsgSource: 'https://epsg.io/1113',
  );

  static const nad27Conus = GeodeticDatum(
    id: 'epsg_4267_1173',
    displayName: 'NAD27 — CONUS',
    parentEllipsoid: ReferenceEllipsoid.clarke1866,
    epsgCrsCode: 4267,
    epsgOperationCode: 1173,
    semiMajorAxis: 6378206.4,
    inverseFlattening: 294.978698213898,
    dX: -8,
    dY: 160,
    dZ: 176,
    areaOfUse: 'Contiguous United States — onshore',
    bounds: GeographicBounds(24.41, -124.79, 49.38, -66.91),
    accuracyMeters: 10,
    epsgSource: 'https://epsg.io/1173',
  );

  static const nad83 = GeodeticDatum(
    id: 'epsg_4269_1188',
    displayName: 'NAD83 — North America',
    parentEllipsoid: ReferenceEllipsoid.grs1980,
    epsgCrsCode: 4269,
    epsgOperationCode: 1188,
    semiMajorAxis: 6378137,
    inverseFlattening: 298.257222101,
    dX: 0,
    dY: 0,
    dZ: 0,
    areaOfUse: 'North America',
    bounds: GeographicBounds(23.81, -172.54, 86.46, -47.74),
    accuracyMeters: 4,
    epsgSource: 'https://epsg.io/1188',
    isApproximate: true,
  );

  static const etrs89 = GeodeticDatum(
    id: 'epsg_4258_1149',
    displayName: 'ETRS89 — Europe',
    parentEllipsoid: ReferenceEllipsoid.grs1980,
    epsgCrsCode: 4258,
    epsgOperationCode: 1149,
    semiMajorAxis: 6378137,
    inverseFlattening: 298.257222101,
    dX: 0,
    dY: 0,
    dZ: 0,
    areaOfUse: 'Europe — onshore and offshore',
    bounds: GeographicBounds(33.26, -16.10, 84.73, 38.01),
    accuracyMeters: 1,
    epsgSource: 'https://epsg.io/1149',
    isApproximate: true,
  );

  static const gda94 = GeodeticDatum(
    id: 'epsg_4283_1150',
    displayName: 'GDA94 — Australia',
    parentEllipsoid: ReferenceEllipsoid.grs1980,
    epsgCrsCode: 4283,
    epsgOperationCode: 1150,
    semiMajorAxis: 6378137,
    inverseFlattening: 298.257222101,
    dX: 0,
    dY: 0,
    dZ: 0,
    areaOfUse: 'Australia and external territories',
    bounds: GeographicBounds(-60.55, 93.41, -8.47, 173.34),
    accuracyMeters: 3,
    epsgSource: 'https://epsg.io/1150',
    isApproximate: true,
  );

  static const sad69 = GeodeticDatum(
    id: 'epsg_4618_1864',
    displayName: 'SAD69 — South America mean',
    parentEllipsoid: ReferenceEllipsoid.grs1967,
    epsgCrsCode: 4618,
    epsgOperationCode: 1864,
    semiMajorAxis: 6378160,
    inverseFlattening: 298.25,
    dX: -57,
    dY: 1,
    dZ: -41,
    areaOfUse: 'South America onshore north of 45°S, excluding Amazonia',
    bounds: GeographicBounds(-45, -81.41, 12.52, -34.74),
    accuracyMeters: 19,
    epsgSource: 'https://epsg.io/1864',
  );

  static const wgs72 = GeodeticDatum(
    id: 'epsg_4322_1238',
    displayName: 'WGS 72 — global',
    parentEllipsoid: ReferenceEllipsoid.wgs72,
    epsgCrsCode: 4322,
    epsgOperationCode: 1238,
    semiMajorAxis: 6378135,
    inverseFlattening: 298.26,
    dX: 0,
    dY: 0,
    dZ: 4.5,
    rZ: 0.554,
    scalePpm: 0.219,
    areaOfUse: 'World',
    bounds: GeographicBounds(-90, -180, 90, 180),
    accuracyMeters: 2,
    epsgSource: 'https://epsg.io/1238',
  );

  static const Map<ReferenceEllipsoid, List<GeodeticDatum>> _registry = {
    ReferenceEllipsoid.clarke1880: [
      arc1960Tanzania,
      arc1960Kenya,
      arc1960,
      arc1950,
    ],
    ReferenceEllipsoid.clarke1866: [nad27Conus],
    ReferenceEllipsoid.grs1980: [nad83, etrs89, gda94],
    ReferenceEllipsoid.grs1967: [sad69],
    ReferenceEllipsoid.wgs84: [],
    ReferenceEllipsoid.wgs72: [wgs72],
    ReferenceEllipsoid.wgs66: [],
    ReferenceEllipsoid.wgs60: [],
  };

  static List<GeodeticDatum> forEllipsoid(ReferenceEllipsoid ellipsoid) =>
      List.unmodifiable(_registry[ellipsoid] ?? const []);

  static List<GeodeticDatum> orderedForLocation(
    ReferenceEllipsoid ellipsoid,
    LatLng? location,
  ) {
    final datums = forEllipsoid(ellipsoid).toList();
    if (location == null) return datums;
    datums.sort((left, right) {
      final byArea = (right.isValidAt(location) ? 1 : 0).compareTo(
        left.isValidAt(location) ? 1 : 0,
      );
      return byArea != 0
          ? byArea
          : left.accuracyMeters.compareTo(right.accuracyMeters);
    });
    return datums;
  }

  static GeodeticDatum? byId(String? id) {
    if (id == null) return null;
    for (final datums in _registry.values) {
      for (final datum in datums) {
        if (datum.id == id) return datum;
      }
    }
    return null;
  }
}
