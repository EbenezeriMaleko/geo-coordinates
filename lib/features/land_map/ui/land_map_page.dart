import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:uuid/uuid.dart';

import '../models/coordinate_format.dart';
import '../state/land_map_notifier.dart';
import '../state/land_map_state.dart';
import '../state/settings_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum MapType { normal, satellite, terrain, hybrid }

enum _MapTool { none, marker, distance }

class LandMapPage extends ConsumerStatefulWidget {
  final double bottomInset;

  const LandMapPage({super.key, this.bottomInset = 0});

  @override
  ConsumerState<LandMapPage> createState() => _LandMapPageState();
}

class _LandMapPageState extends ConsumerState<LandMapPage>
    with TickerProviderStateMixin {
  static const double _minZoom = 3;
  static const double _maxZoom = 20;
  static const double _defaultMapZoom = 16;

  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();

  MapType _currentMapType = MapType.normal;
  _MapTool _activeTool = _MapTool.none;
  final Distance _distanceCalculator = const Distance();
  List<LatLng> _distancePoints = const [];
  bool _isFabExpanded = false;
  bool _isLocating = false;
  bool _isMarkerSaving = false;
  bool _isAutoFieldCapture = false;
  bool _isFullscreen = false;
  double _currentZoom = _defaultMapZoom;
  String? _locationError;
  List<_PlacedMarker> _savedMarkers = const [];
  StreamSubscription<Position>? _fieldTrackingSubscription;
  bool _showFieldLayer = true;
  bool _showDistanceLayer = true;
  bool _showMarkerLayer = true;
  ProviderSubscription<LandMapState>? _landMapSubscription;

  @override
  void initState() {
    super.initState();
    _landMapSubscription = ref.listenManual(landMapProvider, (previous, next) {
      final prevLen = previous?.points.length ?? 0;
      final nextLen = next.points.length;
      if (nextLen == 0) return;

      final pointsChanged = previous == null || previous.points != next.points;
      if (!pointsChanged) return;

      if (prevLen != nextLen || prevLen == 0) {
        _focusOnPoints(next.points);
      }
    });

    Future.microtask(() async {
      await _loadSavedMarkers();
      await _initLocationAndCenter();
    });
  }

  @override
  void dispose() {
    _landMapSubscription?.close();
    _fieldTrackingSubscription?.cancel();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _nameController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _initLocationAndCenter() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    final err = await ref.read(landMapProvider.notifier).initLocation();
    if (!mounted) return;

    final st = ref.read(landMapProvider);
    if (st.current != null) {
      _mapController.move(st.current!, 17);
    }

    setState(() {
      _isLocating = false;
      _locationError = err;
    });
  }

  Future<void> _recenterToCurrentLocation() async {
    if (_isLocating) return;

    final beforeRefresh = ref.read(landMapProvider).current;
    if (beforeRefresh != null) {
      _mapController.move(beforeRefresh, _clampZoom(max(_currentZoom, 17)));
    }

    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    final err = await ref.read(landMapProvider.notifier).refreshLocation();
    if (!mounted) return;

    final now = ref.read(landMapProvider).current;
    if (now != null) {
      _mapController.move(now, _clampZoom(max(_currentZoom, 17)));
    }

    setState(() {
      _isLocating = false;
      _locationError = err;
    });

    if (err != null && beforeRefresh == null) {
      _snack(err);
    }
  }

  Future<void> _addCurrentPointToDistance() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    final err = await ref.read(landMapProvider.notifier).refreshLocation();
    if (!mounted) return;

    final now = ref.read(landMapProvider).current;
    if (now != null) {
      _addDistancePoint(now);
    }

    setState(() {
      _isLocating = false;
      _locationError = err;
    });

    if (err != null) _snack(err);
  }

  Future<void> _handleLocationIssueAction() async {
    if ((_locationError ?? '').toLowerCase().contains('services')) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }

  Future<void> _loadSavedMarkers() async {
    final box = Hive.box('landbox');
    final markerItems =
        box.values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['entityType'] == 'marker')
            .map(
              (e) => _PlacedMarker(
                id: e['id'].toString(),
                point: LatLng(
                  (e['lat'] as num).toDouble(),
                  (e['lng'] as num).toDouble(),
                ),
                createdAt: DateTime.tryParse(e['createdAt']?.toString() ?? ''),
              ),
            )
            .toList()
          ..sort((a, b) {
            final aTs = a.createdAt?.millisecondsSinceEpoch ?? 0;
            final bTs = b.createdAt?.millisecondsSinceEpoch ?? 0;
            return bTs.compareTo(aTs);
          });

    if (!mounted) return;
    setState(() {
      _savedMarkers = markerItems;
    });
  }

  Future<void> _addMarkerAt(LatLng point) async {
    if (_isMarkerSaving) return;
    setState(() => _isMarkerSaving = true);
    try {
      final box = Hive.box('landbox');
      final id = const Uuid().v4();
      final payload = {
        'id': id,
        'entityType': 'marker',
        'name': 'Marker ${DateTime.now().toIso8601String()}',
        'lat': point.latitude,
        'lng': point.longitude,
        'createdAt': DateTime.now().toIso8601String(),
      };
      await box.put(id, payload);
      if (!mounted) return;
      await _loadSavedMarkers();
      _snack('Marker added');
    } finally {
      if (mounted) {
        setState(() => _isMarkerSaving = false);
      }
    }
  }

  Future<void> _deleteMarker(String id) async {
    final box = Hive.box('landbox');
    await box.delete(id);
    if (!mounted) return;
    await _loadSavedMarkers();
    _snack('Marker deleted');
  }

  void _addDistancePoint(LatLng point) {
    setState(() {
      _distancePoints = [..._distancePoints, point];
    });
  }

  void _undoDistancePoint() {
    if (_distancePoints.isEmpty) return;
    setState(() {
      _distancePoints = [..._distancePoints]..removeLast();
    });
  }

  void _clearDistancePoints() {
    setState(() {
      _distancePoints = const [];
    });
  }

  double _totalDistanceMeters() {
    if (_distancePoints.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < _distancePoints.length - 1; i++) {
      total += _distanceCalculator.as(
        LengthUnit.Meter,
        _distancePoints[i],
        _distancePoints[i + 1],
      );
    }
    return total;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(1)} m';
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (!mounted) return;
    setState(() => _isFullscreen = !_isFullscreen);
  }

  double _clampZoom(double zoom) => zoom.clamp(_minZoom, _maxZoom);

  void _focusOnPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, _clampZoom(18));
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final diagonal = Geolocator.distanceBetween(minLat, minLng, maxLat, maxLng);

    double zoom;
    if (diagonal < 40) {
      zoom = 18;
    } else if (diagonal < 100) {
      zoom = 17;
    } else if (diagonal < 250) {
      zoom = 16;
    } else if (diagonal < 600) {
      zoom = 15;
    } else if (diagonal < 1200) {
      zoom = 14;
    } else {
      zoom = 13;
    }

    _mapController.move(center, _clampZoom(zoom));
  }

  double _calculatePerimeterMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    double perimeter = 0;
    for (int i = 0; i < points.length - 1; i++) {
      perimeter += _distanceCalculator.as(
        LengthUnit.Meter,
        points[i],
        points[i + 1],
      );
    }
    if (points.length >= 3) {
      perimeter += _distanceCalculator.as(
        LengthUnit.Meter,
        points.last,
        points.first,
      );
    }
    return perimeter;
  }

  double _calculateAreaSqm(List<LatLng> points) {
    if (points.length < 3) return 0;

    const radius = 6378137.0;
    final lat0 =
        points.map((e) => e.latitude).reduce((a, b) => a + b) / points.length;
    final lon0 =
        points.map((e) => e.longitude).reduce((a, b) => a + b) / points.length;

    final lat0Rad = lat0 * pi / 180.0;
    final lon0Rad = lon0 * pi / 180.0;

    final projected = points.map((p) {
      final latRad = p.latitude * pi / 180.0;
      final lonRad = p.longitude * pi / 180.0;
      final x = radius * (lonRad - lon0Rad) * cos(lat0Rad);
      final y = radius * (latRad - lat0Rad);
      return Offset(x, y);
    }).toList();

    double sum = 0;
    for (int i = 0; i < projected.length; i++) {
      final j = (i + 1) % projected.length;
      sum += projected[i].dx * projected[j].dy;
      sum -= projected[j].dx * projected[i].dy;
    }
    return sum.abs() / 2.0;
  }

  String _formatArea(double sqm) {
    if (sqm >= 10000) {
      return '${(sqm / 10000).toStringAsFixed(2)} ha';
    }
    return '${sqm.toStringAsFixed(1)} sqm';
  }

  Future<void> _startAutoFieldCapture() async {
    if (_fieldTrackingSubscription != null) return;
    final notifier = ref.read(landMapProvider.notifier);

    setState(() => _isAutoFieldCapture = true);
    _fieldTrackingSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1,
          ),
        ).listen(
          (position) {
            final result = notifier.addPointFromLivePosition(
              position,
              maxAccuracy: 20,
              minDistanceMeters: 2.0,
            );
            if (result == null) return;
          },
          onError: (_) {
            if (mounted) {
              _snack('Auto capture stopped');
              _stopAutoFieldCapture();
            }
          },
        );
  }

  Future<void> _stopAutoFieldCapture() async {
    await _fieldTrackingSubscription?.cancel();
    _fieldTrackingSubscription = null;
    if (mounted) {
      setState(() => _isAutoFieldCapture = false);
    }
  }

  void _showMarkerActions(_PlacedMarker marker) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Center here'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _mapController.move(marker.point, 17);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete marker'),
                textColor: Colors.red,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _deleteMarker(marker.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(landMapProvider);
    final notifier = ref.read(landMapProvider.notifier);
    final coordinateFormat = ref.watch(coordinateFormatProvider);
    final bottomFabOffset = widget.bottomInset + 16;
    final bottomZoomOffset = widget.bottomInset + 140;
    final toolBannerTop = _locationError == null ? 92.0 : 202.0;
    final totalDistanceMeters = _totalDistanceMeters();

    final center = st.current ?? const LatLng(-6.7924, 39.2083);

    final markers = <Marker>[
      if (_showFieldLayer)
        for (int i = 0; i < st.points.length; i++)
          Marker(
            width: 40,
            height: 40,
            point: st.points[i],
            child: _PointMarker(index: i + 1),
          ),

      if (st.current != null)
        Marker(
          width: 36,
          height: 36,
          point: st.current!,
          child: const _CurrentMarker(),
        ),
      if (_showMarkerLayer)
        for (final marker in _savedMarkers)
          Marker(
            width: 44,
            height: 44,
            point: marker.point,
            child: GestureDetector(
              onTap: () => _showMarkerActions(marker),
              child: const _SavedMarkerPin(),
            ),
          ),
      if (_showDistanceLayer)
        for (int i = 0; i < _distancePoints.length; i++)
          Marker(
            width: 34,
            height: 34,
            point: _distancePoints[i],
            child: _DistancePointMarker(index: i + 1),
          ),
    ];

    final polygons = <Polygon>[
      if (_showFieldLayer && st.points.length >= 3)
        Polygon(
          points: st.points,
          borderStrokeWidth: 3,
          color: const Color(0xFF001F3F).withValues(alpha: 0.3),
          borderColor: const Color(0xFF001F3F),
        ),
    ];

    final polylines = <Polyline>[
      if (_showFieldLayer && st.points.length >= 2)
        Polyline(
          points: st.points,
          strokeWidth: 3,
          color: const Color(0xFF001F3F),
        ),
      if (_showDistanceLayer && _distancePoints.length >= 2)
        Polyline(
          points: _distancePoints,
          strokeWidth: 4,
          color: Colors.orange.shade700,
        ),
    ];

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _defaultMapZoom,
            onPositionChanged: (position, _) {
              final zoom = position.zoom;
              if (zoom != _currentZoom && mounted) {
                setState(() => _currentZoom = zoom);
              }
            },
            onLongPress: (_, latLng) async {
              if (_activeTool == _MapTool.marker) {
                await _addMarkerAt(latLng);
                return;
              }
              if (_activeTool == _MapTool.distance) {
                _addDistancePoint(latLng);
              }
            },
          ),
          children: [
            ..._buildMapTileLayers(),
            if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),

        // GPS Info Card
        if (!_isFullscreen)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF001F3F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.gps_fixed,
                      color: Color(0xFF001F3F),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          st.current == null
                              ? (_isLocating
                                    ? 'Locating...'
                                    : (_locationError != null
                                          ? 'Location unavailable'
                                          : 'Waiting for GPS...'))
                              : CoordinateFormatter.format(
                                  st.current!.latitude,
                                  st.current!.longitude,
                                  coordinateFormat,
                                ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        if (st.current != null)
                          Text(
                            'Accuracy: ${(st.accuracyMeters ?? 0).toStringAsFixed(1)}m',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (st.points.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF001F3F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${st.points.length} pts',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        if (_locationError != null && !_isFullscreen)
          Positioned(
            top: 92,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _locationError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _isLocating
                                  ? null
                                  : _handleLocationIssueAction,
                              child: const Text('Open settings'),
                            ),
                            ElevatedButton(
                              onPressed: _isLocating
                                  ? null
                                  : _initLocationAndCenter,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (st.activeFieldId != null && !_isFullscreen)
          Positioned(
            top: _locationError == null ? 92 : 202,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_location_alt,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Editing: ${st.activeFieldName ?? 'Saved field'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      notifier.exitEditingMode();
                      _snack('Exited edit mode');
                    },
                    child: const Text(
                      'Exit',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_activeTool == _MapTool.marker && !_isFullscreen)
          Positioned(
            top: st.activeFieldId != null ? toolBannerTop + 52 : toolBannerTop,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF001F3F).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Marker mode: long-press map to place marker',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _activeTool = _MapTool.none),
                    child: const Text(
                      'Exit',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_activeTool == _MapTool.distance && !_isFullscreen)
          Positioned(
            top: st.activeFieldId != null ? toolBannerTop + 52 : toolBannerTop,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade800.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.straighten,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Distance mode: ${_formatDistance(totalDistanceMeters)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _isLocating
                            ? null
                            : _addCurrentPointToDistance,
                        child: const Text(
                          'Mark GPS',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: _distancePoints.isEmpty
                            ? null
                            : _undoDistancePoint,
                        child: const Text(
                          'Undo',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: _distancePoints.isEmpty
                            ? null
                            : _clearDistancePoints,
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            setState(() => _activeTool = _MapTool.none),
                        child: const Text(
                          'Exit',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Compass (Top Right)
        Positioned(
          right: 16,
          top: _isFullscreen ? 20 : 90,
          child: const CompassWidget(),
        ),

        // Map Controls (Right side)
        Positioned(
          right: 16,
          top: _isFullscreen ? 90 : 160,
          child: Column(
            children: [
              _MapControlButton(
                icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                isActive: _isFullscreen,
                onPressed: _toggleFullscreen,
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.my_location_rounded,
                isLoading: _isLocating,
                enabled: !_isLocating,
                onPressed: _recenterToCurrentLocation,
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.layers,
                onPressed: () {
                  _showMapTypeSelector();
                },
              ),
            ],
          ),
        ),

        // Zoom Controls
        Positioned(
          left: 16,
          bottom: bottomZoomOffset,
          child: Column(
            children: [
              _MapControlButton(
                icon: Icons.add,
                enabled: !_isLocating && _currentZoom < _maxZoom,
                onPressed: () {
                  final nextZoom = _clampZoom(_mapController.camera.zoom + 1);
                  _mapController.move(_mapController.camera.center, nextZoom);
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.remove,
                enabled: !_isLocating && _currentZoom > _minZoom,
                onPressed: () {
                  final nextZoom = _clampZoom(_mapController.camera.zoom - 1);
                  _mapController.move(_mapController.camera.center, nextZoom);
                },
              ),
            ],
          ),
        ),

        // Floating Action Button
        Positioned(
          right: 16,
          bottom: bottomFabOffset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isFabExpanded) ...[
                _FabOption(
                  label: 'Field',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/golf-hole.svg',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isFabExpanded = false;
                      _activeTool = _MapTool.none;
                    });
                    _showFieldDialog();
                  },
                ),
                const SizedBox(height: 12),
                _FabOption(
                  label: 'Distance',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/map-location-track.svg',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isFabExpanded = false;
                      _showDistanceLayer = true;
                      _activeTool = _activeTool == _MapTool.distance
                          ? _MapTool.none
                          : _MapTool.distance;
                    });
                    _snack(
                      _activeTool == _MapTool.distance
                          ? 'Distance mode enabled'
                          : 'Distance mode disabled',
                    );
                  },
                ),
                const SizedBox(height: 12),
                _FabOption(
                  label: 'Marker',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/marker.svg',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isFabExpanded = false;
                      _showMarkerLayer = true;
                      _activeTool = _activeTool == _MapTool.marker
                          ? _MapTool.none
                          : _MapTool.marker;
                    });
                    _snack(
                      _activeTool == _MapTool.marker
                          ? 'Marker mode enabled'
                          : 'Marker mode disabled',
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              FloatingActionButton(
                onPressed: () {
                  setState(() {
                    _isFabExpanded = !_isFabExpanded;
                  });
                },
                backgroundColor: Colors.white,
                child: AnimatedRotation(
                  turns: _isFabExpanded ? 0.125 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(_isFabExpanded ? Icons.close : Icons.add),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMapTileLayers() {
    switch (_currentMapType) {
      case MapType.normal:
        return [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.landmapper',
          ),
        ];
      case MapType.satellite:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.landmapper',
          ),
        ];
      case MapType.terrain:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.landmapper',
          ),
        ];
      case MapType.hybrid:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.landmapper',
          ),
          TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.landmapper',
            subdomains: ['a', 'b', 'c', 'd'],
          ),
        ];
    }
  }

  void _showMapTypeSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Map Type',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MapTypeOption(
                    label: 'Normal',
                    icon: Icons.map,
                    isSelected: _currentMapType == MapType.normal,
                    onTap: () {
                      setState(() => _currentMapType = MapType.normal);
                      Navigator.pop(context);
                    },
                  ),
                  _MapTypeOption(
                    label: 'Satellite',
                    icon: Icons.satellite_alt,
                    isSelected: _currentMapType == MapType.satellite,
                    onTap: () {
                      setState(() => _currentMapType = MapType.satellite);
                      Navigator.pop(context);
                    },
                  ),
                  _MapTypeOption(
                    label: 'Terrain',
                    icon: Icons.terrain,
                    isSelected: _currentMapType == MapType.terrain,
                    onTap: () {
                      setState(() => _currentMapType = MapType.terrain);
                      Navigator.pop(context);
                    },
                  ),
                  _MapTypeOption(
                    label: 'Hybrid',
                    icon: Icons.layers,
                    isSelected: _currentMapType == MapType.hybrid,
                    onTap: () {
                      setState(() => _currentMapType = MapType.hybrid);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Layers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LayerOption(
                    label: 'Field',
                    icon: SvgPicture.asset(
                      'lib/assets/icons/golf-hole.svg',
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    color: Colors.blue,
                    isSelected: _showFieldLayer,
                    onTap: () {
                      setState(() {
                        _showFieldLayer = !_showFieldLayer;
                      });
                      modalSetState(() {});
                    },
                  ),
                  _LayerOption(
                    label: 'Distance',
                    icon: SvgPicture.asset(
                      'lib/assets/icons/map-location-track.svg',
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    color: Colors.orange,
                    isSelected: _showDistanceLayer,
                    onTap: () {
                      setState(() {
                        _showDistanceLayer = !_showDistanceLayer;
                        if (!_showDistanceLayer &&
                            _activeTool == _MapTool.distance) {
                          _activeTool = _MapTool.none;
                        }
                      });
                      modalSetState(() {});
                    },
                  ),
                  _LayerOption(
                    label: 'Marker',
                    icon: SvgPicture.asset(
                      'lib/assets/icons/marker.svg',
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    color: Colors.red,
                    isSelected: _showMarkerLayer,
                    onTap: () {
                      setState(() {
                        _showMarkerLayer = !_showMarkerLayer;
                        if (!_showMarkerLayer &&
                            _activeTool == _MapTool.marker) {
                          _activeTool = _MapTool.none;
                        }
                      });
                      modalSetState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showFieldDialog() {
    final current = ref.read(landMapProvider);
    if (_nameController.text.trim().isEmpty &&
        current.activeFieldName != null) {
      _nameController.text = current.activeFieldName!;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, child) {
          final mapState = ref.watch(landMapProvider);
          final pointsCount = mapState.points.length;
          final perimeter = _calculatePerimeterMeters(mapState.points);
          final area = _calculateAreaSqm(mapState.points);
          final notifier = ref.read(landMapProvider.notifier);

          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (_, result) async {
              await _stopAutoFieldCapture();
            },
            child: AlertDialog(
              title: const Text('Create Field'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Field Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Auto-capture while moving',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Walk field boundary. Adds point every ~2m when GPS is accurate.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _isAutoFieldCapture,
                      onChanged: mapState.isSaving
                          ? null
                          : (value) async {
                              if (value) {
                                await _startAutoFieldCapture();
                              } else {
                                await _stopAutoFieldCapture();
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: mapState.isSaving
                                ? null
                                : () async {
                                    final err = await notifier
                                        .addPointFromCurrent();
                                    if (err != null && dialogContext.mounted) {
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        SnackBar(content: Text(err)),
                                      );
                                    } else if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Point added'),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.my_location),
                            label: const Text('Mark Current GPS'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pointsCount == 0 || mapState.isSaving
                                ? null
                                : notifier.undoLastPoint,
                            icon: const Icon(Icons.undo),
                            label: const Text('Undo Last'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pointsCount == 0 || mapState.isSaving
                                ? null
                                : notifier.clearPoints,
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Clear All'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$pointsCount points captured',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Perimeter: ${_formatDistance(perimeter)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Area: ${_formatArea(area)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: mapState.isSaving
                      ? null
                      : () async {
                          await _stopAutoFieldCapture();
                          if (mapState.activeFieldId == null) {
                            notifier.clearPoints();
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: mapState.isSaving
                      ? null
                      : () async {
                          final err = await notifier.saveOffline(
                            name: _nameController.text.trim(),
                          );
                          if (dialogContext.mounted) {
                            if (err != null) {
                              ScaffoldMessenger.of(
                                dialogContext,
                              ).showSnackBar(SnackBar(content: Text(err)));
                            } else {
                              await _stopAutoFieldCapture();
                              if (!dialogContext.mounted) return;
                              _nameController.clear();
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    mapState.activeFieldId != null
                                        ? 'Field updated successfully'
                                        : 'Field saved successfully',
                                  ),
                                ),
                              );
                              Navigator.pop(dialogContext);
                            }
                          }
                        },
                  child: mapState.isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          mapState.activeFieldId != null
                              ? 'Update Field'
                              : 'Save Field',
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Helper Widgets
class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool isLoading;
  final bool isActive;

  const _MapControlButton({
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.isLoading = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF001F3F).withValues(alpha: 0.12)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        onPressed: enabled ? onPressed : null,
        color: enabled ? const Color(0xFF001F3F) : Colors.grey,
        iconSize: 22,
      ),
    );
  }
}

class _FabOption extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onPressed;

  const _FabOption({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF001F3F),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton(
          mini: true,
          onPressed: onPressed,
          backgroundColor: Colors.white,
          child: icon,
        ),
      ],
    );
  }
}

class _MapTypeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapTypeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF001F3F)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF001F3F)
                    : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey,
              size: 28,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? const Color(0xFF001F3F) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerOption extends StatelessWidget {
  final String label;
  final Widget icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _LayerOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: Center(
              child: Opacity(opacity: isSelected ? 1 : 0.45, child: icon),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? color : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointMarker extends StatelessWidget {
  final int index;
  const _PointMarker({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF001F3F).withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CurrentMarker extends StatelessWidget {
  const _CurrentMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 20),
    );
  }
}

class _SavedMarkerPin extends StatelessWidget {
  const _SavedMarkerPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.deepOrange.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.push_pin, color: Colors.white, size: 20),
    );
  }
}

class _DistancePointMarker extends StatelessWidget {
  final int index;
  const _DistancePointMarker({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.orange.shade700,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _PlacedMarker {
  final String id;
  final LatLng point;
  final DateTime? createdAt;

  const _PlacedMarker({
    required this.id,
    required this.point,
    required this.createdAt,
  });
}

class CompassWidget extends StatefulWidget {
  const CompassWidget({super.key});

  @override
  State<CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<CompassWidget> {
  double _heading = 0.0;
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    _initCompass();
  }

  void _initCompass() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        if (!mounted) return;
        setState(() {
          _heading = event.heading!;
        });
      }
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Transform.rotate(
        angle: -_heading * (pi / 180), // Convert degrees to radians and rotate
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Compass circle background
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF001F3F).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            // North pointer (red)
            CustomPaint(size: const Size(40, 40), painter: _CompassPainter()),
            // N letter
            const Positioned(
              top: 6,
              child: Text(
                'N',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE53E3E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    // North pointer (red)
    paint.color = const Color(0xFFE53E3E);
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - 15)
      ..lineTo(center.dx - 4, center.dy)
      ..lineTo(center.dx, center.dy - 3)
      ..close();
    canvas.drawPath(northPath, paint);

    // South pointer (white with dark border)
    paint.color = Colors.white;
    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + 15)
      ..lineTo(center.dx + 4, center.dy)
      ..lineTo(center.dx, center.dy + 3)
      ..close();
    canvas.drawPath(southPath, paint);

    // Border for south pointer
    paint
      ..color = const Color(0xFF001F3F).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(southPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
