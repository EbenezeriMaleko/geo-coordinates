import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class AuthDeviceIdentity {
  static const key = 'auth_installation_device_id';

  Future<Map<String, String>> metadata() async {
    final box = Hive.box('landbox');
    var id = box.get(key)?.toString().trim() ?? '';
    if (id.isEmpty) {
      id = const Uuid().v4();
      await box.put(key, id);
    }
    return {
      'device_id': id,
      'device_name':
          'TaREF GPS - ${kIsWeb ? 'Web' : defaultTargetPlatform.name}',
    };
  }
}
