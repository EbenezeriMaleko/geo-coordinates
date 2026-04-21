class LandCoordinateRequest {
  final double x;
  final double y;
  final double? z;
  final String? zone;
  final String? band;
  final String? hemisphere;

  const LandCoordinateRequest({
    required this.x,
    required this.y,
    this.z,
    this.zone,
    this.band,
    this.hemisphere,
  });

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'z': z,
    'zone': zone,
    'band': band,
    'hemisphere': hemisphere,
  }..removeWhere((key, value) => value == null);
}

class CreateLandRequest {
  final String name;
  final String? place;
  final String? phone;
  final String? description;
  final List<LandCoordinateRequest> coordinates;

  const CreateLandRequest({
    required this.name,
    required this.coordinates,
    this.place,
    this.phone,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'place': place?.trim(),
    'phone': phone?.trim(),
    'description': description?.trim(),
    'coordinates': coordinates.map((e) => e.toJson()).toList(),
  }..removeWhere(
    (key, value) =>
        value == null || (value is String && value.isEmpty),
  );
}

class UpdateLandRequest {
  final String? name;
  final String? place;
  final String? phone;
  final String? description;

  const UpdateLandRequest({
    this.name,
    this.place,
    this.phone,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'name': name?.trim(),
    'place': place?.trim(),
    'phone': phone?.trim(),
    'description': description?.trim(),
  }..removeWhere(
    (key, value) =>
        value == null || (value is String && value.isEmpty),
  );
}

class LandMarkerRequest {
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? markerType;
  final String? properties;

  const LandMarkerRequest({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.description,
    this.altitude,
    this.markerType,
    this.properties,
  });

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'description': description?.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'marker_type': markerType?.trim(),
    'properties': properties?.trim(),
  }..removeWhere(
    (key, value) =>
        value == null || (value is String && value.isEmpty),
  );
}

class UpdateLandMarkerRequest {
  final String? name;
  final String? description;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final String? markerType;
  final String? properties;

  const UpdateLandMarkerRequest({
    this.name,
    this.description,
    this.latitude,
    this.longitude,
    this.altitude,
    this.markerType,
    this.properties,
  });

  Map<String, dynamic> toJson() => {
    'name': name?.trim(),
    'description': description?.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'marker_type': markerType?.trim(),
    'properties': properties?.trim(),
  }..removeWhere(
    (key, value) =>
        value == null || (value is String && value.isEmpty),
  );
}

class LandListItem {
  final String id;
  final String userId;
  final String name;
  final String? place;
  final String? phone;
  final double? area;
  final double? perimeter;
  final String? description;
  final String syncStatus;
  final String? lastSyncedAt;
  final int pointsCount;
  final int markersCount;
  final int mediaCount;
  final String? createdAt;
  final String? updatedAt;

  const LandListItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.place,
    required this.phone,
    required this.area,
    required this.perimeter,
    required this.description,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.pointsCount,
    required this.markersCount,
    required this.mediaCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LandListItem.fromJson(Map<String, dynamic> json) {
    return LandListItem(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      place: json['place']?.toString(),
      phone: json['phone']?.toString(),
      area: (json['area'] as num?)?.toDouble(),
      perimeter: (json['perimeter'] as num?)?.toDouble(),
      description: json['description']?.toString(),
      syncStatus: json['sync_status']?.toString() ?? 'pending',
      lastSyncedAt: json['last_synced_at']?.toString(),
      pointsCount: (json['points_count'] as num?)?.toInt() ?? 0,
      markersCount: (json['markers_count'] as num?)?.toInt() ?? 0,
      mediaCount: (json['media_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

class LandPoint {
  final Map<String, dynamic> raw;

  const LandPoint(this.raw);

  factory LandPoint.fromJson(Map<String, dynamic> json) => LandPoint(json);
}

class LandMarker {
  final String id;
  final String landId;
  final String name;
  final String? description;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final String? markerType;
  final String? properties;

  const LandMarker({
    required this.id,
    required this.landId,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.markerType,
    required this.properties,
  });

  factory LandMarker.fromJson(Map<String, dynamic> json) {
    return LandMarker(
      id: json['id']?.toString() ?? '',
      landId: json['land_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      markerType: json['marker_type']?.toString(),
      properties: json['properties']?.toString(),
    );
  }
}

class LandMedia {
  final Map<String, dynamic> raw;

  const LandMedia(this.raw);

  factory LandMedia.fromJson(Map<String, dynamic> json) => LandMedia(json);
}

class LandDetail extends LandListItem {
  final List<LandPoint> points;
  final List<LandMarker> markers;
  final List<LandMedia> media;

  const LandDetail({
    required super.id,
    required super.userId,
    required super.name,
    required super.place,
    required super.phone,
    required super.area,
    required super.perimeter,
    required super.description,
    required super.syncStatus,
    required super.lastSyncedAt,
    required super.pointsCount,
    required super.markersCount,
    required super.mediaCount,
    required super.createdAt,
    required super.updatedAt,
    required this.points,
    required this.markers,
    required this.media,
  });

  factory LandDetail.fromJson(Map<String, dynamic> json) {
    final base = LandListItem.fromJson(json);
    return LandDetail(
      id: base.id,
      userId: base.userId,
      name: base.name,
      place: base.place,
      phone: base.phone,
      area: base.area,
      perimeter: base.perimeter,
      description: base.description,
      syncStatus: base.syncStatus,
      lastSyncedAt: base.lastSyncedAt,
      pointsCount: base.pointsCount,
      markersCount: base.markersCount,
      mediaCount: base.mediaCount,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      points: ((json['points'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LandPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      markers: ((json['markers'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LandMarker.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      media: ((json['media'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LandMedia.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class LandSummary {
  final int totalLands;
  final double totalArea;
  final double totalPerimeter;
  final int syncedCount;
  final int pendingCount;
  final List<LandListItem> recentLands;

  const LandSummary({
    required this.totalLands,
    required this.totalArea,
    required this.totalPerimeter,
    required this.syncedCount,
    required this.pendingCount,
    required this.recentLands,
  });

  factory LandSummary.fromJson(Map<String, dynamic> json) {
    return LandSummary(
      totalLands: (json['total_lands'] as num?)?.toInt() ?? 0,
      totalArea: (json['total_area'] as num?)?.toDouble() ?? 0,
      totalPerimeter: (json['total_perimeter'] as num?)?.toDouble() ?? 0,
      syncedCount: (json['synced_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      recentLands: ((json['recent_lands'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LandListItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class PaginatedLands {
  final List<LandListItem> items;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;

  const PaginatedLands({
    required this.items,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
  });

  factory PaginatedLands.fromJson(Map<String, dynamic> json) {
    final meta =
        (json['meta'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return PaginatedLands(
      items: ((json['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LandListItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? 0,
      perPage: (meta['per_page'] as num?)?.toInt() ?? 15,
      currentPage: (meta['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
    );
  }
}

class PaginatedMarkers {
  final List<LandMarker> items;
  final int total;
  final int perPage;

  const PaginatedMarkers({
    required this.items,
    required this.total,
    required this.perPage,
  });

  factory PaginatedMarkers.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PaginatedMarkers(
      items: ((data['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LandMarker.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? 0,
      perPage: (meta['per_page'] as num?)?.toInt() ?? 50,
    );
  }
}

class SyncLandResult {
  final String id;
  final String syncStatus;
  final String? lastSyncedAt;

  const SyncLandResult({
    required this.id,
    required this.syncStatus,
    required this.lastSyncedAt,
  });

  factory SyncLandResult.fromJson(Map<String, dynamic> json) {
    return SyncLandResult(
      id: json['id']?.toString() ?? '',
      syncStatus: json['sync_status']?.toString() ?? 'pending',
      lastSyncedAt: json['last_synced_at']?.toString(),
    );
  }
}

class RemoteSettingsOptions {
  final List<String> coordinateFormats;
  final List<String> referenceEllipsoids;
  final List<String> units;
  final Map<String, dynamic> userSettings;

  const RemoteSettingsOptions({
    required this.coordinateFormats,
    required this.referenceEllipsoids,
    required this.units,
    required this.userSettings,
  });

  factory RemoteSettingsOptions.fromJson(Map<String, dynamic> json) {
    return RemoteSettingsOptions(
      coordinateFormats: ((json['coordinate_formats'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      referenceEllipsoids:
          ((json['reference_ellipsoids'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
      units: ((json['units'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      userSettings: (json['user_settings'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

class LandMessageResponse {
  final bool success;
  final String message;

  const LandMessageResponse({required this.success, required this.message});

  factory LandMessageResponse.fromJson(Map<String, dynamic> json) {
    return LandMessageResponse(
      success: json['success'] as bool? ?? false,
      message: json['message']?.toString() ?? '',
    );
  }
}
