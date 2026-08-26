import 'package:latlong2/latlong.dart';

import '../services/utm_converter.dart';

class DisplayCoordinate {
  final LatLng canonicalWgs84;
  final LatLng geodeticOnSelectedDatum;
  final UtmCoordinate? utm;

  const DisplayCoordinate({
    required this.canonicalWgs84,
    required this.geodeticOnSelectedDatum,
    required this.utm,
  });
}
