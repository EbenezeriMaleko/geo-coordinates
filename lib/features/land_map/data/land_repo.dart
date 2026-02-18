import 'package:hive/hive.dart';

class LandRepo {
  final Box box;
  LandRepo(this.box);

  Future<void> saveLand(Map<String, dynamic> payload) async {
    await box.put(payload['id'], payload);
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final raw = box.get(id);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> updateLand(String id, Map<String, dynamic> payload) async {
    await box.put(id, payload);
  }
}
