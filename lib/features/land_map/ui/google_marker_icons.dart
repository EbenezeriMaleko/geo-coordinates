import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

enum GoogleMarkerIconKind { point, label, arrow }

/// Renders marker artwork in logical pixels and caches it for the map session.
class GoogleMarkerIcons {
  final Map<String, google.BitmapDescriptor> _cache = {};
  final Set<String> _pending = {};

  google.BitmapDescriptor get({
    required GoogleMarkerIconKind kind,
    required String text,
    required Color color,
    required VoidCallback onReady,
  }) {
    final key = '${kind.name}:${color.toARGB32()}:$text';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_pending.add(key)) {
      _render(kind, text, color).then(
        (icon) {
          _pending.remove(key);
          _cache[key] = icon;
          onReady();
        },
        onError: (Object error, StackTrace stack) {
          _pending.remove(key);
        },
      );
    }
    return google.BitmapDescriptor.defaultMarker;
  }

  Future<google.BitmapDescriptor> _render(
    GoogleMarkerIconKind kind,
    String text,
    Color color,
  ) async {
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: kind == GoogleMarkerIconKind.label ? color : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 140);
    final width = kind == GoogleMarkerIconKind.label
        ? (label.width + 20).ceil().clamp(60, 160).toDouble()
        : 36.0;
    const height = 36.0;
    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    final bounds = Rect.fromLTWH(1, 1, width - 2, height - 2);
    if (kind == GoogleMarkerIconKind.label) {
      final shape = RRect.fromRectAndRadius(bounds, const Radius.circular(18));
      canvas.drawRRect(shape, Paint()..color = Colors.white);
      canvas.drawRRect(
        shape,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      canvas.drawCircle(bounds.center, 17, Paint()..color = Colors.white);
      canvas.drawCircle(bounds.center, 15, Paint()..color = color);
    }
    if (kind == GoogleMarkerIconKind.arrow) {
      final path = Path()
        ..moveTo(width / 2, 6)
        ..lineTo(width / 2 - 7, 26)
        ..lineTo(width / 2, 21)
        ..lineTo(width / 2 + 7, 26)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white);
    } else {
      label.paint(
        canvas,
        Offset((width - label.width) / 2, (height - label.height) / 2),
      );
    }
    label.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * scale).round(),
      (height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('Could not render map marker');
    return google.BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: width,
      height: height,
    );
  }
}
