import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taref_gps/features/land_map/ui/polygon_label_layout.dart';

void main() {
  const square = [
    LatLng(0, 0),
    LatLng(0, .01),
    LatLng(.01, .01),
    LatLng(.01, 0),
  ];
  PolygonLabelLayout layout(
    List<LatLng> points, {
    double zoom = 16,
    double rotation = 0,
  }) => layoutPolygonLabels(
    points: points,
    zoom: zoom,
    rotation: rotation,
    areaSize: const Size(110, 34),
    edgeSizes: List.filled(points.length, const Size(90, 34)),
  );

  test('area stays inside while distances sit outside a spacious parcel', () {
    final result = layout(square);
    expect(result.area, isNotNull);
    expect(result.area!.latitude, inExclusiveRange(0, .01));
    expect(result.area!.longitude, inExclusiveRange(0, .01));
    expect(result.edges, hasLength(4));
    for (final label in result.edges) {
      final p = label.point;
      expect(
        p.latitude < 0 ||
            p.latitude > .01 ||
            p.longitude < 0 ||
            p.longitude > .01,
        isTrue,
      );
    }
  });

  test('concave parcel places area in its interior, not in the notch', () {
    final result = layout(const [
      LatLng(0, 0),
      LatLng(0, .02),
      LatLng(.005, .02),
      LatLng(.005, .005),
      LatLng(.02, .005),
      LatLng(.02, 0),
    ]);
    expect(result.area, isNotNull);
    final p = result.area!;
    expect(p.latitude > 0 && p.longitude > 0, isTrue);
    expect(p.latitude < .005 || p.longitude < .005, isTrue);
  });

  test(
    'zooming out suppresses crowded labels and zooming in restores them',
    () {
      final far = layout(square, zoom: 8);
      final near = layout(square);
      expect(far.area, isNull);
      expect(far.edges.length, lessThan(near.edges.length));
      expect(near.area, isNotNull);
    },
  );

  test('rotated maps keep the area within the parcel', () {
    for (final rotation in [45.0, 90.0, 180.0]) {
      final result = layout(square, rotation: rotation);
      expect(result.area, isNotNull);
      expect(result.area!.latitude, inExclusiveRange(0, .01));
      expect(result.area!.longitude, inExclusiveRange(0, .01));
      expect(result.edges, hasLength(4));
    }
  });

  test('incomplete and degenerate polygons have no area label', () {
    expect(layout(square.take(2).toList()).area, isNull);
    expect(
      layout(const [LatLng(0, 0), LatLng(0, .01), LatLng(0, .02)]).area,
      isNull,
    );
  });
}
