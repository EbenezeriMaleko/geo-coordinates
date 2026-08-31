import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:taref_gps/features/land_map/models/land_api_models.dart';
import 'package:taref_gps/features/land_map/services/land_cloud_service.dart';
import 'package:taref_gps/features/land_map/services/land_sync_service.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('land_sync_test_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('landbox_test');
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('cloud metadata edit is saved locally and queued for sync', () async {
    const detail = LandDetail(
      id: 'remote-123',
      userId: 'user-1',
      type: 'point',
      name: 'Old name',
      place: 'Old place',
      phone: null,
      area: null,
      perimeter: null,
      description: null,
      pointsCount: 1,
      markersCount: 0,
      mediaCount: 0,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: null,
      points: [
        LandPoint({'point_order': 0, 'x': 39.185703, 'y': -6.655303}),
      ],
      markers: [],
      media: [],
    );

    await LandSyncService(box).queueMetadataEdit(
      detail: detail,
      name: 'Edited offline',
      place: 'Dar es Salaam',
    );

    final saved = Map<String, dynamic>.from(box.get('cloud_remote-123') as Map);
    expect(saved['cloudId'], 'remote-123');
    expect(saved['name'], 'Edited offline');
    expect(saved['place'], 'Dar es Salaam');
    expect(saved['syncStatus'], 'pending');
    expect(saved['syncError'], isNull);
    expect(saved['points'], hasLength(1));
    expect((saved['points'] as List).single['lat'], -6.655303);
    expect((saved['points'] as List).single['lng'], 39.185703);
  });

  test(
    'cloud-only record is cached as an editable synced local copy',
    () async {
      const detail = LandDetail(
        id: '636',
        userId: 'user-1',
        type: 'polygon',
        name: 'Cloud field',
        place: 'Dar es Salaam',
        phone: null,
        area: null,
        perimeter: null,
        description: null,
        referenceEllipsoid: 'WGS 84',
        pointsCount: 3,
        markersCount: 0,
        mediaCount: 0,
        createdAt: null,
        updatedAt: null,
        points: [
          LandPoint({'id': 1, 'point_order': 1, 'x': 39.28, 'y': -6.80}),
          LandPoint({'id': 2, 'point_order': 2, 'x': 39.29, 'y': -6.81}),
          LandPoint({'id': 3, 'point_order': 3, 'x': 39.30, 'y': -6.82}),
        ],
        markers: [],
        media: [],
      );

      final localId = await LandSyncService(box).cacheCloudLand(detail);

      expect(localId, 'cloud_636');
      final cached = Map<String, dynamic>.from(box.get(localId) as Map);
      expect(cached['cloudId'], '636');
      expect(cached['syncStatus'], 'synced');
      expect(cached['referenceEllipsoid'], 'WGS 84');
      expect(cached['points'], hasLength(3));
      expect((cached['points'] as List).first['cloudPointId'], 1);
    },
  );

  test('cloud caching does not overwrite pending local edits', () async {
    await box.put('local-636', {
      'id': 'local-636',
      'cloudId': '636',
      'name': 'Pending mobile name',
      'syncStatus': 'pending',
      'points': const [
        {'lat': -6.8, 'lng': 39.28},
      ],
    });
    const detail = LandDetail(
      id: '636',
      userId: 'user-1',
      type: 'point',
      name: 'Newer cloud name',
      place: null,
      phone: null,
      area: null,
      perimeter: null,
      description: null,
      pointsCount: 1,
      markersCount: 0,
      mediaCount: 0,
      createdAt: null,
      updatedAt: null,
      points: [],
      markers: [],
      media: [],
    );

    final localId = await LandSyncService(box).cacheCloudLand(detail);

    expect(localId, 'local-636');
    final cached = Map<String, dynamic>.from(box.get('local-636') as Map);
    expect(cached['name'], 'Pending mobile name');
    expect(cached['syncStatus'], 'pending');
  });

  test('editing an existing local shadow preserves its coordinates', () async {
    const originalPoints = [
      {'lat': -6.8, 'lng': 39.2833, 'label': 'A'},
    ];
    await box.put('local-1', {
      'id': 'local-1',
      'cloudId': 'remote-123',
      'entityType': 'point',
      'name': 'Old name',
      'points': originalPoints,
      'syncStatus': 'synced',
    });
    const detail = LandDetail(
      id: 'remote-123',
      userId: 'user-1',
      type: 'point',
      name: 'Old name',
      place: null,
      phone: null,
      area: null,
      perimeter: null,
      description: null,
      pointsCount: 1,
      markersCount: 0,
      mediaCount: 0,
      createdAt: null,
      updatedAt: null,
      points: [],
      markers: [],
      media: [],
    );

    await LandSyncService(
      box,
    ).queueMetadataEdit(detail: detail, name: 'New name');

    final saved = Map<String, dynamic>.from(box.get('local-1') as Map);
    expect(saved['name'], 'New name');
    expect(saved['points'], originalPoints);
    expect(saved['syncStatus'], 'pending');
  });

  test('update request serializes server point IDs and labels', () {
    const request = UpdateLandRequest(
      name: 'Updated field',
      points: [LandPointUpdateRequest(id: 1320, label: 'Point 02')],
    );

    final json = request.toJson();
    expect(json['points'], hasLength(1));
    expect((json['points'] as List).single['id'], 1320);
    expect((json['points'] as List).single['label'], 'Point 02');
  });

  test('pending cloud update sends locally edited point labels', () async {
    final cloud = _RecordingLandCloudService();
    await box.put('auth_token', 'test-token');
    await box.put('auth_is_verified', true);
    await box.put('local-field', {
      'id': 'local-field',
      'cloudId': '636',
      'entityType': 'polygon',
      'type': 'polygon',
      'name': 'Simulator Testing',
      'referenceEllipsoid': 'wgs84',
      'syncStatus': 'pending',
      'points': const [
        {'lat': -6.80, 'lng': 39.28, 'label': 'Point 01'},
        {'lat': -6.81, 'lng': 39.29, 'label': 'Point 02'},
        {'lat': -6.82, 'lng': 39.30, 'label': 'Point 03'},
      ],
    });

    final result = await LandSyncService(
      box,
      cloudService: cloud,
    ).syncPendingLands();

    expect(result.synced, 1);
    expect(cloud.updatedLandId, '636');
    final points = cloud.updateRequest!.toJson()['points'] as List;
    expect(points.map((point) => point['id']), [1319, 1320, 1321]);
    expect(points.map((point) => point['label']), [
      'Point 01',
      'Point 02',
      'Point 03',
    ]);
  });
}

class _RecordingLandCloudService extends LandCloudService {
  String? updatedLandId;
  UpdateLandRequest? updateRequest;

  @override
  Future<LandDetail> getLand(String bearerToken, String landId) async {
    return const LandDetail(
      id: '636',
      userId: 'user-1',
      type: 'polygon',
      name: 'Simulator Testing',
      place: null,
      phone: null,
      area: null,
      perimeter: null,
      description: null,
      pointsCount: 3,
      markersCount: 0,
      mediaCount: 0,
      createdAt: null,
      updatedAt: null,
      points: [
        LandPoint({'id': 1319, 'point_order': 1, 'x': 39.28, 'y': -6.80}),
        LandPoint({'id': 1320, 'point_order': 2, 'x': 39.29, 'y': -6.81}),
        LandPoint({'id': 1321, 'point_order': 3, 'x': 39.30, 'y': -6.82}),
      ],
      markers: [],
      media: [],
    );
  }

  @override
  Future<LandListItem> updateLand(
    String bearerToken,
    String landId,
    UpdateLandRequest request,
  ) async {
    updatedLandId = landId;
    updateRequest = request;
    return const LandListItem(
      id: '636',
      userId: 'user-1',
      type: 'polygon',
      name: 'Simulator Testing',
      place: null,
      phone: null,
      area: null,
      perimeter: null,
      description: null,
      pointsCount: 3,
      markersCount: 0,
      mediaCount: 0,
      createdAt: null,
      updatedAt: null,
    );
  }
}
