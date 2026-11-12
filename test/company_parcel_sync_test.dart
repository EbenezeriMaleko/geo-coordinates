import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taref_gps/features/land_map/models/land_api_models.dart';
import 'package:taref_gps/features/land_map/services/land_sync_service.dart';
import 'package:taref_gps/features/workspaces/workspace_context.dart';

void main() {
  late Directory directory;
  late Box box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('company_parcel_');
    Hive.init(directory.path);
    box = await Hive.openBox('landbox');
  });

  tearDown(() async {
    await WorkspaceContext.clear();
    await box.close();
    await directory.delete(recursive: true);
  });

  test(
    'company edits retain clear values and only the masked owner ID',
    () async {
      await WorkspaceContext.selectCompany(12);
      final detail = LandDetail.fromJson({
        'id': 5,
        'name': 'Plot',
        'type': 'point',
        'claimant_id_masked': '****1234',
        'points': [
          {'id': 1, 'point_order': 1, 'x': 39.2, 'y': -6.8},
        ],
      });
      await LandSyncService(box).queueMetadataEdit(
        detail: detail,
        name: 'Plot',
        claimantName: 'Jane Doe',
        claimantPhone: '',
        plotNumber: '12',
        landUse: 'Residential',
      );
      final record = Map<String, dynamic>.from(box.get('cloud_5') as Map);
      expect(record['companyId'], 12);
      expect(record['claimant_name'], 'Jane Doe');
      expect(record['claimant_phone'], '');
      expect(record['claimant_id_masked'], '****1234');
      expect(record.containsKey('claimant_id'), isFalse);
    },
  );

  test('personal metadata edits do not save company claimant fields', () async {
    final detail = LandDetail.fromJson({'id': 6, 'name': 'Personal'});
    await LandSyncService(box).queueMetadataEdit(
      detail: detail,
      name: 'Personal',
      claimantName: 'Ignored',
      claimantPhone: 'Ignored',
    );
    final record = Map<String, dynamic>.from(box.get('cloud_6') as Map);
    expect(record.containsKey('claimant_name'), isFalse);
    expect(record.containsKey('claimant_phone'), isFalse);
  });
}
