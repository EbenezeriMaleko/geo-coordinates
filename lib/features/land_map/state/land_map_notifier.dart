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

class LandMapNotifier extends Notifier<LandMapState> {
  @override
  LandMapState build() {
    return LandMapState.initial();
  }

  Future<String?> initLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return 'Please enable location services.';

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) return 'Location Permission denied';
    if (perm == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Enable it in settings.';
    }

    return await refreshLocation();
  }

  Future<String?> refreshLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      state = state.copyWith(
        current: LatLng(pos.latitude, pos.longitude),
        accuracyMeters: pos.accuracy,
        altitudeMeters: pos.altitude,
        locationTimestamp: pos.timestamp,
      );
      return null;
    } catch (_) {
      return 'Failed to get location.';
    }
  }

  void updateCurrentFromPosition(Position pos) {
    state = state.copyWith(
      current: LatLng(pos.latitude, pos.longitude),
      accuracyMeters: pos.accuracy,
      altitudeMeters: pos.altitude,
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
      current: points.first,
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

  Future<String?> saveOffline({required String name}) async {
    if (state.points.length < 3) {
      return 'Add at least 3 points to form a land boundary.';
    }

    state = state.copyWith(isSaving: true);

    try {
      final id = const Uuid().v4();
      final now = DateTime.now();
      final repo = ref.read(landRepoProvider);
      final pointsPayload = state.points
          .asMap()
          .entries
          .map(
            (e) => {
              'order': e.key,
              'lat': e.value.latitude,
              'lng': e.value.longitude,
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
          'entityType': 'land',
          'name': displayName,
          'updatedAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'points': pointsPayload,
        };
        await repo.updateLand(state.activeFieldId!, updated);
      } else {
        final displayName = name.isEmpty
            ? 'Land ${now.toIso8601String()}'
            : name;
        final payload = {
          'id': id,
          'entityType': 'land',
          'name': displayName,
          'createdAt': now.toIso8601String(),
          'syncStatus': 'pending',
          'points': pointsPayload,
        };
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
}
