import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';

import 'google_map_surface.dart';

/// Dispatches the map page's camera commands to the active map surface.
class MapCameraController {
  MapCameraController(this.flutterMap);

  final MapController flutterMap;
  google.GoogleMapController? _googleMap;
  google.CameraPosition? _googlePosition;
  bool _usingGoogle = false;
  bool _pendingMove = false;

  void beginGoogle(google.CameraPosition position) {
    _usingGoogle = true;
    _googleMap = null;
    _googlePosition = position;
    _pendingMove = false;
  }

  void useGoogle(
    google.GoogleMapController controller,
    google.CameraPosition position,
  ) {
    if (!_usingGoogle) return;
    _googleMap = controller;
    final target = _googlePosition ?? position;
    if (_pendingMove) {
      _pendingMove = false;
      _moveGoogle(target);
    }
  }

  void updateGooglePosition(google.CameraPosition position) {
    if (_usingGoogle) _googlePosition = position;
  }

  void useFlutterMap() {
    _googleMap = null;
    _googlePosition = null;
    _usingGoogle = false;
    _pendingMove = false;
  }

  void move(LatLng point, double zoom) {
    if (!_usingGoogle) {
      flutterMap.move(point, zoom);
      return;
    }
    final current = _googlePosition;
    final position = google.CameraPosition(
      target: toGoogleLatLng(point),
      zoom: zoom,
      bearing: current?.bearing ?? 0,
    );
    _moveGoogle(position);
  }

  void rotate(double rotation) {
    final current = _googlePosition;
    if (!_usingGoogle) {
      flutterMap.rotate(rotation);
      return;
    }
    if (current == null) return;
    _moveGoogle(
      google.CameraPosition(
        target: current.target,
        zoom: current.zoom,
        bearing: googleBearingForRotation(rotation),
      ),
    );
  }

  void moveAndRotate(LatLng point, double zoom, double rotation) {
    if (!_usingGoogle) {
      flutterMap.moveAndRotate(point, zoom, rotation);
      return;
    }
    _moveGoogle(
      google.CameraPosition(
        target: toGoogleLatLng(point),
        zoom: zoom,
        bearing: googleBearingForRotation(rotation),
      ),
    );
  }

  void _moveGoogle(google.CameraPosition position) {
    _googlePosition = position;
    final controller = _googleMap;
    if (controller == null) {
      _pendingMove = true;
      return;
    }
    unawaited(
      controller.moveCamera(google.CameraUpdate.newCameraPosition(position)),
    );
  }
}

/// flutter_map rotates the map, while Google uses a clockwise camera bearing.
double googleBearingForRotation(double rotation) =>
    (-rotation % 360 + 360) % 360;
