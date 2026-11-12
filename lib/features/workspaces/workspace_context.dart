import 'package:hive/hive.dart';

import '../../core/network/api_client.dart';

class WorkspaceContext {
  static const String _activeCompanyKey = 'workspace_active_company_id';
  static int _selectionGeneration = 0;

  static Box get _box => Hive.box('landbox');

  static int? get activeCompanyId =>
      _companyIdFrom(_box.get(_activeCompanyKey));

  static void restore() {
    ApiClient.setActiveCompanyId(activeCompanyId);
  }

  static Future<void> selectCompany(int? companyId) async {
    final generation = ++_selectionGeneration;
    if (companyId == null) {
      await _box.delete(_activeCompanyKey);
    } else {
      await _box.put(_activeCompanyKey, companyId);
    }
    if (generation == _selectionGeneration) {
      ApiClient.setActiveCompanyId(companyId);
    }
  }

  static Future<void> clear() => selectCompany(null);

  static Map<String, dynamic> stampRecord(Map<String, dynamic> record) {
    final companyId = activeCompanyId;
    if (companyId == null) return record;
    return {...record, 'companyId': companyId};
  }

  static bool belongsToActiveWorkspace(Map<String, dynamic> record) {
    return _companyIdFrom(record['companyId']) == activeCompanyId;
  }

  static int? _companyIdFrom(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
