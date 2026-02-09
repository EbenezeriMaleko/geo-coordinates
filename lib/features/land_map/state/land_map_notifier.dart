import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../data/land_repo.dart';
import 'land_map_state.dart';

final landRepoProvider = Provider<LandRepo>((ref) {
  final box = Hive.box('landsBox');
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
      );
      return null;
    } catch (_) {
      return 'Failed to get location.';
    }
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

    final newPoints = [...state.points, current];
    state = state.copyWith(points: newPoints);
    return null;
  }

  void undoLastPoint() {
    if (state.points.isEmpty) return;
    final newPoints = [...state.points]..removeLast();
    state = state.copyWith(points: newPoints);
  }

  void clearPoints() {
    state = state.copyWith(points: []);
  }

  Future<String?> saveOffline({required String name}) async {
    if (state.points.length < 3) {
      return 'Add at least 3 points to form a land boundary.';
    }

    state = state.copyWith(isSaving: true);

    try {
      final id = const Uuid().v4();
      final payload = {
        'id': id,
        'name': name.isEmpty
            ? 'Land ${DateTime.now().toIso8601String()}'
                  'createdAt'
            : DateTime.now().toIso8601String(),
        'syncStatus': 'pending',
        'points': state.points
            .asMap()
            .entries
            .map(
              (e) => {
                'order': e.key,
                'lat': e.value.latitude,
                'lng': e.value.longitude,
              },
            )
            .toList(),
      };

      final repo = ref.read(landRepoProvider);
      await repo.saveLand(payload);

      state = state.copyWith(points: []);
      return null;
    } catch (_) {
      return 'Failed to save offline.';
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}
