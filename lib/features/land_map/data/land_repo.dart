import 'package:hive/hive.dart';

class LandRepo {
  final Box box;
  LandRepo(this.box);

  Future<void> saveLand(Map<String, dynamic> payload) async {
    await box.put(payload['id'], payload);
  }
}
