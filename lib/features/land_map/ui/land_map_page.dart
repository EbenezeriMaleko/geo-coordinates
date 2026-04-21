import 'dart:async';
import 'dart:convert';
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
import 'package:hugeicons/hugeicons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_client.dart';
import '../models/coordinate_format.dart';
import '../models/reference_ellipsoid.dart';
import '../services/utm_converter.dart';
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
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const double _minZoom = 3;
  static const double _maxZoom = 20;
  static const double _defaultMapZoom = 16;
  static const String _mapTypePrefKey = 'prefs_land_map_type';

  final MapController _mapController = MapController();
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  MapType _currentMapType = MapType.normal;
  _MapTool _activeTool = _MapTool.none;
  final Distance _distanceCalculator = const Distance();
  List<LatLng> _distancePoints = const [];
  bool _isFabExpanded = false;
  bool _isLocating = false;
  bool _isMarkerSaving = false;
  bool _isAutoFieldCapture = false;
  bool _isFullscreen = false;
  bool _isMapTypeSwitching = false;
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
    _restoreMapTypePreference();
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
    _placeController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
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

  @override
  bool get wantKeepAlive => true;

  void _restoreMapTypePreference() {
    final box = Hive.box('landbox');
    final raw = box.get(_mapTypePrefKey)?.toString();
    if (raw == null) return;

    final savedType = _mapTypeFromRaw(raw);
    if (savedType == null || !mounted) return;
    setState(() => _currentMapType = savedType);
  }

  Future<void> _saveMapTypePreference(MapType type) async {
    final box = Hive.box('landbox');
    await box.put(_mapTypePrefKey, type.name);
  }

  MapType? _mapTypeFromRaw(String raw) {
    for (final type in MapType.values) {
      if (type.name == raw) return type;
    }
    return null;
  }

  void _changeMapType(MapType type, BuildContext sheetContext) {
    if (_currentMapType == type) {
      Navigator.pop(sheetContext);
      return;
    }
    Navigator.pop(sheetContext);
    setState(() {
      _currentMapType = type;
      _isMapTypeSwitching = true;
    });
    _saveMapTypePreference(type);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _isMapTypeSwitching = false);
    });
  }

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

  Future<String?> _submitFieldPayload({
    required String name,
    String? place,
    String? phone,
    String? description,
    required List<LatLng> points,
  }) async {
    if (points.length < 3) {
      return 'Not enough points to submit.';
    }

    final box = Hive.box('landbox');
    final authToken = _stringOrFallback(box.get('auth_token'), '');
    if (authToken.isEmpty) {
      return 'Sign in is required before cloud sync.';
    }

    final firstName = _stringOrFallback(box.get('auth_first_name'), '');
    final lastName = _stringOrFallback(box.get('auth_last_name'), '');
    final userFullName = [
      firstName,
      lastName,
    ].where((s) => s.isNotEmpty).join(' ').trim();
    final ownerName = userFullName.isNotEmpty
        ? userFullName
        : _stringOrFallback(box.get('auth_email'), 'Unknown');

    final normalizedPhone =
        _optionalTrim(phone) ?? _optionalTrim(box.get('submit_phone')?.toString());
    final normalizedDescription =
        _optionalTrim(description) ??
        (ownerName.isEmpty ? null : 'Captured by $ownerName');

    final payload = <String, dynamic>{
      'name': name,
      'place': _optionalTrim(place),
      'phone': normalizedPhone,
      'description': normalizedDescription,
      'coordinates': points.map(_latLngToServerCoordinate).toList(),
    };
    payload.removeWhere(
      (key, value) => value == null || (value is String && value.trim().isEmpty),
    );

    if (normalizedPhone != null) {
      await box.put('submit_phone', normalizedPhone);
    }

    try {
      final response = await ApiClient.postJson(
        '/lands',
        body: payload,
        bearerToken: authToken,
        tag: 'land_map_manual_submit',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractApiError(
          response.body,
          'Server rejected payload (${response.statusCode}).',
        );
      }
      return null;
    } catch (_) {
      return 'Failed to send payload to server.';
    }
  }

  String _extractApiError(String rawBody, String fallback) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        final topLevel = decoded['message'] as String?;
        final errors = decoded['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final firstValue = errors.values.first;
          if (firstValue is List && firstValue.isNotEmpty) {
            return firstValue.first.toString();
          }
        }
        if (topLevel != null && topLevel.trim().isNotEmpty) {
          return topLevel;
        }
      }
    } catch (_) {}
    return fallback;
  }

  String _stringOrFallback(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String? _optionalTrim(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _prepareFieldFormControllers(LandMapState currentState) {
    final box = Hive.box('landbox');
    final activeId = currentState.activeFieldId;
    if (activeId != null) {
      final raw = box.get(activeId);
      if (raw is Map) {
        final existing = Map<String, dynamic>.from(raw);
        _placeController.text =
            (existing['place']?.toString() ?? existing['name']?.toString() ?? '')
                .trim();
        _phoneController.text = (existing['phone']?.toString() ?? '').trim();
        _descriptionController.text =
            (existing['description']?.toString() ?? '').trim();
        return;
      }
    }

    if (_placeController.text.trim().isEmpty &&
        currentState.activeFieldName != null) {
      _placeController.text = currentState.activeFieldName!.trim();
    }
    if (_phoneController.text.trim().isEmpty) {
      _phoneController.text =
          _optionalTrim(box.get('submit_phone')?.toString()) ?? '';
    }
  }

  TextStyle _sheetLabelStyle() {
    return GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF374151),
    );
  }

  InputDecoration _sheetInputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF001F3F), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Map<String, dynamic> _latLngToServerCoordinate(LatLng point) {
    final zone = _utmZone(point.latitude, point.longitude);

    return {
      'x': point.longitude,
      'y': point.latitude,
      'z': 0,
      'zone': zone.toString(),
      'band': _utmBand(point.latitude),
      'hemisphere': point.latitude >= 0 ? 'N' : 'S',
    };
  }

  int _utmZone(double latitude, double longitude) {
    final lon = ((longitude + 180) % 360 + 360) % 360 - 180;

    if (latitude >= 56 && latitude < 64 && lon >= 3 && lon < 12) {
      return 32;
    }
    if (latitude >= 72 && latitude < 84) {
      if (lon >= 0 && lon < 9) return 31;
      if (lon >= 9 && lon < 21) return 33;
      if (lon >= 21 && lon < 33) return 35;
      if (lon >= 33 && lon < 42) return 37;
    }

    return ((lon + 180) / 6).floor() + 1;
  }

  String _utmBand(double latitude) {
    if (latitude < -80 || latitude > 84) return 'Z';
    const bands = 'CDEFGHJKLMNPQRSTUVWX';
    final index = ((latitude + 80) / 8).floor().clamp(0, bands.length - 1);
    return bands[index];
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
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedPinLocation02,
                ),
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
    super.build(context);
    final st = ref.watch(landMapProvider);
    final notifier = ref.read(landMapProvider.notifier);
    final coordinateFormat = ref.watch(coordinateFormatProvider);
    final referenceEllipsoid = ref.watch(referenceEllipsoidProvider);
    final utmText = st.current == null
        ? null
        : _formatMapUtm(
            st.current!.latitude,
            st.current!.longitude,
            referenceEllipsoid,
          );
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

        if (_isMapTypeSwitching)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.18),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Switching map type...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
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
                            utmText ?? 'UTM unavailable',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        if (st.current != null)
                          Text(
                            '${referenceEllipsoid.displayName} • Accuracy: ${(st.accuracyMeters ?? 0).toStringAsFixed(1)}m',
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
        // Positioned(
        //   right: 16,
        //   top: _isFullscreen ? 20 : 90,
        //   child: const CompassWidget(),
        // ),

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
                heroTag: 'map_main_fab',
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
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.landmapper',
            subdomains: const ['a', 'b', 'c'],
            maxZoom: _maxZoom,
          ),
        ];
      case MapType.satellite:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.landmapper',
            maxZoom: _maxZoom,
          ),
        ];
      case MapType.terrain:
        return [
          TileLayer(
            urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.landmapper',
            subdomains: const ['a', 'b', 'c'],
            maxZoom: 17,
          ),
        ];
      case MapType.hybrid:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.landmapper',
            maxZoom: _maxZoom,
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
                    preview: Image.asset(
                      'lib/assets/mapsImages/Normal.jpg',
                      fit: BoxFit.cover,
                    ),
                    isSelected: _currentMapType == MapType.normal,
                    onTap: () {
                      _changeMapType(MapType.normal, context);
                    },
                  ),
                  _MapTypeOption(
                    label: 'Satellite',
                    preview: Image.asset(
                      'lib/assets/mapsImages/satellite.png',
                      fit: BoxFit.cover,
                    ),
                    isSelected: _currentMapType == MapType.satellite,
                    onTap: () {
                      _changeMapType(MapType.satellite, context);
                    },
                  ),
                  _MapTypeOption(
                    label: 'Terrain',
                    preview: Image.asset(
                      'lib/assets/mapsImages/terrain.jpg',
                      fit: BoxFit.cover,
                    ),
                    isSelected: _currentMapType == MapType.terrain,
                    onTap: () {
                      _changeMapType(MapType.terrain, context);
                    },
                  ),
                  _MapTypeOption(
                    label: 'Hybrid',
                    preview: Image.asset(
                      'lib/assets/mapsImages/satellite.png',
                      fit: BoxFit.cover,
                    ),
                    isSelected: _currentMapType == MapType.hybrid,
                    onTap: () {
                      _changeMapType(MapType.hybrid, context);
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
    _prepareFieldFormControllers(current);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, child) {
          final mapState = ref.watch(landMapProvider);
          final pointsCount = mapState.points.length;
          final perimeter = _calculatePerimeterMeters(mapState.points);
          final area = _calculateAreaSqm(mapState.points);
          final notifier = ref.read(landMapProvider.notifier);
          final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (_, result) async {
              await _stopAutoFieldCapture();
            },
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        mapState.activeFieldId != null
                            ? 'Update Field'
                            : 'Create Field',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Capture boundary points and save your land details.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Place *', style: _sheetLabelStyle()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _placeController,
                        textInputAction: TextInputAction.next,
                        decoration: _sheetInputDecoration(
                          hint: 'Enter place name',
                          icon: Icons.place_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Phone (optional)', style: _sheetLabelStyle()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _sheetInputDecoration(
                          hint: 'e.g. 0712345678',
                          icon: Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Description (optional)', style: _sheetLabelStyle()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descriptionController,
                        minLines: 2,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        decoration: _sheetInputDecoration(
                          hint: 'Add notes about this land',
                          icon: Icons.notes_outlined,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Boundary capture',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mark current GPS or use auto-capture while walking around the field boundary.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
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
                                      final err =
                                          await notifier.addPointFromCurrent();
                                      if (err != null && sheetContext.mounted) {
                                        ScaffoldMessenger.of(
                                          sheetContext,
                                        ).showSnackBar(
                                          SnackBar(content: Text(err)),
                                        );
                                      } else if (sheetContext.mounted) {
                                        ScaffoldMessenger.of(
                                          sheetContext,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Point added'),
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.my_location),
                              label: const Text('Mark Current GPS'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF001F3F),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
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
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: mapState.isSaving
                                  ? null
                                  : () async {
                                      await _stopAutoFieldCapture();
                                      if (mapState.activeFieldId == null) {
                                        notifier.clearPoints();
                                      }
                                      if (sheetContext.mounted) {
                                        Navigator.pop(sheetContext);
                                      }
                                    },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: mapState.isSaving
                                    ? null
                                    : () async {
                                        final pointsSnapshot = List<LatLng>.from(
                                          mapState.points,
                                        );
                                        final enteredPlace =
                                            _placeController.text.trim();
                                        final enteredPhone =
                                            _phoneController.text.trim();
                                        final enteredDescription =
                                            _descriptionController.text.trim();

                                        if (enteredPlace.isEmpty) {
                                          if (!sheetContext.mounted) return;
                                          ScaffoldMessenger.of(
                                            sheetContext,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Place is required.'),
                                            ),
                                          );
                                          return;
                                        }

                                        final effectiveName = enteredPlace;

                                        final err = await notifier.saveOffline(
                                          name: effectiveName,
                                          place: enteredPlace,
                                          phone: enteredPhone,
                                          description: enteredDescription,
                                        );
                                        if (sheetContext.mounted) {
                                          if (err != null) {
                                            ScaffoldMessenger.of(
                                              sheetContext,
                                            ).showSnackBar(
                                              SnackBar(content: Text(err)),
                                            );
                                          } else {
                                            final submitErr =
                                                await _submitFieldPayload(
                                                  name: effectiveName,
                                                  place: enteredPlace,
                                                  phone: enteredPhone,
                                                  description:
                                                      enteredDescription,
                                                  points: pointsSnapshot,
                                                );
                                            await _stopAutoFieldCapture();
                                            if (!sheetContext.mounted) return;
                                            _placeController.clear();
                                            _phoneController.clear();
                                            _descriptionController.clear();
                                            final baseMessage =
                                                mapState.activeFieldId != null
                                                ? 'Field updated offline successfully'
                                                : 'Field saved offline successfully';
                                            final fullMessage = submitErr == null
                                                ? '$baseMessage and sent to server'
                                                : '$baseMessage. Sync pending: $submitErr';

                                            ScaffoldMessenger.of(sheetContext)
                                                .showSnackBar(
                                                  SnackBar(
                                                    content: Text(fullMessage),
                                                  ),
                                                );
                                            Navigator.pop(sheetContext);
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF001F3F),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: mapState.isSaving ? 0 : 2,
                                ),
                                child: mapState.isSaving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        mapState.activeFieldId != null
                                            ? 'Update Field'
                                            : 'Save Field',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatMapUtm(
  double latitude,
  double longitude,
  ReferenceEllipsoid ellipsoid,
) {
  final utm = UtmConverter.fromLatLng(latitude, longitude, ellipsoid);
  if (utm == null) return 'UTM unavailable';
  return utm.toDisplayString();
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
          heroTag: 'map_tool_${label.toLowerCase().replaceAll(' ', '_')}',
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
  final Widget preview;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapTypeOption({
    required this.label,
    required this.preview,
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF0EA5E9)
                    : Colors.grey.shade300,
                width: isSelected ? 3 : 1.5,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                preview,
                if (isSelected)
                  Container(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? const Color(0xFF0B3B5A) : Colors.grey,
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
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer soft halo to improve visibility on busy tiles.
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2563EB).withValues(alpha: 0.20),
          ),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
            ),
            border: Border.all(color: Colors.white, width: 2.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.40),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
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
