import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import 'google_map_surface.dart';

/// Converts the line and polygon styles currently used by the survey map.
/// IDs are stable as long as the calling map keeps the layer ordering stable.
Set<google.Polyline> googlePolylines(List<flutter_map.Polyline> lines) => {
  for (var i = 0; i < lines.length; i++)
    google.Polyline(
      polylineId: google.PolylineId('line_$i'),
      points: lines[i].points.map(toGoogleLatLng).toList(),
      color: lines[i].color,
      width: lines[i].strokeWidth.round().clamp(1, 100),
      patterns: _pattern(lines[i].pattern, lines[i].strokeWidth),
    ),
};

Set<google.Polygon> googlePolygons(List<flutter_map.Polygon> polygons) => {
  for (var i = 0; i < polygons.length; i++)
    google.Polygon(
      polygonId: google.PolygonId('polygon_$i'),
      points: polygons[i].points.map(toGoogleLatLng).toList(),
      holes:
          polygons[i].holePointsList
              ?.map((hole) => hole.map(toGoogleLatLng).toList())
              .toList() ??
          const [],
      fillColor: polygons[i].color ?? Colors.transparent,
      strokeColor: polygons[i].borderColor,
      strokeWidth: polygons[i].borderStrokeWidth.round().clamp(0, 100),
    ),
};

List<google.PatternItem> _pattern(
  flutter_map.StrokePattern pattern,
  double width,
) {
  if (pattern.spacingFactor case final spacing?) {
    return [
      google.PatternItem.dot,
      google.PatternItem.gap((spacing * width).clamp(1, double.infinity)),
    ];
  }
  if (pattern.segments case final segments?) {
    return [
      for (var i = 0; i < segments.length; i++)
        i.isEven
            ? google.PatternItem.dash(segments[i])
            : google.PatternItem.gap(segments[i]),
    ];
  }
  return const [];
}
