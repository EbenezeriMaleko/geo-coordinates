import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../data/land_repo.dart';
import 'land_map_state.dart';

final landRepoProvider = Provider<LandRepo>((ref) {
  final box = Hive.box('landbox');
  return LandRepo(box);
});

final landMapProvider = NotifierProvider<LandMapNotifier, LandMapState>(
  LandMapNotifier.new,
);

/// Serializes concurrent [Geolocator.requestPermission] calls.
/// On first install the map page and my-location page both mount at once
/// (IndexedStack); without this gate one caller can hang forever.
class _LocationPermissionCoordinator {
  static Future<LocationPermission>? _inFlight;

  static Future<LocationPermission> resolve() async {
    var permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.denied) {
      return permission;
    }

    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final request = Geolocator.requestPermission();
    _inFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) {
        _inFlight = null;
      }
    }
  }
}

class LandMapNotifier extends Notifier<LandMapState> {
  @override
  LandMapState build() {
    return LandMapState.initial();
  }

  void setNavigationTarget(LandNavigationTarget target) {
    state = state.copyWith(navigationTarget: target);
  }

  void clearNavigationTarget() {
    state = state.copyWith(clearNavigationTarget: true);
  }

  /// Checks location availability without displaying the system prompt.
  Future<String?> ensureLocationAccess() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return 'Please enable location services.';

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) return 'Location Permission denied';
    if (perm == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Enable it in settings.';
    }
    return null;
  }

  /// Requests location after an explicit user choice.
  Future<String?> requestLocationAccess() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return 'Please enable location services.';

    final perm = await _LocationPermissionCoordinator.resolve();
    if (perm == LocationPermission.denied) return 'Location Permission denied';
    if (perm == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Enable it in settings.';
    }
    return null;
  }

  Future<String?> initLocation() async {
    final err = await requestLocationAccess();
    if (err != null) return err;
    return refreshLocation();
  }

  Future<String?> refreshLocation() async {
    // Step 1: getLastKnownPosition is instant — it reads from the OS cache.
    // This resolves the first-launch stuck spinner: the foreground service
    // used in the old code started but never fully terminated, keeping the
    // platform channel open. Now we return almost immediately regardless.
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        state = state.copyWith(
          current: LatLng(lastKnown.latitude, lastKnown.longitude),
          accuracyMeters: lastKnown.accuracy,
          altitudeMeters: lastKnown.altitude,
          speedMps: lastKnown.speed,
          locationTimestamp: lastKnown.timestamp,
        );
      }
    } catch (_) {}

    // Step 2: fire a fresh GPS fix silently in the background.
    // No spinner, no error shown. When it arrives the landMapProvider state
    // updates and the map re-centers through the existing listener.
    unawaited(_fetchFreshPositionSilently());
    return null;
  }

  Future<void> _fetchFreshPositionSilently() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 30),
        ),
      );
      state = state.copyWith(
        current: LatLng(pos.latitude, pos.longitude),
        accuracyMeters: pos.accuracy,
        altitudeMeters: pos.altitude,
        speedMps: pos.speed,
        locationTimestamp: pos.timestamp,
      );
    } catch (_) {
      // Silent — user already has a position displayed or sees the default map.
    }
  }

  void updateCurrentFromPosition(Position pos) {
    state = state.copyWith(
      current: LatLng(pos.latitude, pos.longitude),
      accuracyMeters: pos.accuracy,
      altitudeMeters: pos.altitude,
      speedMps: pos.speed,
      locationTimestamp: pos.timestamp,
    );
  }

  Future<String?> addPointFromCurrent({double maxAccuracy = 15}) async {
    final err = await refreshLocation();
    if (err != null) return err;

    final current = state.current;
    if (current == null) return 'No location available';

    final acc = state.accuracyMeters ?? 999;
    if (acc > maxAccuracy) {
      return 'GPS accuracy is poor (${acc.toStringAsFixed(0)}m). Wait or move to open area.';
    }

    return _appendPointIfValid(current, minDistanceMeters: 2);
  }

  String? addPointAt(LatLng point, {double minDistanceMeters = 2}) {
    return _appendPointIfValid(point, minDistanceMeters: minDistanceMeters);
  }

  String? addPointFromLivePosition(
    Position position, {
    double maxAccuracy = 20,
    double minDistanceMeters = 2,
  }) {
    if (position.accuracy > maxAccuracy) {
      return 'accuracy_low';
    }
    final point = LatLng(position.latitude, position.longitude);
    state = state.copyWith(
      current: point,
      accuracyMeters: position.accuracy,
      altitudeMeters: position.altitude,
      locationTimestamp: position.timestamp,
    );
    return _appendPointIfValid(point, minDistanceMeters: minDistanceMeters);
  }

  void undoLastPoint() {
    if (state.points.isEmpty) return;
    final newPoints = [...state.points]..removeLast();
    state = state.copyWith(points: newPoints);
  }

  void clearPoints() {
    state = state.copyWith(points: []);
  }

  void loadSavedFieldPoints(
    List<LatLng> points, {
    String? fieldId,
    String? fieldName,
  }) {
    if (points.isEmpty) return;
    state = state.copyWith(
      points: [...points],
      activeFieldId: fieldId,
      activeFieldName: fieldName,
    );
  }

  void exitEditingMode() {
    state = state.copyWith(clearActiveField: true);
  }

  String? _appendPointIfValid(
    LatLng point, {
    required double minDistanceMeters,
  }) {
    final points = state.points;
    if (points.isNotEmpty) {
      final last = points.last;
      final delta = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        point.latitude,
        point.longitude,
      );
      if (delta < minDistanceMeters) {
        return 'Move at least ${minDistanceMeters.toStringAsFixed(0)}m before adding next point.';
      }
    }

    final newPoints = [...points, point];
    state = state.copyWith(points: newPoints);
    return null;
  }

  Future<String?> saveOffline({
    required String name,
    String? place,
    String? phone,
    String? description,
    List<String>? pointLabels,
  }) async {
    if (state.points.length < 3) {
      return 'Add at least 3 points to form a land boundary.';
    }

    state = state.copyWith(isSaving: true);

    try {
      final id = const Uuid().v4();
      final now = DateTime.now();
      final repo = ref.read(landRepoProvider);
      final placeValue = place?.trim() ?? '';
      final phoneValue = phone?.trim() ?? '';
      final descriptionValue = description?.trim() ?? '';
      final normalizedLabels = _normalizePointLabels(
        pointLabels,
        state.points.length,
      );
      final pointsPayload = state.points
          .asMap()
          .entries
          .map(
            (e) => {
              'order': e.key,
              'lat': e.value.latitude,
              'lng': e.value.longitude,
              'label': normalizedLabels[e.key],
            },
          )
          .toList();

      if (state.activeFieldId != null) {
        final existing = await repo.getById(state.activeFieldId!);
        if (existing == null) {
          return 'Field no longer exists.';
        }
        final displayName = name.isEmpty
            ? (existing['name']?.toString() ?? 'Land ${now.toIso8601String()}')
            : name;
        final updated = {
          ...existing,
          'id': state.activeFieldId,
          'entityType': 'polygon',
          'type': 'polygon',
          'name': displayName,
          'updatedAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'points': pointsPayload,
          'labels': normalizedLabels,
        };
        if (placeValue.isNotEmpty) {
          updated['place'] = placeValue;
        } else {
          updated.remove('place');
        }
        if (phoneValue.isNotEmpty) {
          updated['phone'] = phoneValue;
        } else {
          updated.remove('phone');
        }
        if (descriptionValue.isNotEmpty) {
          updated['description'] = descriptionValue;
        } else {
          updated.remove('description');
        }
        await repo.updateLand(state.activeFieldId!, updated);
      } else {
        final displayName = name.isEmpty
            ? 'Land ${now.toIso8601String()}'
            : name;
        final payload = {
          'id': id,
          'entityType': 'polygon',
          'type': 'polygon',
          'name': displayName,
          'createdAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'points': pointsPayload,
          'labels': normalizedLabels,
        };
        if (placeValue.isNotEmpty) {
          payload['place'] = placeValue;
        }
        if (phoneValue.isNotEmpty) {
          payload['phone'] = phoneValue;
        }
        if (descriptionValue.isNotEmpty) {
          payload['description'] = descriptionValue;
        }
        await repo.saveLand(payload);
      }

      state = state.copyWith(points: [], clearActiveField: true);
      return null;
    } catch (_) {
      return 'Failed to save offline.';
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }

  List<String> _normalizePointLabels(List<String>? labels, int count) {
    return List<String>.generate(count, (index) {
      if (labels == null || index >= labels.length) {
        return '${index + 1}';
      }
      final value = labels[index].trim();
      return value.isEmpty ? '${index + 1}' : value;
    });
  }

  /// Transform all coordinates in the land map state
  /// Used when changing the reference ellipsoid
  void transformAllCoordinates(LatLng Function(LatLng) coordinateTransformer) {
    // Transform all points with debug logging
    final transformedPoints = <LatLng>[];
    for (var i = 0; i < state.points.length; i++) {
      final old = state.points[i];
      final updated = coordinateTransformer(old);
      try {
        debugPrint(
          'LandMapNotifier: point #$i: '
          '${old.latitude.toStringAsFixed(6)},${old.longitude.toStringAsFixed(6)} '
          '-> ${updated.latitude.toStringAsFixed(6)},${updated.longitude.toStringAsFixed(6)}',
        );
      } catch (_) {}
      transformedPoints.add(updated);
    }

    // Transform current location if available with debug logging
    final transformedCurrent = state.current != null
        ? (() {
            final old = state.current!;
            final updated = coordinateTransformer(old);
            try {
              debugPrint(
                'LandMapNotifier: current: '
                '${old.latitude.toStringAsFixed(6)},${old.longitude.toStringAsFixed(6)} '
                '-> ${updated.latitude.toStringAsFixed(6)},${updated.longitude.toStringAsFixed(6)}',
              );
            } catch (_) {}
            return updated;
          })()
        : null;

    // Update state with transformed coordinates
    state = state.copyWith(
      points: transformedPoints,
      current: transformedCurrent,
    );
  }
}
