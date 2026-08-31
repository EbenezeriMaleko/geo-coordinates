import 'package:hive/hive.dart';

class LandRepo {
  final Box box;
  LandRepo(this.box);

  Future<void> saveLand(Map<String, dynamic> payload) async {
    await box.put(payload['id'], payload);
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final key = _resolveStorageKey(id);
    if (key == null) return null;
    final raw = box.get(key);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> updateLand(String id, Map<String, dynamic> payload) async {
    final key = _resolveStorageKey(id);
    if (key == null) return;
    await box.put(key, payload);
  }

  /// Resolves both the immutable local ID and the server ID assigned later.
  dynamic _resolveStorageKey(String id) {
    if (box.containsKey(id)) return id;
    for (final entry in box.toMap().entries) {
      if (entry.value is! Map) continue;
      final record = Map<String, dynamic>.from(entry.value as Map);
      final localId = record['id']?.toString().trim() ?? '';
      final cloudId = record['cloudId']?.toString().trim() ?? '';
      if (localId == id || cloudId == id) return entry.key;
    }
    return null;
  }
}
