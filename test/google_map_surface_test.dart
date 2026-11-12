import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as map;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart' as geo;
import 'package:taref_gps/features/land_map/ui/google_map_geometry.dart';
import 'package:taref_gps/features/land_map/ui/map_camera_controller.dart';
import 'package:taref_gps/features/land_map/ui/google_map_surface.dart';

void main() {
  test('converts map rotation to a normalized Google camera bearing', () {
    expect(googleBearingForRotation(0), 0);
    expect(googleBearingForRotation(-90), 90);
    expect(googleBearingForRotation(90), 270);
    expect(googleBearingForRotation(-450), 90);
  });

  test('camera commands are held while the native map is being created', () {
    final controller = MapCameraController(map.MapController());
    controller.beginGoogle(
      const google.CameraPosition(target: google.LatLng(-6.8, 39.2), zoom: 15),
    );
    expect(
      () => controller.move(const geo.LatLng(-6.9, 39.3), 17),
      returnsNormally,
    );
    expect(() => controller.rotate(-90), returnsNormally);
    expect(
      () => controller.moveAndRotate(const geo.LatLng(-6.7, 39.1), 18, -45),
      returnsNormally,
    );
    controller.useFlutterMap();
  });
  test('converts survey coordinates without swapping or rounding them', () {
    const original = geo.LatLng(-6.79235412, 39.20832876);
    final converted = toGoogleLatLng(original);
    expect(converted.latitude, original.latitude);
    expect(converted.longitude, original.longitude);

    final restored = fromGoogleLatLng(converted);
    expect(restored.latitude, original.latitude);
    expect(restored.longitude, original.longitude);
  });

  test('converts survey boundaries, holes and dotted routes', () {
    const a = geo.LatLng(-6.8, 39.2);
    const b = geo.LatLng(-6.9, 39.3);
    const c = geo.LatLng(-7.0, 39.4);
    final polygon = googlePolygons([
      map.Polygon(
        points: [a, b, c],
        holePointsList: [
          [a, b, c],
        ],
        color: Colors.red,
        borderColor: Colors.blue,
        borderStrokeWidth: 3,
      ),
    ]).single;
    expect(polygon.points.map((p) => p.latitude), [-6.8, -6.9, -7.0]);
    expect(polygon.holes.single.length, 3);
    expect(polygon.fillColor, Colors.red);
    expect(polygon.strokeColor, Colors.blue);
    expect(polygon.strokeWidth, 3);

    final route = googlePolylines([
      map.Polyline(
        points: [a, b],
        color: Colors.teal,
        strokeWidth: 3,
        pattern: const map.StrokePattern.dotted(),
      ),
    ]).single;
    expect(route.points.last.longitude, 39.3);
    expect(route.color, Colors.teal);
    expect(route.patterns.length, 2);
  });
}
