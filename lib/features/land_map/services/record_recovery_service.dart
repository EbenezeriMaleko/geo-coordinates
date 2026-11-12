import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../workspaces/workspace_context.dart';
import '../../workspaces/workspace_provider.dart';
import 'land_cloud_service.dart';
import 'land_sync_service.dart';

typedef RecoveryQuery = ({
  int? company,
  String? record,
  String search,
  int page,
});
typedef VersionQuery = ({int? company, String record, int version});

class RecordRecoveryService {
  Future<Map<String, dynamic>> read(Future<http.Response> request) async {
    final response = await request;
    final decoded = jsonDecode(response.body);
    final body = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = body['errors'];
      final messages = errors is Map
          ? errors.values
                .whereType<List>()
                .expand((values) => values)
                .whereType<String>()
                .toList()
          : <String>[];
      throw Exception(
        messages.isNotEmpty
            ? messages.first
            : body['message'] ?? 'Unable to complete record recovery.',
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> list(String token, RecoveryQuery query) async {
    final body = await read(
      ApiClient.getJson(
        query.record == null
            ? '/lands/trash'
            : '/lands/${query.record}/versions',
        bearerToken: token,
        queryParameters: {
          'page': query.page,
          if (query.record == null) 'search': query.search,
        },
      ),
    );
    if (body['data'] is! List || body['meta'] is! Map) {
      throw Exception('Unexpected recovery response.');
    }
    return body;
  }

  Future<Map<String, dynamic>> version(
    String token,
    String record,
    int version,
  ) async {
    final body = await read(
      ApiClient.getJson('/lands/$record/versions/$version', bearerToken: token),
    );
    if (body['data'] is! Map) throw Exception('Unexpected version response.');
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> restore(
    String token,
    String record, {
    int? version,
    String? revision,
  }) async {
    await read(
      ApiClient.postJson(
        version == null
            ? '/lands/$record/restore'
            : '/lands/$record/versions/$version/restore',
        bearerToken: token,
        body: {if (version != null) 'expected_revision': revision},
      ),
    );
  }

  bool pending(String record) =>
      Hive.box('landbox').values.whereType<Map>().any(
        (item) =>
            WorkspaceContext.belongsToActiveWorkspace(
              Map<String, dynamic>.from(item),
            ) &&
            (item['cloudId']?.toString() == record ||
                item['id']?.toString() == record) &&
            item['syncStatus'] == 'pending',
      );

  Future<void> refreshCache(String token, int? company, String record) async {
    final detail = await LandCloudService().getLand(token, record);
    final box = Hive.box('landbox');
    if (WorkspaceContext.activeCompanyId != company ||
        box.get('auth_token') != token) {
      return;
    }
    await LandSyncService(box).cacheCloudLand(detail);
  }
}

final recordRecoveryServiceProvider = Provider<RecordRecoveryService>(
  (ref) => RecordRecoveryService(),
);
final recoveryListProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, RecoveryQuery>((ref, query) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isLoggedIn ||
          !session.isVerified ||
          workspace.isLoading ||
          workspace.activeCompanyId != query.company) {
        throw Exception('Workspace or account changed. Reopen recovery.');
      }
      return ref.read(recordRecoveryServiceProvider).list(session.token, query);
    });
final recoveryVersionProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, VersionQuery>((ref, query) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isLoggedIn ||
          !session.isVerified ||
          workspace.isLoading ||
          workspace.activeCompanyId != query.company) {
        throw Exception('Workspace or account changed. Reopen history.');
      }
      return ref
          .read(recordRecoveryServiceProvider)
          .version(session.token, query.record, query.version);
    });
