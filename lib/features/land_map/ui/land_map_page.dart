import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:taref_gps/features/land_map/services/routing_service.dart';
import 'package:uuid/uuid.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/coordinate_format.dart';
import '../models/reference_ellipsoid.dart';
import '../services/utm_converter.dart';
import '../state/land_map_notifier.dart';
import '../state/land_map_state.dart';
import '../state/settings_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import '../services/map_tile_cache.dart';

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
  List<String> _distanceLabels = const [];

  bool _isLocating = false;
  bool _isMarkerSaving = false;
  bool _isAutoFieldCapture = false;
  bool _isFullscreen = false;
  bool _isMapTypeSwitching = false;
  double _currentZoom = _defaultMapZoom;
  String? _locationError;
  List<_PlacedMarker> _savedMarkers = const [];
  StreamSubscription<Position>? _fieldTrackingSubscription;
  StreamSubscription<Position>? _navigationTrackingSubscription;
  bool _showFieldLayer = true;
  bool _showDistanceLayer = true;
  bool _showMarkerLayer = true;
  List<LatLng> _routePoints = const [];
  RouteResult? _currentRoute;
  bool _isFetchingRoute = false;
  ProviderSubscription<LandMapState>? _landMapSubscription;
  DateTime? _lastNavigationCameraMove;
  bool _userIsInteracting = false;
  bool _followCurrentLocation = true;
  Timer? _interactionCooldownTimer;

  @override
  void initState() {
    super.initState();
    _restoreMapTypePreference();
    _landMapSubscription = ref.listenManual(landMapProvider, (previous, next) {
      final targetChanged = previous?.navigationTarget != next.navigationTarget;
      final currentChanged = previous?.current != next.current;
      final prevLen = previous?.points.length ?? 0;
      final nextLen = next.points.length;

      if (next.navigationTarget != null) {
        if (targetChanged) {
          _lastNavigationCameraMove = null;
          unawaited(_startNavigationTracking());
          // Fetch road route to the target
          final targetPoint = next.navigationTarget!.point;
          unawaited(_fetchRoute(targetPoint));
        }
        if (targetChanged || currentChanged) {
          _focusOnNavigationTarget(next);
        }
        return;
      }

      if (currentChanged) {
        _followCurrentLocationIfNeeded(next.current);
      }

      if (previous?.navigationTarget != null) {
        unawaited(_stopNavigationTracking());
        _clearRoute();
      }

      if (nextLen == 0) return;

      final pointsChanged = previous == null || previous.points != next.points;
      if (!pointsChanged) return;

      if (_fieldTrackingSubscription != null &&
          _followCurrentLocation &&
          next.current != null) {
        _followCurrentLocationIfNeeded(next.current);
        return;
      }

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
    _interactionCooldownTimer?.cancel();
    _landMapSubscription?.close();
    _fieldTrackingSubscription?.cancel();
    _navigationTrackingSubscription?.cancel();
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
      _followCurrentLocation = true;
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
      _followCurrentLocation = true;
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
      _followCurrentLocation = true;
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
            .where((e) {
              final entityType = e['entityType']?.toString();
              return entityType == 'marker' || entityType == 'point';
            })
            .map(
              (e) => _PlacedMarker(
                id: e['id'].toString(),
                point: _extractMarkerPoint(e),
                label: _extractMarkerLabel(e),
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

  LatLng _extractMarkerPoint(Map<String, dynamic> item) {
    final points = (item['points'] as List?) ?? const [];
    if (points.isNotEmpty && points.first is Map) {
      final first = Map<String, dynamic>.from(points.first as Map);
      final lat = (first['lat'] as num?)?.toDouble();
      final lng = (first['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    return LatLng(
      (item['lat'] as num).toDouble(),
      (item['lng'] as num).toDouble(),
    );
  }

  String _extractMarkerLabel(Map<String, dynamic> item) {
    final direct = item['label']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;

    final labels = item['labels'];
    if (labels is List && labels.isNotEmpty) {
      final first = labels.first?.toString().trim() ?? '';
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  Future<void> _addMarkerAt(LatLng point) async {
    if (_isMarkerSaving) return;
    final draft = await _promptMarkerDetails();
    if (draft == null) return;
    setState(() => _isMarkerSaving = true);
    try {
      final box = Hive.box('landbox');
      final ellipsoid = ref.read(referenceEllipsoidProvider);
      final id = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final label = draft.label.trim();
      final payload = {
        'id': id,
        'entityType': 'point',
        'type': 'point',
        'name': draft.name,
        if (label.isNotEmpty) 'label': label,
        if (label.isNotEmpty) 'labels': [label],
        'referenceEllipsoid': ellipsoid.name,
        'points': [
          {'order': 0, 'lat': point.latitude, 'lng': point.longitude},
        ],
        'syncStatus': 'pending',
        'syncError': null,
        'createdAt': now,
        'updatedAt': now,
      };
      await box.put(id, payload);
      if (!mounted) return;
      setState(() {
        _activeTool = _MapTool.none;
      });
      _snack('Location saved locally. Sync queued.');
    } finally {
      if (mounted) {
        setState(() => _isMarkerSaving = false);
      }
    }
  }

  Future<_MarkerDraft?> _promptMarkerDetails() async {
    final nameController = TextEditingController();
    final labelController = TextEditingController();
    final result = await showModalBottomSheet<_MarkerDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Save location',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add location name and point label before saving.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onSubmitted: (value) {
                  FocusScope.of(sheetContext).nextFocus();
                },
                decoration: _sheetInputDecoration(
                  hint: 'e.g. Home, Office, Farm Entrace',
                  icon: Icons.place_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(sheetContext).pop(
                    _MarkerDraft(
                      name: name,
                      label: labelController.text.trim(),
                    ),
                  );
                },
                decoration: _sheetInputDecoration(
                  hint: 'Point label (e.g. A1, P1)',
                  icon: Icons.label_outline,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        if (name.isNotEmpty) {
                          Navigator.of(sheetContext).pop(
                            _MarkerDraft(
                              name: name,
                              label: labelController.text.trim(),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF001F3F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Save',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      labelController.dispose();
    });
    return result;
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
      _distanceLabels = [..._distanceLabels, '${_distancePoints.length}'];
    });
  }

  void _undoDistancePoint() {
    if (_distancePoints.isEmpty) return;
    setState(() {
      _distancePoints = [..._distancePoints]..removeLast();
      _distanceLabels = [..._distanceLabels]..removeLast();
    });
  }

  void _clearDistancePoints() {
    setState(() {
      _distancePoints = const [];
      _distanceLabels = const [];
    });
  }

  Future<void> _saveDistanceRecord({
    required String name,
    String? place,
    String? phone,
    String? description,
  }) async {
    final points = List<LatLng>.from(_distancePoints);
    final labels = List<String>.from(_distanceLabels);
    if (points.length < 2) {
      _snack('Add at least 2 points to save a distance.');
      return;
    }

    final box = Hive.box('landbox');
    final ellipsoid = ref.read(referenceEllipsoidProvider);
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await box.put(id, {
      'id': id,
      'entityType': 'polyline',
      'type': 'polyline',
      'name': name,
      'referenceEllipsoid': ellipsoid.name,
      if ((place ?? '').trim().isNotEmpty) 'place': place!.trim(),
      if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
      if ((description ?? '').trim().isNotEmpty)
        'description': description!.trim(),
      if (labels.isNotEmpty) 'labels': labels,
      'points': points
          .asMap()
          .entries
          .map(
            (entry) => {
              'order': entry.key,
              'lat': entry.value.latitude,
              'lng': entry.value.longitude,
            },
          )
          .toList(),
      'syncStatus': 'pending',
      'syncError': null,
      'createdAt': now,
      'updatedAt': now,
    });

    if (!mounted) return;
    setState(() {
      _distancePoints = const [];
      _activeTool = _MapTool.none;
    });
    _snack('Distance saved locally. Sync queued.');
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

  String _formatDistance(double meters, DistanceUnit unit) {
    if (unit == DistanceUnit.feet) {
      return '${(meters * 3.28084).toStringAsFixed(1)} ft';
    }
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(1)} m';
  }

  List<Marker> _buildSegmentDistanceMarkers(
    List<LatLng> points, {
    required DistanceUnit unit,
    required Color color,
    bool closeLoop = false,
  }) {
    if (points.length < 2) return const [];

    final out = <Marker>[];
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final meters = _distanceCalculator.as(LengthUnit.Meter, a, b);
      final text = _formatDistance(meters, unit);
      final mid = LatLng(
        (a.latitude + b.latitude) / 2,
        (a.longitude + b.longitude) / 2,
      );
      final markerWidth = (text.length * 7.5 + 28).clamp(60.0, 120.0);
      out.add(
        Marker(
          width: markerWidth,
          height: 34,
          point: mid,
          child: _SegmentDistancePill(
            text: text,
            color: color,
          ),
        ),
      );
    }

    if (closeLoop && points.length >= 3) {
      final a = points.last;
      final b = points.first;
      final meters = _distanceCalculator.as(LengthUnit.Meter, a, b);
      final text = _formatDistance(meters, unit);
      final mid = LatLng(
        (a.latitude + b.latitude) / 2,
        (a.longitude + b.longitude) / 2,
      );
      final markerWidth = (text.length * 7.5 + 28).clamp(60.0, 120.0);
      out.add(
        Marker(
          width: markerWidth,
          height: 34,
          point: mid,
          child: _SegmentDistancePill(
            text: text,
            color: color,
          ),
        ),
      );
    }

    return out;
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

  void _focusOnNavigationTarget(LandMapState st) {
    if (_userIsInteracting) return;
    final target = st.navigationTarget;
    if (target == null) return;

    final now = DateTime.now();
    final shouldMoveCamera =
        _lastNavigationCameraMove == null ||
        now.difference(_lastNavigationCameraMove!) > const Duration(seconds: 8);
    if (!shouldMoveCamera) return;

    final current = st.current;
    if (current == null) {
      _focusOnPoints(_targetPoints(target));
      _lastNavigationCameraMove = now;
      return;
    }

    _focusOnPoints([current, ..._targetPoints(target)]);
    _lastNavigationCameraMove = now;
  }

  bool _isUserMapEventSource(MapEventSource source) {
    return switch (source) {
      MapEventSource.dragStart ||
      MapEventSource.onDrag ||
      MapEventSource.dragEnd ||
      MapEventSource.multiFingerGestureStart ||
      MapEventSource.onMultiFinger ||
      MapEventSource.multiFingerEnd ||
      MapEventSource.flingAnimationController ||
      MapEventSource.doubleTap ||
      MapEventSource.doubleTapHold ||
      MapEventSource.doubleTapZoomAnimationController ||
      MapEventSource.scrollWheel ||
      MapEventSource.cursorKeyboardRotation ||
      MapEventSource.keyboard => true,
      _ => false,
    };
  }

  void _followCurrentLocationIfNeeded(LatLng? current) {
    if (!_followCurrentLocation || _userIsInteracting || current == null) {
      return;
    }

    _mapController.move(current, _clampZoom(max(_currentZoom, 17)));
  }

  List<LatLng> _targetPoints(LandNavigationTarget target) {
    return target.points.isEmpty ? [target.point] : target.points;
  }

  LatLng _navigationPointForCurrent(
    LatLng current,
    LandNavigationTarget target,
  ) {
    final points = _targetPoints(target);
    if (points.length == 1) return points.first;

    final kind = target.kind.toLowerCase();
    if (kind != 'polygon' && kind != 'polyline') return target.point;

    return _nearestPointOnTargetSegments(
      current,
      points,
      closeLoop: kind == 'polygon' && points.length >= 3,
    );
  }

  LatLng _nearestPointOnTargetSegments(
    LatLng current,
    List<LatLng> points, {
    required bool closeLoop,
  }) {
    if (points.length == 1) return points.first;

    LatLng bestPoint = points.first;
    double bestDistance = double.infinity;
    final segmentCount = closeLoop ? points.length : points.length - 1;

    for (int i = 0; i < segmentCount; i++) {
      final start = points[i];
      final end = points[(i + 1) % points.length];
      final candidate = _nearestPointOnSegment(current, start, end);
      final distance = _distanceCalculator.as(
        LengthUnit.Meter,
        current,
        candidate,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = candidate;
      }
    }

    return bestPoint;
  }

  LatLng _nearestPointOnSegment(LatLng point, LatLng start, LatLng end) {
    final latScale = 111320.0;
    final lngScale = latScale * cos(point.latitude * pi / 180.0);

    final px = point.longitude * lngScale;
    final py = point.latitude * latScale;
    final ax = start.longitude * lngScale;
    final ay = start.latitude * latScale;
    final bx = end.longitude * lngScale;
    final by = end.latitude * latScale;

    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return start;

    final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );

    final nearestX = ax + dx * t;
    final nearestY = ay + dy * t;
    return LatLng(nearestY / latScale, nearestX / lngScale);
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final fromLat = from.latitude * pi / 180.0;
    final fromLng = from.longitude * pi / 180.0;
    final toLat = to.latitude * pi / 180.0;
    final toLng = to.longitude * pi / 180.0;

    final y = sin(toLng - fromLng) * cos(toLat);
    final x =
        cos(fromLat) * sin(toLat) -
        sin(fromLat) * cos(toLat) * cos(toLng - fromLng);
    return (atan2(y, x) * 180.0 / pi + 360.0) % 360.0;
  }

  String _bearingLabel(double bearing) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((bearing + 22.5) / 45.0).floor() % labels.length;
    return labels[index];
  }

  void _clearNavigationTarget() {
    ref.read(landMapProvider.notifier).clearNavigationTarget();
    _clearRoute();
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

    setState(() {
      _isAutoFieldCapture = true;
      _followCurrentLocation = true;
    });
    _fieldTrackingSubscription =
        Geolocator.getPositionStream(
          // locationSettings: const LocationSettings(
          //   accuracy: LocationAccuracy.best,
          //   distanceFilter: 1,
          // ),
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'TaREF GPS - Coordinates',
              notificationText: 'Location tracking is active',
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'ic_launcher',
                defType: 'mipmap',
              ),
            ),
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

  Future<void> _startNavigationTracking() async {
    if (_navigationTrackingSubscription != null) return;

    final err = await ref.read(landMapProvider.notifier).initLocation();
    if (!mounted) return;
    if (err != null) {
      setState(() => _locationError = err);
      return;
    }

    _navigationTrackingSubscription =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'TaREF GPS - Coordinates',
              notificationText: 'Location tracking is active',
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'ic_launcher',
                defType: 'mipmap',
              ),
            ),
          ),
        ).listen(
          (position) {
            ref
                .read(landMapProvider.notifier)
                .updateCurrentFromPosition(position);
            if (!mounted || _locationError == null) return;
            setState(() => _locationError = null);
          },
          onError: (_) {
            if (!mounted) return;
            setState(() => _locationError = 'Live navigation updates failed.');
          },
        );
  }

  Future<void> _stopNavigationTracking() async {
    await _navigationTrackingSubscription?.cancel();
    _navigationTrackingSubscription = null;
    _lastNavigationCameraMove = null;
  }

  Future<void> _fetchRoute(LatLng destination) async {
    final current = ref.read(landMapProvider).current;
    if (current == null) return;

    setState(() {
      _isFetchingRoute = true;
      _routePoints = const [];
      _currentRoute = null;
    });

    final result = await RoutingService.getRoute(
      from: current,
      to: destination,
    );

    if (!mounted) return;

    setState(() {
      _isFetchingRoute = false;
      if (result != null) {
        _routePoints = result.points;
        _currentRoute = result;
      } else {
        // Fallback to straight line if routing fails
        _routePoints = [current, destination];
        _snack('Road routing unavailable. Showing straight line.');
      }
    });
  }

  void _clearRoute() {
    setState(() {
      _routePoints = const [];
      _currentRoute = null;
    });
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
            (existing['place']?.toString() ??
                    existing['name']?.toString() ??
                    '')
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

  List<String> _loadFieldPointLabels(String? fieldId, int fallbackCount) {
    if (fieldId == null) {
      return List<String>.generate(fallbackCount, (index) => '${index + 1}');
    }
    final box = Hive.box('landbox');
    final raw = box.get(fieldId);
    if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);
      final labelsRaw = data['labels'];
      if (labelsRaw is List) {
        final labels = labelsRaw
            .map((value) => value?.toString().trim() ?? '')
            .toList();
        if (labels.isNotEmpty) {
          return _normalizeStringLabels(labels, fallbackCount);
        }
      }
    }
    return List<String>.generate(fallbackCount, (index) => '${index + 1}');
  }

  List<String> _normalizePointLabels(
    List<TextEditingController> controllers,
    int count,
  ) {
    final labels = List<String>.generate(count, (index) {
      if (index >= controllers.length) return '';
      return controllers[index].text.trim();
    });
    return _normalizeStringLabels(labels, count);
  }

  List<String> _normalizeStringLabels(List<String> labels, int count) {
    return List<String>.generate(count, (index) {
      if (index >= labels.length) return '${index + 1}';
      final value = labels[index].trim();
      return value.isEmpty ? '${index + 1}' : value;
    });
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

  InputDecoration _pointLabelDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
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
        borderSide: const BorderSide(color: Color(0xFF001F3F), width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    );
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
    final coordinateFormat = ref.watch(coordinateFormatProvider);
    final distanceUnit = ref.watch(distanceUnitProvider);
    final referenceEllipsoid = ref.watch(referenceEllipsoidProvider);
    final utmText = st.current == null
        ? null
        : _formatMapUtm(
            st.current!.latitude,
            st.current!.longitude,
            referenceEllipsoid,
          );
    final bottomFabOffset = widget.bottomInset + 16;

    final center = st.current ?? const LatLng(-6.7924, 39.2083);
    final navigationTarget = st.navigationTarget;
    final navigationTargetPoints = navigationTarget == null
        ? const <LatLng>[]
        : _targetPoints(navigationTarget);
    final navigationTargetKind =
        navigationTarget?.kind.toLowerCase().trim() ?? '';
    final navigationGuidancePoint = navigationTarget == null
        ? null
        : st.current == null
        ? navigationTarget.point
        : _navigationPointForCurrent(st.current!, navigationTarget);

    final fieldSegmentLabels = _showFieldLayer
        ? _buildSegmentDistanceMarkers(
            st.points,
            unit: distanceUnit,
            color: const Color(0xFF001F3F),
            closeLoop: st.points.length >= 3,
          )
        : const <Marker>[];

    final distanceSegmentLabels = _showDistanceLayer
        ? _buildSegmentDistanceMarkers(
            _distancePoints,
            unit: distanceUnit,
            color: Colors.orange.shade700,
            closeLoop: false,
          )
        : const <Marker>[];

    final markers = <Marker>[
      if (_showFieldLayer)
        for (int i = 0; i < st.points.length; i++)
          Marker(
            width: 40,
            height: 40,
            point: st.points[i],
            child: _PointMarker(index: i + 1),
          ),
      ...fieldSegmentLabels,

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
              child: _SavedMarkerPin(label: marker.label),
            ),
          ),
      if (navigationTarget != null && navigationTargetKind == 'point')
        Marker(
          width: 46,
          height: 46,
          point: navigationGuidancePoint ?? navigationTarget.point,
          child: const _NavigationTargetMarker(),
        ),
      if (navigationTarget != null && navigationTargetKind != 'point')
        for (int i = 0; i < navigationTargetPoints.length; i++)
          Marker(
            width: 28,
            height: 28,
            point: navigationTargetPoints[i],
            child: _NavigationTargetVertexMarker(
              label: i < navigationTarget.pointLabels.length
                  ? navigationTarget.pointLabels[i]
                  : '${i + 1}',
            ),
          ),
      if (navigationTarget != null &&
          navigationTargetKind != 'point' &&
          navigationGuidancePoint != null)
        Marker(
          width: 42,
          height: 42,
          point: navigationGuidancePoint,
          child: const _NavigationTargetMarker(),
        ),
      if (_showDistanceLayer)
        for (int i = 0; i < _distancePoints.length; i++)
          Marker(
            width: 34,
            height: 34,
            point: _distancePoints[i],
            child: _DistancePointMarker(
              label: i < _distanceLabels.length
                  ? _distanceLabels[i]
                  : '${i + 1}',
            ),
          ),
      ...distanceSegmentLabels,
    ];

    final polygons = <Polygon>[
      if (_showFieldLayer && st.points.length >= 3)
        Polygon(
          points: st.points,
          borderStrokeWidth: 3,
          color: const Color(0xFF001F3F).withValues(alpha: 0.3),
          borderColor: const Color(0xFF001F3F),
        ),
      if (navigationTargetKind == 'polygon' &&
          navigationTargetPoints.length >= 3)
        Polygon(
          points: navigationTargetPoints,
          borderStrokeWidth: 3,
          color: Colors.teal.shade700.withValues(alpha: 0.20),
          borderColor: Colors.teal.shade700,
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
      if (navigationTargetKind == 'polyline' &&
          navigationTargetPoints.length >= 2)
        Polyline(
          points: navigationTargetPoints,
          strokeWidth: 5,
          color: Colors.teal.shade700,
        ),
      // Show road route if available, otherwise straight line
      if (navigationTarget != null && st.current != null)
        if (_routePoints.length >= 2)
          Polyline(
            points: _routePoints,
            strokeWidth: 4,
            color: Colors.teal.shade700,
          )
        else if (navigationGuidancePoint != null)
          Polyline(
            points: [st.current!, navigationGuidancePoint],
            strokeWidth: 3,
            color: Colors.teal.shade700,
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
            onMapEvent: (event) {
              final isUserEvent = _isUserMapEventSource(event.source);
              if (event is MapEventMoveStart ||
                  event is MapEventFlingAnimationStart) {
                if (isUserEvent) {
                  _interactionCooldownTimer?.cancel();
                  setState(() {
                    _userIsInteracting = true;
                    _followCurrentLocation = false;
                  });
                }
              }
              if (event is MapEventMoveEnd ||
                  event is MapEventFlingAnimationEnd) {
                if (isUserEvent) {
                  _interactionCooldownTimer?.cancel();
                  _interactionCooldownTimer = Timer(
                    const Duration(seconds: 2),
                    () {
                      if (mounted) setState(() => _userIsInteracting = false);
                    },
                  );
                }
              }
            },
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

            Positioned(
              top: 140 + MediaQuery.of(context).padding.top,
              child: const Padding(
                padding: EdgeInsets.all(10.0),
                child: MapCompass.cupertino(hideIfRotatedNorth: true),
              ),
            ),

            RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [TextSourceAttribution('OSM contributors')],
            ),
          ],
        ),
        if (_isFetchingRoute)
          Positioned(
            top: 110 + MediaQuery.of(context).padding.top,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.teal.shade700,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Finding best route...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
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
            top: 16 + MediaQuery.of(context).padding.top,
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
                        if (st.current != null)
                          Text(
                            utmText ?? 'UTM unavailable',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,

                              color: Colors.black87,
                            ),
                          ),
                        if (st.current != null)
                          Text(
                            '${referenceEllipsoid.displayName} • Accuracy: ${st.accuracyMeters == null ? '—' : _formatDistance(st.accuracyMeters!, distanceUnit)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
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

        if (!_isFullscreen)
          if (_locationError != null && !_isFullscreen)
            Positioned(
              top: 92 + MediaQuery.of(context).padding.top,
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

        if (!_isFullscreen &&
            (_activeTool != _MapTool.none ||
                st.activeFieldId != null ||
                navigationTarget != null))
          Positioned(
            top: _locationError == null
                ? 92 + MediaQuery.of(context).padding.top
                : 202 + MediaQuery.of(context).padding.top,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_activeTool != _MapTool.none || st.activeFieldId != null)
                  _buildStatusPill(st),
                if ((_activeTool != _MapTool.none ||
                        st.activeFieldId != null) &&
                    navigationTarget != null)
                  const SizedBox(height: 8),
                if (navigationTarget != null) _buildNavigationBanner(st),
              ],
            ),
          ),

        // Map Controls (Right side)
        Positioned(
          right: 16,
          top: _isFullscreen ? 90 : 160 + MediaQuery.of(context).padding.top,
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
                isActive: _followCurrentLocation,
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

        Positioned(
          left: 16,
          bottom: bottomFabOffset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolButton(
                label: 'Area',
                icon: SvgPicture.asset(
                  'lib/assets/icons/golf-hole.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF001F3F),
                    BlendMode.srcIn,
                  ),
                ),
                isActive: false,
                onPressed: () {
                  setState(() => _activeTool = _MapTool.none);
                  _showFieldDialog();
                },
              ),
              const SizedBox(height: 10),
              _ToolButton(
                label: 'Route',
                icon: SvgPicture.asset(
                  'lib/assets/icons/map-location-track.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    _activeTool == _MapTool.distance
                        ? Colors.white
                        : const Color(0xFF001F3F),
                    BlendMode.srcIn,
                  ),
                ),
                isActive: _activeTool == _MapTool.distance,
                onPressed: () {
                  setState(() {
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

              const SizedBox(height: 10),
              _ToolButton(
                label: 'Point',
                icon: SvgPicture.asset(
                  'lib/assets/icons/marker.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    _activeTool == _MapTool.marker
                        ? Colors.white
                        : const Color(0xFF001F3F),
                    BlendMode.srcIn,
                  ),
                ),
                isActive: _activeTool == _MapTool.marker,
                onPressed: () {
                  setState(() {
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
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMapTileLayers() {
    final cacheStore = MapTileCache.store;

    TileLayer cachedTile(
      String urlTemplate, {
      List<String> subdomains = const [],
      double maxZoom = 20,
    }) {
      return TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: 'com.example.landmapper',
        subdomains: subdomains,
        maxZoom: maxZoom,
        tileProvider: CachedTileProvider(
          maxStale: const Duration(days: 30),
          store: cacheStore,
        ),
      );
    }

    switch (_currentMapType) {
      case MapType.normal:
        return [
          cachedTile(
            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
        ];
      case MapType.satellite:
        return [
          cachedTile(
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          ),
        ];
      case MapType.terrain:
        return [
          cachedTile(
            'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
            maxZoom: 17,
          ),
        ];
      case MapType.hybrid:
        return [
          cachedTile(
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          ),
          cachedTile(
            'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png',
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

  Future<void> _showFieldDialog() async {
    final current = ref.read(landMapProvider);
    _prepareFieldFormControllers(current);
    final initialLabels = _loadFieldPointLabels(
      current.activeFieldId,
      current.points.length,
    );
    final labelControllers = <TextEditingController>[];
    var labelsInitialized = false;

    void syncLabelControllers(int count) {
      if (!labelsInitialized) {
        for (int i = 0; i < count; i++) {
          labelControllers.add(
            TextEditingController(
              text: i < initialLabels.length ? initialLabels[i] : '${i + 1}',
            ),
          );
        }
        labelsInitialized = true;
        return;
      }

      if (count > labelControllers.length) {
        for (int i = labelControllers.length; i < count; i++) {
          labelControllers.add(TextEditingController(text: '${i + 1}'));
        }
      }
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          String? fieldSheetMessage;
          bool fieldSheetIsError = false;

          return StatefulBuilder(
            builder: (sheetStateContext, setSheetState) {
              return Consumer(
                builder: (context, ref, child) {
                  final mapState = ref.watch(landMapProvider);
                  final distanceUnit = ref.watch(distanceUnitProvider);
                  final pointsCount = mapState.points.length;
                  final perimeter = _calculatePerimeterMeters(mapState.points);
                  final area = _calculateAreaSqm(mapState.points);
                  final notifier = ref.read(landMapProvider.notifier);
                  final bottomInset = MediaQuery.of(
                    sheetStateContext,
                  ).viewInsets.bottom;
                  syncLabelControllers(pointsCount);

                  Widget? feedbackBanner;
                  if (fieldSheetMessage != null) {
                    feedbackBanner = Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: fieldSheetIsError
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: fieldSheetIsError
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            fieldSheetIsError
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: fieldSheetIsError
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              fieldSheetMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: fieldSheetIsError
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                fieldSheetMessage = null;
                              });
                            },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    );
                  }

                  return PopScope(
                    canPop: true,
                    onPopInvokedWithResult: (_, result) async {
                      await _stopAutoFieldCapture();
                    },
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          14,
                          20,
                          bottomInset + 20,
                        ),
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
                                    ? 'Update Area'
                                    : 'Create Area',
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
                              Text(
                                'Phone (optional)',
                                style: _sheetLabelStyle(),
                              ),
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
                              Text(
                                'Description (optional)',
                                style: _sheetLabelStyle(),
                              ),
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
                                'Mark current Location while walking around the field boundary.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
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
                                              if (!sheetStateContext.mounted)
                                                return;
                                              setSheetState(() {
                                                fieldSheetMessage =
                                                    err ?? 'Point added';
                                                fieldSheetIsError = err != null;
                                              });
                                            },
                                      icon: const Icon(Icons.my_location),
                                      label: const Text(
                                        'Mark Current Location',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF001F3F,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
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
                                      onPressed:
                                          pointsCount == 0 || mapState.isSaving
                                          ? null
                                          : notifier.undoLastPoint,
                                      icon: const Icon(Icons.undo),
                                      label: const Text('Undo Last'),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          pointsCount == 0 || mapState.isSaving
                                          ? null
                                          : notifier.clearPoints,
                                      icon: const Icon(
                                        Icons.delete_sweep_outlined,
                                      ),
                                      label: const Text('Clear All'),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                      'Perimeter: ${_formatDistance(perimeter, distanceUnit)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Area: ${_formatArea(area)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (pointsCount > 0) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Point labels',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Optional. Rename boundary points for reference.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: List.generate(pointsCount, (
                                      index,
                                    ) {
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom: index == pointsCount - 1
                                              ? 0
                                              : 10,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 72,
                                              child: Text(
                                                'Point ${index + 1}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: TextField(
                                                controller:
                                                    labelControllers[index],
                                                textInputAction:
                                                    index == pointsCount - 1
                                                    ? TextInputAction.done
                                                    : TextInputAction.next,
                                                decoration:
                                                    _pointLabelDecoration(
                                                      hint: 'Label',
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                              if (feedbackBanner != null) ...[
                                const SizedBox(height: 12),
                                feedbackBanner,
                              ],
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: mapState.isSaving
                                          ? null
                                          : () async {
                                              await _stopAutoFieldCapture();
                                              if (mapState.activeFieldId ==
                                                  null) {
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
                                                final enteredPlace =
                                                    _placeController.text
                                                        .trim();
                                                final enteredPhone =
                                                    _phoneController.text
                                                        .trim();
                                                final enteredDescription =
                                                    _descriptionController.text
                                                        .trim();
                                                final pointLabels =
                                                    _normalizePointLabels(
                                                      labelControllers,
                                                      pointsCount,
                                                    );

                                                if (enteredPlace.isEmpty) {
                                                  if (!sheetStateContext
                                                      .mounted) {
                                                    return;
                                                  }
                                                  setSheetState(() {
                                                    fieldSheetMessage =
                                                        'Place is required.';
                                                    fieldSheetIsError = true;
                                                  });
                                                  return;
                                                }

                                                final effectiveName =
                                                    enteredPlace;

                                                final err = await notifier
                                                    .saveOffline(
                                                      name: effectiveName,
                                                      place: enteredPlace,
                                                      phone: enteredPhone,
                                                      description:
                                                          enteredDescription,
                                                      pointLabels: pointLabels,
                                                    );
                                                if (!sheetStateContext
                                                    .mounted) {
                                                  return;
                                                }

                                                if (err != null) {
                                                  setSheetState(() {
                                                    fieldSheetMessage = err;
                                                    fieldSheetIsError = true;
                                                  });
                                                } else {
                                                  await _stopAutoFieldCapture();
                                                  if (!sheetStateContext
                                                      .mounted) {
                                                    return;
                                                  }
                                                  _placeController.clear();
                                                  _phoneController.clear();
                                                  _descriptionController
                                                      .clear();
                                                  setSheetState(() {
                                                    fieldSheetMessage =
                                                        mapState.activeFieldId !=
                                                            null
                                                        ? 'Field updated offline successfully. Sync queued.'
                                                        : 'Field saved offline successfully. Sync queued.';
                                                    fieldSheetIsError = false;
                                                  });
                                                }
                                              },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF001F3F,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          elevation: mapState.isSaving ? 0 : 2,
                                        ),
                                        child: mapState.isSaving
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : Text(
                                                mapState.activeFieldId != null
                                                    ? 'Update Area'
                                                    : 'Save Area',
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
              );
            },
          );
        },
      );
    } finally {
      for (final controller in labelControllers) {
        controller.dispose();
      }
    }
  }

  void _showDistanceDialog() {
    _placeController.clear();
    _phoneController.text =
        _optionalTrim(Hive.box('landbox').get('submit_phone')?.toString()) ??
        '';
    _descriptionController.clear();
    final distanceUnit = ref.read(distanceUnitProvider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        final totalDistance = _totalDistanceMeters();
        return SafeArea(
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
                    'Save Distance',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Store this measured line locally and send it to the server as a distance record.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Place', style: _sheetLabelStyle()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _placeController,
                    decoration: _sheetInputDecoration(
                      hint: 'Distance name or place',
                      icon: Icons.place_outlined,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Phone', style: _sheetLabelStyle()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _sheetInputDecoration(
                      hint: 'Contact phone',
                      icon: Icons.phone_outlined,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Description', style: _sheetLabelStyle()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: _sheetInputDecoration(
                      hint: 'Notes about this distance',
                      icon: Icons.notes_outlined,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                          '${_distancePoints.length} points • ${_formatDistance(totalDistance, distanceUnit)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_distancePoints.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Point labels',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          StatefulBuilder(
                            builder: (context, setModalState) {
                              return Column(
                                children: List.generate(
                                  _distancePoints.length,
                                  (index) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          child: Text(
                                            '${index + 1}.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: TextFormField(
                                            initialValue:
                                                index < _distanceLabels.length
                                                ? _distanceLabels[index]
                                                : '${index + 1}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Point ${index + 1}',
                                              hintStyle: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 13,
                                              ),
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                            ),
                                            onChanged: (value) {
                                              final updated = List<String>.from(
                                                _distanceLabels,
                                              );
                                              while (updated.length <= index) {
                                                updated.add(
                                                  '${updated.length + 1}',
                                                );
                                              }
                                              updated[index] =
                                                  value.trim().isEmpty
                                                  ? '${index + 1}'
                                                  : value;
                                              setState(() {
                                                _distanceLabels = updated;
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        final place = _placeController.text.trim();
                        if (place.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Place is required.')),
                          );
                          return;
                        }

                        await _saveDistanceRecord(
                          name: place,
                          place: place,
                          phone: _phoneController.text.trim(),
                          description: _descriptionController.text.trim(),
                        );
                        if (!sheetContext.mounted) return;
                        _placeController.clear();
                        _phoneController.clear();
                        _descriptionController.clear();
                        Navigator.pop(sheetContext);
                      },
                      child: const Text('Save distance'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPill(LandMapState st) {
    final Color bg;
    final Color textColor;
    final IconData icon;
    final String label;
    VoidCallback? onDismiss;

    if (st.activeFieldId != null) {
      bg = Colors.green.shade700;
      textColor = Colors.white;
      icon = Icons.edit_location_alt;
      label = 'Editing: ${st.activeFieldName ?? 'Saved field'}';
      onDismiss = () {
        ref.read(landMapProvider.notifier).exitEditingMode();
        _snack('Exited edit mode');
      };
    } else if (_activeTool == _MapTool.marker) {
      bg = const Color(0xFF001F3F);
      textColor = Colors.white;
      icon = Icons.push_pin;
      label = 'Marker — long-press to place';
      onDismiss = () => setState(() => _activeTool = _MapTool.none);
    } else {
      // distance
      bg = Colors.orange.shade800;
      textColor = Colors.white;
      icon = Icons.straighten;
      label = _distancePoints.isEmpty
          ? 'Distance — tap map or Mark GPS'
          : _formatDistance(
              _totalDistanceMeters(),
              ref.read(distanceUnitProvider),
            );
      onDismiss = () => setState(() => _activeTool = _MapTool.none);
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Distance-specific actions
            if (_activeTool == _MapTool.distance &&
                _distancePoints.isNotEmpty) ...[
              const SizedBox(width: 6),
              _PillAction(
                label: 'GPS',
                onTap: _isLocating ? null : _addCurrentPointToDistance,
              ),
              if (_distancePoints.length >= 2)
                _PillAction(label: 'Save', onTap: _showDistanceDialog),
              _PillAction(label: 'Undo', onTap: _undoDistancePoint),
              _PillAction(label: 'Clear', onTap: _clearDistancePoints),
            ],
            // Distance GPS button when no points yet
            if (_activeTool == _MapTool.distance && _distancePoints.isEmpty)
              _PillAction(
                label: 'GPS',
                onTap: _isLocating ? null : _addCurrentPointToDistance,
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                color: textColor.withValues(alpha: 0.75),
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationBanner(LandMapState st) {
    final target = st.navigationTarget;
    if (target == null) return const SizedBox.shrink();

    final current = st.current;
    final guidancePoint = current == null
        ? target.point
        : _navigationPointForCurrent(current, target);

    // Use road distance if available, otherwise straight line
    final distanceText = _isFetchingRoute
        ? 'Calculating route...'
        : _currentRoute != null
        ? _formatDistance(
            _currentRoute!.distanceMeters,
            ref.read(distanceUnitProvider),
          )
        : current == null
        ? 'Waiting for location'
        : _formatDistance(
            _distanceCalculator.as(LengthUnit.Meter, current, guidancePoint),
            ref.read(distanceUnitProvider),
          );

    final durationText = _currentRoute != null
        ? ' · ${_currentRoute!.formattedDuration}'
        : '';

    final bearingText = current == null || _currentRoute != null
        ? ''
        : ' · ${_bearingLabel(_bearingDegrees(current, guidancePoint))}';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.shade700,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.navigation, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${target.label} · $distanceText$durationText$bearingText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _clearNavigationTarget,
              child: Icon(
                Icons.close,
                color: Colors.white.withValues(alpha: 0.75),
                size: 14,
              ),
            ),
          ],
        ),
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

class _ToolButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool isActive;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF001F3F) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isActive ? 0.25 : 0.10),
                  blurRadius: isActive ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: isActive
                  ? null
                  : Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive ? const Color(0xFF001F3F) : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PillAction({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: onTap != null ? 0.20 : 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: onTap != null ? 1.0 : 0.4),
          ),
        ),
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
  final String label;

  const _SavedMarkerPin({required this.label});

  @override
  Widget build(BuildContext context) {
    final clean = label.trim();
    final markerLabel = clean.isEmpty
        ? ''
        : clean.substring(0, min(2, clean.length)).toUpperCase();
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
      child: markerLabel.isEmpty
          ? const Icon(Icons.push_pin, color: Colors.white, size: 20)
          : Center(
              child: Text(
                markerLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }
}

class _NavigationTargetMarker extends StatelessWidget {
  const _NavigationTargetMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.teal.withValues(alpha: 0.18),
          ),
        ),
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.teal.shade700,
            border: Border.all(color: Colors.white, width: 2.4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.near_me, color: Colors.white, size: 14),
        ),
      ],
    );
  }
}

class _NavigationTargetVertexMarker extends StatelessWidget {
  final String label;

  const _NavigationTargetVertexMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.teal.shade700,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 9,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _DistancePointMarker extends StatelessWidget {
  final String label;
  const _DistancePointMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.orange.shade700,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}

class _SegmentDistancePill extends StatelessWidget {
  final String text;
  final Color color;

  const _SegmentDistancePill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _PlacedMarker {
  final String id;
  final LatLng point;
  final String label;
  final DateTime? createdAt;

  const _PlacedMarker({
    required this.id,
    required this.point,
    required this.label,
    required this.createdAt,
  });
}

class _MarkerDraft {
  final String name;
  final String label;

  const _MarkerDraft({required this.name, required this.label});
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
