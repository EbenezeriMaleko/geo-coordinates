import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taref_gps/features/land_map/data/land_repo.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> box;
  late LandRepo repo;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('land_repo_test_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<dynamic>('landbox_repo_test');
    repo = LandRepo(box);
  });

  tearDown(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('finds an offline-created record by its later cloud ID', () async {
    await box.put('local-key', {
      'id': 'local-id',
      'cloudId': 'cloud-id',
      'name': 'Synced field',
      'points': const [
        {'lat': -6.8, 'lng': 39.28},
      ],
    });

    final record = await repo.getById('cloud-id');

    expect(record, isNotNull);
    expect(record!['id'], 'local-id');
  });

  test('updates by cloud ID without changing the Hive key', () async {
    await box.put('local-key', {
      'id': 'local-id',
      'cloudId': 'cloud-id',
      'name': 'Before',
    });

    await repo.updateLand('cloud-id', {
      'id': 'local-id',
      'cloudId': 'cloud-id',
      'name': 'After',
      'syncStatus': 'pending',
    });

    expect(box.containsKey('local-key'), isTrue);
    expect(box.containsKey('cloud-id'), isFalse);
    final saved = Map<String, dynamic>.from(box.get('local-key') as Map);
    expect(saved['id'], 'local-id');
    expect(saved['name'], 'After');
    expect(saved['syncStatus'], 'pending');
  });
}
