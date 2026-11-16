import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

class PolygonEdgeLabel {
  const PolygonEdgeLabel(this.edge, this.point);
  final int edge;
  final LatLng point;
}

class PolygonLabelLayout {
  const PolygonLabelLayout({required this.area, required this.edges});
  final LatLng? area;
  final List<PolygonEdgeLabel> edges;
}

/// Places labels in logical map pixels, reserving space for vertices and labels.
/// Area has priority; distances sit outside the boundary and are omitted if
/// crowded. The projection supports either map provider and rotated maps.
PolygonLabelLayout layoutPolygonLabels({
  required List<LatLng> points,
  required double zoom,
  required Size areaSize,
  required List<Size> edgeSizes,
  double rotation = 0,
}) {
  if (points.length < 3) return const PolygonLabelLayout(area: null, edges: []);
  final scale = 256 * math.pow(2, zoom);
  final origin = points.first.longitude;
  final angle = rotation * math.pi / 180;
  Offset rotate(Offset p, double a) => Offset(
    p.dx * math.cos(a) - p.dy * math.sin(a),
    p.dx * math.sin(a) + p.dy * math.cos(a),
  );
  Offset project(LatLng p) {
    final longitude = origin + ((p.longitude - origin + 540) % 360 - 180);
    final lat = p.latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    return rotate(
      Offset(
        (longitude + 180) / 360 * scale,
        (1 - math.log(math.tan(math.pi / 4 + lat / 2)) / math.pi) / 2 * scale,
      ),
      angle,
    );
  }

  LatLng unproject(Offset p) {
    final world = rotate(p, -angle);
    final n = math.pi * (1 - 2 * world.dy / scale);
    return LatLng(
      math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi,
      (world.dx / scale * 360) % 360 - 180,
    );
  }

  final polygon = points.map(project).toList();
  bool inside(Offset p) {
    var result = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        result = !result;
      }
    }
    return result;
  }

  double segmentDistance(Offset p, Offset a, Offset b) {
    final delta = b - a;
    final length = delta.distanceSquared;
    final t = length == 0
        ? 0.0
        : (((p - a).dx * delta.dx + (p - a).dy * delta.dy) / length).clamp(
            0.0,
            1.0,
          );
    return (p - (a + delta * t)).distance;
  }

  double clearance(Offset p) {
    if (!inside(p)) return -1;
    var distance = double.infinity;
    for (var i = 0; i < polygon.length; i++) {
      distance = math.min(
        distance,
        segmentDistance(p, polygon[i], polygon[(i + 1) % polygon.length]),
      );
    }
    return distance;
  }

  var bounds = Rect.fromPoints(polygon.first, polygon.first);
  for (final point in polygon) {
    bounds = bounds.expandToInclude(Rect.fromCircle(center: point, radius: 0));
  }
  // Refine a grid around the point with the most interior clearance. Unlike an
  // average of vertices, this also works for concave parcels.
  Offset? best;
  var bestClearance = -1.0;
  var search = bounds;
  for (var pass = 0; pass < 4; pass++) {
    for (var x = 0; x <= 20; x++) {
      for (var y = 0; y <= 20; y++) {
        final p = Offset(
          search.left + search.width * x / 20,
          search.top + search.height * y / 20,
        );
        final score = clearance(p);
        if (score > bestClearance) {
          best = p;
          bestClearance = score;
        }
      }
    }
    if (best == null) break;
    search = Rect.fromCenter(
      center: best,
      width: search.width / 5,
      height: search.height / 5,
    );
  }
  final occupied = polygon
      .map((p) => Rect.fromCircle(center: p, radius: 25))
      .toList();
  final areaRadius =
      math.sqrt(
            areaSize.width * areaSize.width + areaSize.height * areaSize.height,
          ) /
          2 +
      6;
  final area = best != null && bestClearance >= areaRadius ? best : null;
  if (area != null) {
    occupied.add(
      Rect.fromCenter(
        center: area,
        width: areaSize.width,
        height: areaSize.height,
      ).inflate(6),
    );
  }
  final labels = <PolygonEdgeLabel>[];
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    final delta = b - a;
    if (delta.distance < 1) continue;
    final normal = Offset(-delta.dy, delta.dx) / delta.distance;
    final size = edgeSizes[i];
    final offset =
        (normal.dx.abs() * size.width + normal.dy.abs() * size.height) / 2 + 10;
    var placed = false;
    for (final fraction in [0.5, 0.35, 0.65]) {
      for (final sign in [1.0, -1.0]) {
        final p = a + delta * fraction + normal * offset * sign;
        if (inside(p)) continue;
        final rect = Rect.fromCenter(
          center: p,
          width: size.width,
          height: size.height,
        ).inflate(5);
        if (occupied.any(rect.overlaps)) continue;
        // Keep the entire badge off every boundary segment.
        final radius =
            math.sqrt(size.width * size.width + size.height * size.height) / 2;
        var crosses = false;
        for (var j = 0; j < polygon.length; j++) {
          if (j == i) continue;
          if (segmentDistance(
                p,
                polygon[j],
                polygon[(j + 1) % polygon.length],
              ) <
              radius + 4) {
            crosses = true;
            break;
          }
        }
        if (crosses) continue;
        occupied.add(rect);
        labels.add(PolygonEdgeLabel(i, unproject(p)));
        placed = true;
        break;
      }
      if (placed) break;
    }
  }
  return PolygonLabelLayout(
    area: area == null ? null : unproject(area),
    edges: labels,
  );
}
