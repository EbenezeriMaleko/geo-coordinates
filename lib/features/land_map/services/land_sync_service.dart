import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

import '../models/land_api_models.dart';
import 'land_cloud_service.dart';

class LandSyncResult {
  final int attempted;
  final int synced;
  final int failed;

  const LandSyncResult({
    required this.attempted,
    required this.synced,
    required this.failed,
  });
}

class LandSyncService {
  final Box box;
  final LandCloudService cloudService;

  LandSyncService(this.box, {LandCloudService? cloudService})
    : cloudService = cloudService ?? LandCloudService();

  Future<LandSyncResult> syncPendingLands({int limit = 10}) async {
    final token = (box.get('auth_token')?.toString() ?? '').trim();
    final isVerified = box.get('auth_is_verified') as bool? ?? false;
    if (token.isEmpty || !isVerified) {
      return const LandSyncResult(attempted: 0, synced: 0, failed: 0);
    }

    final pending = _pendingLandEntries(limit: limit);
    int synced = 0;
    int failed = 0;

    for (final entry in pending) {
      final key = entry.key;
      final value = entry.value;
      final error = await _syncOneLandRecord(
        key: key,
        land: value,
        bearerToken: token,
      );
      if (error == null) {
        synced++;
      } else {
        failed++;
      }
    }

    return LandSyncResult(
      attempted: pending.length,
      synced: synced,
      failed: failed,
    );
  }

  List<MapEntry<dynamic, Map<String, dynamic>>> _pendingLandEntries({
    required int limit,
  }) {
    final entries = box
        .toMap()
        .entries
        .where((entry) => entry.value is Map)
        .map(
          (entry) => MapEntry(
            entry.key,
            Map<String, dynamic>.from(entry.value as Map),
          ),
        )
        .where(
          (entry) =>
              (entry.value['entityType']?.toString() ?? '') == 'land' &&
              (entry.value['syncStatus']?.toString() ?? 'pending') == 'pending',
        )
        .toList();

    // Prioritize latest changes so newly saved edits sync quickly.
    entries.sort((a, b) {
      final aTs = _entryTimestamp(a.value);
      final bTs = _entryTimestamp(b.value);
      return bTs.compareTo(aTs);
    });

    if (entries.length <= limit) return entries;
    return entries.take(limit).toList();
  }

  int _entryTimestamp(Map<String, dynamic> item) {
    final updated = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
    if (updated != null) return updated.millisecondsSinceEpoch;
    final created = DateTime.tryParse(item['createdAt']?.toString() ?? '');
    return created?.millisecondsSinceEpoch ?? 0;
  }

  Future<String?> _syncOneLandRecord({
    required dynamic key,
    required Map<String, dynamic> land,
    required String bearerToken,
  }) async {
    final points = _extractPoints(land);
    if (points.length < 3) {
      final err = 'Not enough points to sync.';
      await _markSyncFailed(key, land, err);
      return err;
    }

    final payload = _buildPayload(land, points);

    try {
      final created = await cloudService.createLand(
        bearerToken,
        payload,
      );
      await _markSynced(key, land, created.id);
      return null;
    } catch (error) {
      final err = error.toString().trim().isEmpty
          ? 'Failed to sync land to server.'
          : error.toString();
      await _markSyncFailed(key, land, err);
      return err;
    }
  }

  List<LatLng> _extractPoints(Map<String, dynamic> land) {
    final rawPoints = (land['points'] as List?) ?? const [];
    final points = <LatLng>[];
    for (final item in rawPoints) {
      if (item is! Map) continue;
      final lat = (item['lat'] as num?)?.toDouble();
      final lng = (item['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  CreateLandRequest _buildPayload(
    Map<String, dynamic> land,
    List<LatLng> points,
  ) {
    final firstName = (box.get('auth_first_name')?.toString() ?? '').trim();
    final lastName = (box.get('auth_last_name')?.toString() ?? '').trim();
    final email = (box.get('auth_email')?.toString() ?? '').trim();
    final owner = [
      firstName,
      lastName,
    ].where((name) => name.isNotEmpty).join(' ').trim();

    return CreateLandRequest(
      name: (land['name']?.toString() ?? '').trim().isEmpty
          ? 'Land ${DateTime.now().toIso8601String()}'
          : land['name'].toString().trim(),
      place: land['place']?.toString(),
      phone: (land['phone']?.toString() ?? box.get('submit_phone')?.toString())
          ?.trim(),
      description: (land['description']?.toString() ?? '').trim().isNotEmpty
          ? land['description']?.toString()
          : (owner.isEmpty && email.isEmpty
                ? null
                : 'Captured by ${owner.isNotEmpty ? owner : email}'),
      coordinates: points.map(_latLngToServerCoordinate).toList(),
    );
  }

  LandCoordinateRequest _latLngToServerCoordinate(LatLng point) {
    final zone = _utmZone(point.latitude, point.longitude);
    return LandCoordinateRequest(
      x: point.longitude,
      y: point.latitude,
      z: 0,
      zone: zone.toString(),
      band: _utmBand(point.latitude),
      hemisphere: point.latitude >= 0 ? 'N' : 'S',
    );
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

  Future<void> _markSynced(
    dynamic key,
    Map<String, dynamic> land,
    dynamic remoteId,
  ) async {
    final updated = {
      ...land,
      'syncStatus': 'synced',
      'syncError': null,
      'lastSyncedAt': DateTime.now().toIso8601String(),
    };
    if (remoteId != null) {
      updated['cloudId'] = remoteId.toString();
    }
    await box.put(key, updated);
  }

  Future<void> _markSyncFailed(
    dynamic key,
    Map<String, dynamic> land,
    String error,
  ) async {
    final updated = {
      ...land,
      'syncStatus': 'pending',
      'syncError': error,
      'lastSyncAttemptAt': DateTime.now().toIso8601String(),
    };
    await box.put(key, updated);
  }

}
