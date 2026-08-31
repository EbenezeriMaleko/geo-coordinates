import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:taref_gps/features/land_map/models/land_api_models.dart';
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
}
