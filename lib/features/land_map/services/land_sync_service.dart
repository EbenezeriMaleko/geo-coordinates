import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

import '../models/land_api_models.dart';
import '../models/reference_ellipsoid.dart';
import 'utm_converter.dart';
import 'land_cloud_service.dart';

const _referenceEllipsoidPrefKey = 'prefs_reference_ellipsoid';
const _syncSchemaVersionKey = 'land_sync_schema_version';
const _currentSyncSchemaVersion = 1;

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

  /// Stores a complete cloud record locally so it can be edited offline.
  /// Pending local edits always win; a cloud refresh must not overwrite them.
  Future<String> cacheCloudLand(LandDetail detail) async {
    dynamic localKey;
    Map<String, dynamic>? existing;
    for (final entry in box.toMap().entries) {
      if (entry.value is! Map) continue;
      final candidate = Map<String, dynamic>.from(entry.value as Map);
      final localId = candidate['id']?.toString().trim() ?? '';
      final cloudId = candidate['cloudId']?.toString().trim() ?? '';
      if (localId == detail.id || cloudId == detail.id) {
        localKey = entry.key;
        existing = candidate;
        break;
      }
    }

    final existingId = existing?['id']?.toString().trim() ?? '';
    if (existing != null &&
        (existing['syncStatus']?.toString().toLowerCase() ?? '') == 'pending') {
      return existingId.isNotEmpty ? existingId : localKey.toString();
    }

    localKey ??= 'cloud_${detail.id}';
    final localId = existingId.isNotEmpty ? existingId : localKey.toString();
    final now = DateTime.now().toIso8601String();
    final points = _pointsFromDetail(detail);
    final cached = <String, dynamic>{
      ...?existing,
      'id': localId,
      'cloudId': detail.id,
      'entityType': detail.type,
      'type': detail.type,
      'name': detail.name,
      'place': detail.place,
      'phone': detail.phone,
      'description': detail.description,
      if ((detail.referenceEllipsoid ?? '').trim().isNotEmpty)
        'referenceEllipsoid': detail.referenceEllipsoid,
      'points': points,
      'labels': points.map((point) => point['label'] ?? '').toList(),
      'syncStatus': 'synced',
      'syncError': null,
      'createdAt': detail.createdAt ?? existing?['createdAt'] ?? now,
      'updatedAt': detail.updatedAt ?? now,
      'lastSyncedAt': now,
    };
    cached.removeWhere((key, value) => value == null);
    await box.put(localKey, cached);
    return localId;
  }

  List<Map<String, dynamic>> _pointsFromDetail(LandDetail detail) {
    final points = <Map<String, dynamic>>[];
    for (var index = 0; index < detail.points.length; index++) {
      final point = detail.points[index];
      if (point.x == null || point.y == null) continue;
      points.add(
        {
          'order': point.pointOrder > 0 ? point.pointOrder - 1 : index,
          'cloudPointId': point.id,
          'lat': point.y,
          'lng': point.x,
          if (point.easting != null) 'easting': point.easting,
          if (point.northing != null) 'northing': point.northing,
          if (point.zone != null) 'zone': point.zone,
          if (point.band != null) 'band': point.band,
          if (point.hemisphere != null) 'hemisphere': point.hemisphere,
          if (point.label != null) 'label': point.label,
        }..removeWhere((key, value) => value == null),
      );
    }
    return points;
  }

  /// Saves a cloud land metadata edit locally before any network request.
  ///
  /// The normal background sync will upload this pending edit when a usable
  /// connection is available. If this device has never stored the cloud land,
  /// [detail] supplies the coordinates needed to create its local shadow copy.
  Future<void> queueMetadataEdit({
    required LandDetail detail,
    required String name,
    String? place,
    String? phone,
    String? description,
  }) async {
    dynamic localKey;
    Map<String, dynamic>? existing;

    for (final entry in box.toMap().entries) {
      if (entry.value is! Map) continue;
      final candidate = Map<String, dynamic>.from(entry.value as Map);
      final localId = candidate['id']?.toString().trim() ?? '';
      final cloudId = candidate['cloudId']?.toString().trim() ?? '';
      if (localId == detail.id || cloudId == detail.id) {
        localKey = entry.key;
        existing = candidate;
        break;
      }
    }

    localKey ??= 'cloud_${detail.id}';
    final now = DateTime.now().toIso8601String();
    final points = existing?['points'] is List
        ? existing!['points'] as List
        : detail.points
              .map(
                (point) => <String, dynamic>{
                  'order': point.pointOrder,
                  'lat': point.y,
                  'lng': point.x,
                  if (point.easting != null) 'easting': point.easting,
                  if (point.northing != null) 'northing': point.northing,
                  if (point.zone != null) 'zone': point.zone,
                  if (point.band != null) 'band': point.band,
                  if (point.hemisphere != null) 'hemisphere': point.hemisphere,
                  if (point.label != null) 'label': point.label,
                },
              )
              .toList();

    final updated = <String, dynamic>{
      ...?existing,
      'id': existing?['id']?.toString() ?? localKey.toString(),
      'cloudId': detail.id,
      'entityType': detail.type,
      'type': detail.type,
      'name': name.trim(),
      'place': place?.trim(),
      'phone': phone?.trim(),
      'description': description?.trim(),
      'points': points,
      'labels': detail.points.map((point) => point.label ?? '').toList(),
      'syncStatus': 'pending',
      'syncError': null,
      'createdAt': existing?['createdAt'] ?? detail.createdAt ?? now,
      'updatedAt': now,
    };
    updated.removeWhere(
      (key, value) =>
          value == null ||
          (value is String &&
              value.isEmpty &&
              const {'place', 'phone', 'description'}.contains(key)),
    );
    await box.put(localKey, updated);
  }

  Future<LandSyncResult> syncPendingLands({int limit = 10}) async {
    await _runLegacySyncMigrationIfNeeded();

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
        .where((entry) {
          final entityType = entry.value['entityType']?.toString() ?? '';
          final isSupported =
              entityType == 'land' ||
              entityType == 'polygon' ||
              entityType == 'polyline' ||
              entityType == 'point';
          final cloudId = (entry.value['cloudId']?.toString() ?? '').trim();
          final syncStatus = (entry.value['syncStatus']?.toString() ?? '')
              .trim()
              .toLowerCase();
          final isPending =
              syncStatus == 'pending' ||
              (syncStatus.isEmpty && cloudId.isEmpty);
          return isSupported && isPending;
        })
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
    final attemptStampedLand = await _markSyncAttempt(key, land);

    final pointEntries = _extractPointEntries(attemptStampedLand);
    final points = pointEntries
        .map((e) => LatLng(e['lat'] as double, e['lng'] as double))
        .toList();
    final type = _normalizeLandType(attemptStampedLand);
    final minimumPoints = type == 'point' ? 1 : (type == 'polyline' ? 2 : 3);

    if (points.length < minimumPoints) {
      final err = 'Not enough points to sync.';
      await _markSyncFailed(key, attemptStampedLand, err);
      return err;
    }

    final payload = _buildPayload(attemptStampedLand, pointEntries);
    final cloudId = (attemptStampedLand['cloudId']?.toString() ?? '').trim();
    if (cloudId.isNotEmpty) {
      try {
        final remoteDetail = await cloudService.getLand(bearerToken, cloudId);
        if (!_sameBoundary(pointEntries, remoteDetail.points)) {
          const err =
              'Boundary changes are saved locally, but the cloud API does not '
              'support updating land coordinates yet.';
          await _markSyncFailed(key, attemptStampedLand, err);
          return err;
        }
        final updateRequest = _buildUpdateRequest(
          attemptStampedLand,
          pointEntries,
          remoteDetail.points,
        );
        await cloudService.updateLand(bearerToken, cloudId, updateRequest);
        await _markSynced(key, attemptStampedLand, cloudId);
        return null;
      } catch (error) {
        final message = error.toString();
        if (!_isRemoteRecordMissing(message)) {
          final err = message.trim().isEmpty
              ? 'Failed to sync land to server.'
              : message;
          await _markSyncFailed(key, attemptStampedLand, err);
          return err;
        }
      }
    }

    try {
      final created = await cloudService.createLand(bearerToken, payload);
      await _markSynced(key, attemptStampedLand, created.id);
      return null;
    } catch (error) {
      final err = error.toString().trim().isEmpty
          ? 'Failed to sync land to server.'
          : error.toString();
      await _markSyncFailed(key, attemptStampedLand, err);
      return err;
    }
  }

  Future<void> _runLegacySyncMigrationIfNeeded() async {
    final currentVersion =
        (box.get(_syncSchemaVersionKey) as num?)?.toInt() ?? 0;
    if (currentVersion >= _currentSyncSchemaVersion) return;

    final entries = box.toMap().entries.where((entry) => entry.value is Map);
    for (final entry in entries) {
      final raw = Map<String, dynamic>.from(entry.value as Map);
      final normalized = _migrateLegacyRecord(raw);
      if (!_mapsEqual(raw, normalized)) {
        await box.put(entry.key, normalized);
      }
    }

    await box.put(_syncSchemaVersionKey, _currentSyncSchemaVersion);
  }

  Map<String, dynamic> _migrateLegacyRecord(Map<String, dynamic> land) {
    final entityType = (land['entityType']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final isSupported =
        entityType == 'land' ||
        entityType == 'polygon' ||
        entityType == 'polyline' ||
        entityType == 'point';
    if (!isSupported) return land;

    final updated = <String, dynamic>{...land};
    final cloudId = (updated['cloudId']?.toString() ?? '').trim();
    final syncStatus = (updated['syncStatus']?.toString() ?? '')
        .trim()
        .toLowerCase();

    if (syncStatus.isEmpty) {
      updated['syncStatus'] = cloudId.isNotEmpty ? 'synced' : 'pending';
    }

    if (!updated.containsKey('syncError')) {
      updated['syncError'] = null;
    }

    if (!updated.containsKey('syncAttempts')) {
      updated['syncAttempts'] = 0;
    }

    return updated;
  }

  bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (left[key] != right[key]) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _markSyncAttempt(
    dynamic key,
    Map<String, dynamic> land,
  ) async {
    final attempts = _syncAttemptsFrom(land) + 1;
    final updated = {
      ...land,
      'syncAttempts': attempts,
      'lastSyncAttemptAt': DateTime.now().toIso8601String(),
    };
    await box.put(key, updated);
    return updated;
  }

  int _syncAttemptsFrom(Map<String, dynamic> land) {
    final raw = land['syncAttempts'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _extractPointEntries(Map<String, dynamic> land) {
    final rawPoints = (land['points'] as List?) ?? const [];
    final labels = ((land['labels'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final points = <Map<String, dynamic>>[];
    for (int index = 0; index < rawPoints.length; index++) {
      final item = rawPoints[index];
      if (item is! Map) continue;
      final lat = (item['lat'] as num?)?.toDouble();
      final lng = (item['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final point = Map<String, dynamic>.from(item);
      points.add({
        ...point,
        'lat': lat,
        'lng': lng,
        'label': _extractPointLabel(point, labels, index),
      });
    }
    return points;
  }

  String? _extractPointLabel(
    Map<String, dynamic> point,
    List<String> labels,
    int index,
  ) {
    final directLabel = _trimOrNull(point['label']?.toString());
    if (directLabel != null) return directLabel;
    if (index < labels.length) {
      return _trimOrNull(labels[index]);
    }
    return null;
  }

  CreateLandRequest _buildPayload(
    Map<String, dynamic> land,
    List<Map<String, dynamic>> pointEntries,
  ) {
    final firstName = (box.get('auth_first_name')?.toString() ?? '').trim();
    final lastName = (box.get('auth_last_name')?.toString() ?? '').trim();
    final email = (box.get('auth_email')?.toString() ?? '').trim();
    final owner = [
      firstName,
      lastName,
    ].where((name) => name.isNotEmpty).join(' ').trim();
    final ellipsoid = _resolveReferenceEllipsoid(land);
    final fallbackPhone = _trimOrNull(box.get('submit_phone')?.toString());
    final normalizedPhone =
        _trimOrNull(land['phone']?.toString()) ?? fallbackPhone;
    final normalizedDescription =
        _trimOrNull(land['description']?.toString()) ??
        (owner.isEmpty && email.isEmpty
            ? null
            : 'Captured by ${owner.isNotEmpty ? owner : email}');

    return CreateLandRequest(
      type: _normalizeLandType(land),
      name: (land['name']?.toString() ?? '').trim().isEmpty
          ? 'Land ${DateTime.now().toIso8601String()}'
          : land['name'].toString().trim(),
      place: _trimOrNull(land['place']?.toString()),
      phone: normalizedPhone,
      description: normalizedDescription,
      referenceEllipsoid: ellipsoid.displayName,
      coordinates: pointEntries.map((entry) {
        return _latLngToServerCoordinate(
          LatLng(entry['lat'] as double, entry['lng'] as double),
          label: entry['label'] as String?,
          ellipsoid: ellipsoid,
        );
      }).toList(),
    );
  }

  UpdateLandRequest _buildUpdateRequest(
    Map<String, dynamic> land,
    List<Map<String, dynamic>> pointEntries,
    List<LandPoint> remotePoints,
  ) {
    final fallbackPhone = _trimOrNull(box.get('submit_phone')?.toString());
    final orderedRemotePoints = [...remotePoints]
      ..sort((left, right) => left.pointOrder.compareTo(right.pointOrder));
    final pointUpdates = <LandPointUpdateRequest>[];
    for (
      var index = 0;
      index < pointEntries.length && index < orderedRemotePoints.length;
      index++
    ) {
      final remoteId = orderedRemotePoints[index].id;
      if (remoteId == null) continue;
      pointUpdates.add(
        LandPointUpdateRequest(
          id: remoteId,
          label: pointEntries[index]['label'] as String?,
        ),
      );
    }
    return UpdateLandRequest(
      name: _trimOrNull(land['name']?.toString()),
      place: _trimOrNull(land['place']?.toString()),
      phone: _trimOrNull(land['phone']?.toString()) ?? fallbackPhone,
      description: _trimOrNull(land['description']?.toString()),
      points: pointUpdates,
    );
  }

  bool _sameBoundary(
    List<Map<String, dynamic>> localPoints,
    List<LandPoint> remotePoints,
  ) {
    if (localPoints.length != remotePoints.length) return false;
    final orderedRemotePoints = [...remotePoints]
      ..sort((left, right) => left.pointOrder.compareTo(right.pointOrder));
    const toleranceDegrees = 1e-7;
    for (var index = 0; index < localPoints.length; index++) {
      final localLat = localPoints[index]['lat'] as double;
      final localLng = localPoints[index]['lng'] as double;
      final remoteLat = orderedRemotePoints[index].y;
      final remoteLng = orderedRemotePoints[index].x;
      if (remoteLat == null || remoteLng == null) return false;
      if ((localLat - remoteLat).abs() > toleranceDegrees ||
          (localLng - remoteLng).abs() > toleranceDegrees) {
        return false;
      }
    }
    return true;
  }

  String _normalizeLandType(Map<String, dynamic> land) {
    final rawType =
        (land['type']?.toString() ??
                land['entityType']?.toString() ??
                'polygon')
            .trim()
            .toLowerCase();
    if (rawType == 'point' || rawType == 'polyline' || rawType == 'polygon') {
      return rawType;
    }
    if (rawType == 'land') {
      return 'polygon';
    }
    return 'polygon';
  }

  LandCoordinateRequest _latLngToServerCoordinate(
    LatLng point, {
    String? label,
    required ReferenceEllipsoid ellipsoid,
  }) {
    final zone = _utmZone(point.latitude, point.longitude);
    double? easting;
    double? northing;
    final utm = UtmConverter.fromLatLng(
      point.latitude,
      point.longitude,
      ellipsoid,
    );
    if (utm != null) {
      easting = double.parse(utm.easting.toStringAsFixed(2));
      northing = double.parse(utm.northing.toStringAsFixed(2));
    }

    return LandCoordinateRequest(
      x: point.longitude,
      y: point.latitude,
      z: 0,
      zone: zone.toString(),
      band: _utmBand(point.latitude),
      hemisphere: point.latitude >= 0 ? 'N' : 'S',
      easting: easting,
      northing: northing,
      label: _trimOrNull(label),
    );
  }

  ReferenceEllipsoid _resolveReferenceEllipsoid(Map<String, dynamic> land) {
    final rawFromLand = _trimOrNull(land['referenceEllipsoid']?.toString());
    if (rawFromLand != null) {
      return ReferenceEllipsoid.fromRaw(rawFromLand);
    }

    final rawFromPrefs = _trimOrNull(
      box.get(_referenceEllipsoidPrefKey)?.toString(),
    );
    return ReferenceEllipsoid.fromRaw(rawFromPrefs);
  }

  String? _trimOrNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  bool _isRemoteRecordMissing(String errorText) {
    final normalized = errorText.toLowerCase();
    return normalized.contains('404') || normalized.contains('not found');
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
      'lastSyncAttemptAt': DateTime.now().toIso8601String(),
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
