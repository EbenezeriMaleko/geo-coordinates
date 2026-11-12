import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taref_gps/features/workspaces/workspace_context.dart';
import 'package:taref_gps/features/land_map/models/land_api_models.dart';
import 'package:taref_gps/features/land_map/services/land_cloud_service.dart';
import 'package:taref_gps/features/land_map/services/land_sync_service.dart';

class _QuotaService extends LandCloudService {
  int calls = 0;
  Future<void> Function()? duringRequest;
  bool succeeds = false;
  @override
  Future<LandListItem> createLand(
    String token,
    CreateLandRequest request,
  ) async {
    calls++;
    await duringRequest?.call();
    if (succeeds)
      return LandListItem.fromJson({
        'id': 'cloud-confirmed',
        'name': 'Uploaded',
        'type': 'point',
      });
    throw const LandCloudException(
      'Record allowance reached',
      statusCode: 422,
      validationFields: {'records'},
    );
  }
}

void main() {
  late Directory directory;
  late Box box;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('workspace_sync_safety_');
    Hive.init(directory.path);
    box = await Hive.openBox('landbox');
    await box.putAll({
      'auth_token': 'synthetic-test-token',
      'auth_is_verified': true,
    });
  });
  tearDown(() async {
    await WorkspaceContext.clear();
    await box.close();
    await directory.delete(recursive: true);
  });
  test(
    'quota rejection keeps draft coordinates and original workspace',
    () async {
      await WorkspaceContext.selectCompany(12);
      final draft = WorkspaceContext.stampRecord({
        'id': 'draft',
        'entityType': 'point',
        'name': 'Field point',
        'syncStatus': 'pending',
        'points': [
          {'lat': -6.8, 'lng': 39.2},
        ],
      });
      await box.put('draft', draft);
      final cloud = _QuotaService();
      await LandSyncService(box, cloudService: cloud).syncPendingLands();
      expect(cloud.calls, 1);
      final saved = Map.from(box.get('draft') as Map);
      expect(saved['points'], draft['points']);
      expect(saved['companyId'], 12);
      expect(saved['syncStatus'], 'pending');
      expect(saved['syncBlockedReason'], 'waiting_for_space');
      await WorkspaceContext.selectCompany(null);
      await LandSyncService(box, cloudService: cloud).syncPendingLands();
      expect(cloud.calls, 1);
      expect(box.containsKey('draft'), isTrue);
    },
  );
  test(
    'successful upload preserves a newer edit and attaches cloud ID',
    () async {
      await WorkspaceContext.selectCompany(12);
      await box.put(
        'draft',
        WorkspaceContext.stampRecord({
          'id': 'draft',
          'entityType': 'point',
          'name': 'Original',
          'updatedAt': '2026-01-01T00:00:00Z',
          'syncStatus': 'pending',
          'points': [
            {'lat': -6.8, 'lng': 39.2},
          ],
        }),
      );
      final cloud = _QuotaService()..succeeds = true;
      cloud.duringRequest = () async {
        final current = Map<String, dynamic>.from(box.get('draft') as Map);
        await box.put('draft', {
          ...current,
          'name': 'Edited during upload',
          'updatedAt': '2026-01-02T00:00:00Z',
        });
      };
      await LandSyncService(box, cloudService: cloud).syncPendingLands();
      final saved = box.get('draft') as Map;
      expect(saved['name'], 'Edited during upload');
      expect(saved['cloudId'], 'cloud-confirmed');
      expect(saved['companyId'], 12);
      expect(saved['syncStatus'], 'pending');
      expect(saved['points'], hasLength(1));
    },
  );

  test('late success cannot recreate a locally deleted record', () async {
    await box.put('draft', {
      'id': 'draft',
      'entityType': 'point',
      'syncStatus': 'pending',
      'points': [
        {'lat': -6.8, 'lng': 39.2},
      ],
    });
    final cloud = _QuotaService()..succeeds = true;
    cloud.duringRequest = () => box.delete('draft');
    await LandSyncService(box, cloudService: cloud).syncPendingLands();
    expect(cloud.calls, 1);
    expect(box.containsKey('draft'), isFalse);
  });
  test(
    'workspace switch during request stops batch without losing newer edits',
    () async {
      await WorkspaceContext.selectCompany(12);
      for (final id in ['first', 'second']) {
        await box.put(
          id,
          WorkspaceContext.stampRecord({
            'id': id,
            'entityType': 'point',
            'name': id,
            'updatedAt': '2026-01-01T00:00:00Z',
            'syncStatus': 'pending',
            'points': [
              {'lat': -6.8, 'lng': 39.2},
            ],
          }),
        );
      }
      final cloud = _QuotaService();
      cloud.duringRequest = () async {
        for (final id in ['first', 'second']) {
          final current = Map<String, dynamic>.from(box.get(id) as Map);
          await box.put(id, {
            ...current,
            'name': 'New local edit',
            'updatedAt': '2026-01-02T00:00:00Z',
          });
        }
        await WorkspaceContext.selectCompany(99);
      };
      await LandSyncService(box, cloudService: cloud).syncPendingLands();
      expect(cloud.calls, 1);
      for (final id in ['first', 'second']) {
        final saved = box.get(id) as Map;
        expect(saved['name'], 'New local edit');
        expect(saved['companyId'], 12);
        expect(saved['syncStatus'], 'pending');
        expect(saved['points'], hasLength(1));
      }
    },
  );
}
