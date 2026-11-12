import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart' as geo;

/// Native map surface for the future Google Maps provider.
///
/// Survey overlays must be rendered by this map, not by a separately moving
/// transparent map layered over it.
class GoogleMapSurface extends StatelessWidget {
  const GoogleMapSurface({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    required this.mapType,
    required this.onMapCreated,
    this.markers = const {},
    this.polylines = const {},
    this.polygons = const {},
    this.onLongPress,
    this.onCameraMove,
    this.onCameraMoveStarted,
    this.onCameraIdle,
  });

  final geo.LatLng initialCenter;
  final double initialZoom;
  final google.MapType mapType;
  final ValueChanged<google.GoogleMapController> onMapCreated;
  final Set<google.Marker> markers;
  final Set<google.Polyline> polylines;
  final Set<google.Polygon> polygons;
  final ValueChanged<geo.LatLng>? onLongPress;
  final ValueChanged<google.CameraPosition>? onCameraMove;
  final VoidCallback? onCameraMoveStarted;
  final VoidCallback? onCameraIdle;

  @override
  Widget build(BuildContext context) => google.GoogleMap(
    initialCameraPosition: google.CameraPosition(
      target: toGoogleLatLng(initialCenter),
      zoom: initialZoom,
    ),
    mapType: mapType,
    onMapCreated: onMapCreated,
    markers: markers,
    polylines: polylines,
    polygons: polygons,
    onLongPress: onLongPress == null
        ? null
        : (point) => onLongPress!(fromGoogleLatLng(point)),
    onCameraMove: onCameraMove,
    onCameraMoveStarted: onCameraMoveStarted,
    onCameraIdle: onCameraIdle,
    compassEnabled: true,
    mapToolbarEnabled: false,
    myLocationButtonEnabled: false,
    zoomControlsEnabled: false,
    tiltGesturesEnabled: false,
  );
}

google.LatLng toGoogleLatLng(geo.LatLng point) =>
    google.LatLng(point.latitude, point.longitude);

geo.LatLng fromGoogleLatLng(google.LatLng point) =>
    geo.LatLng(point.latitude, point.longitude);
