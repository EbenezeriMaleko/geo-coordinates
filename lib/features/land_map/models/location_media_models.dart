import '../../../core/network/api_client.dart';

class LocationMediaLocationSummary {
  final String id;
  final String name;
  final String? place;
  final String? address;
  final String? description;
  final double? latitude;
  final double? longitude;

  const LocationMediaLocationSummary({
    required this.id,
    required this.name,
    required this.place,
    required this.address,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  factory LocationMediaLocationSummary.fromJson(Map<String, dynamic> json) {
    return LocationMediaLocationSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Saved location',
      place: json['place']?.toString(),
      address: json['address']?.toString(),
      description: json['description']?.toString(),
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
    );
  }
}

class CreateLocationRequest {
  final String? name;
  final String? description;
  final double? latitude;
  final double? longitude;

  const CreateLocationRequest({
    this.name,
    this.description,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() =>
      {
        'name': name?.trim(),
        'description': description?.trim(),
        'latitude': latitude,
        'longitude': longitude,
      }..removeWhere(
        (key, value) => value == null || (value is String && value.isEmpty),
      );
}

class LocationMediaItem {
  final String id;
  final String locationId;
  final String userId;
  final String fileName;
  final String filePath;
  final String url;
  final String mimeType;
  final String type;
  final int fileSize;
  final LocationMediaLocationSummary? location;
  final String? createdAt;
  final String? updatedAt;

  const LocationMediaItem({
    required this.id,
    required this.locationId,
    required this.userId,
    required this.fileName,
    required this.filePath,
    required this.url,
    required this.mimeType,
    required this.type,
    required this.fileSize,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocationMediaItem.fromJson(Map<String, dynamic> json) {
    return LocationMediaItem(
      id: json['id']?.toString() ?? '',
      locationId: json['location_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      filePath: json['file_path']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      mimeType: json['mime_type']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      location: (json['location'] as Map?) == null
          ? null
          : LocationMediaLocationSummary.fromJson(
              Map<String, dynamic>.from(json['location'] as Map),
            ),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  bool get isVideo =>
      type.toLowerCase() == 'video' || mimeType.startsWith('video/');

  bool get isImage => !isVideo;

  String get resolvedUrl {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '${ApiClient.originUrl()}$url';
  }
}

class LocationRecord {
  final String id;
  final String userId;
  final String? name;
  final String? description;
  final double? latitude;
  final double? longitude;
  final int mediaCount;
  final List<LocationMediaItem> media;
  final String? createdAt;
  final String? updatedAt;

  const LocationRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.mediaCount,
    required this.media,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocationRecord.fromJson(Map<String, dynamic> json) {
    return LocationRecord(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      mediaCount: (json['media_count'] as num?)?.toInt() ?? 0,
      media: ((json['media'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                LocationMediaItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

class PaginatedLocationRecords {
  final List<LocationRecord> items;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;

  const PaginatedLocationRecords({
    required this.items,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
  });

  factory PaginatedLocationRecords.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PaginatedLocationRecords(
      items: ((json['data'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => LocationRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? 0,
      perPage: (meta['per_page'] as num?)?.toInt() ?? 20,
      currentPage: (meta['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
    );
  }
}

class PaginatedLocationMedia {
  final List<LocationMediaItem> items;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;

  const PaginatedLocationMedia({
    required this.items,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
  });

  factory PaginatedLocationMedia.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PaginatedLocationMedia(
      items: ((json['data'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                LocationMediaItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? 0,
      perPage: (meta['per_page'] as num?)?.toInt() ?? 10,
      currentPage: (meta['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
    );
  }
}
